# GOLD

*(Parte de la [arquitectura general](../../README.md) · Otras etapas: [RAW](../raw/README.md) · [SILVER](../silver/README.md))*

Capa de consumo: esquema en estrella (dimensiones + hechos) optimizado para que Power BI consulte directamente, sin lógica de limpieza de datos — eso ya se resolvió en SILVER. Lo que sí vive aquí es lógica de negocio: clasificación de ligas, cálculo de `SCORE`, y las agregaciones que le dan a cada tabla su grano final.

## Modelo (5 dimensiones, 3 hechos)

- `DIM_PLAYER`, `DIM_CLUB`, `DIM_COMPETITION`, `DIM_SEASON`, `DIM_COUNTRY`
- `FACT_PLAYER_SEASON` (obligatoria, grano: jugador × temporada × club × competición)
- `FACT_CLUB_GAME` (extra, grano: club × partido)
- `FACT_TRANSFER` (extra, grano: fichaje)
- `FACT_PLAYER_MARKET_VALUE` (extra, grano: jugador × fecha de valoración)
- `VW_PLAYER_VALUE_TIMELINE` (extra, **vista**, no tabla -- grano: jugador × fecha de evento, valoración o traspaso)

**Sin `DIM_DATE`.** El enunciado la pide, pero se decidió explícitamente prescindir de ella: ninguna pregunta de negocio necesita el detalle de día/mes/trimestre, y `DIM_SEASON` ya cubre todo el filtrado y las series temporales del informe. Es una desviación consciente del enunciado, a defender como tal ante el tutor.

## Automatización: STREAM + TASK, igual que SILVER

GOLD se planteó primero con `CREATE OR REPLACE TABLE ... AS SELECT` (refresco manual, ejecutando el script cada vez), y después se decidió pasar al mismo patrón `STREAM` + `TASK` que ya usa SILVER, para que la cadena RAW→SILVER→GOLD quede automatizada de punta a punta sin intervención manual.

**Cómo se evita el problema que tuvimos con `TASK_LOAD_COMPETITIONS` en SILVER** (el stream no hace backfill de filas que ya existían antes de crearlo): cada archivo de GOLD sigue este orden exacto — (1) `CREATE TABLE`, (2) un `INSERT` único de siembra que calcula el contenido completo a partir de todo lo que ya hay en SILVER en ese momento, (3) solo **después** de la siembra, `CREATE STREAM`, (4) `CREATE TASK` para los incrementos futuros. Como el stream se crea después de la siembra, su punto de partida ya es "todo lo anterior está reflejado en GOLD" — no hace falta ningún `INSERT` manual posterior, a diferencia de lo que sí tuvimos que hacer en SILVER.

**Automatizar una tabla de HECHOS agregada es distinto de automatizar una dimensión passthrough.** `DIM_CLUB`, `DIM_PLAYER`, `DIM_COMPETITION` son copias 1 a 1 de su tabla SILVER de origen (mismo grano), así que su `STREAM`+`TASK` es idéntico al patrón de SILVER: el stream aporta directamente las filas a insertar/actualizar. `FACT_PLAYER_SEASON` no puede funcionar así, porque agrega `APPEARANCES` a un grano más ancho (jugador-temporada-club-competición) — una aparición nueva no se inserta tal cual, tiene que **recalcular** el agregado de la clave a la que pertenece. Su task hace esto en dos pasos: usa el stream solo para averiguar qué claves de grano se han visto tocadas, y para esas claves recalcula el total completo releyendo toda la tabla `SILVER.APPEARANCES` (no el stream) filtrada a esas claves. Recalcular desde cero, en vez de sumar el delta sobre la fila existente, hace que la task sea segura de re-ejecutar sin riesgo de duplicar goles si Snowflake reintenta la ejecución.

**Límite aceptado (documentado, no un bug):** el stream de `FACT_PLAYER_SEASON` vigila solo `APPEARANCES`; un cambio en `GAMES` o `PLAYER_VALUATIONS` sin una aparición nueva asociada no dispara recomputación hasta que sí llegue una.

**Periodicidad: semanal, anclada a la carga real de ADF, no encadenada con `AFTER`.** Las 8 tasks de GOLD están programadas para los sábados a las 9:00 (Europe/Madrid) — 30 minutos después que las 9 tasks de SILVER (8:30), que a su vez van 30 minutos después de la carga de ADF (8:00). No es un `SCHEDULE` arbitrario: refleja la cadencia real con la que llega dato nuevo (una vez por semana, el mismo día que corre la carga de origen), en vez de comprobar cada pocos minutos algo que en la práctica solo cambia una vez a la semana. Las tasks no están encadenadas entre sí con `AFTER` — se sincronizan por horario fijo, con 30 minutos de margen entre capa y capa para que la anterior tenga tiempo de terminar. Si algún sábado SILVER tardara más de 30 minutos en completarse (improbable con este volumen), GOLD leería esa semana un SILVER todavía a medio actualizar; encadenar con `AFTER` eliminaría ese riesgo, pero para esta carga se consideró suficiente el margen fijo.

## Decisiones de diseño

**`SCORE` — fórmula tipo Bota de Oro, tiered por país de la competición.** `DIM_COMPETITION.TIER` clasifica cada competición en Elite / Medio / Menor:
- **Elite**: las 5 grandes ligas domésticas por nombre fijo (LaLiga, Premier League, Bundesliga, Serie A, Ligue 1), más cualquier competición sin país propio (Champions League, Europa League, Conference League, Super Cup, selecciones) — no tienen posición UEFA de país que consultar, así que se tratan como el nivel más alto disponible.
- **Menor**: países en posición UEFA 22ª o posterior (Rusia, Rumanía, Ucrania, Suecia, en los datos actuales).
- **Medio**: todo lo demás — tanto los países UEFA en posición 6ª-21ª (Países Bajos, Portugal, Bélgica, Turquía, Chequia, Dinamarca, Suiza, Noruega, Grecia, Austria, Polonia, Escocia, Serbia, Croacia) como las ligas fuera del sistema UEFA (EEUU, Arabia Saudí, Australia, Brasil, Corea del Sur, Argentina, México, Japón), que por decisión explícita se tratan igual que un país UEFA de nivel intermedio al no tener coeficiente propio. Cualquier país nuevo no contemplado cae también en Medio por defecto — evita que una liga no prevista rompa silenciosamente el cálculo con un `TIER` nulo.

  Puntuación resultante:

  | Tier | Gol | Asistencia | Amarilla | Roja |
  |---|---|---|---|---|
  | Elite | 2.0 | 1.0 | -1 | -3 |
  | Medio | 1.5 | 0.75 | -1 | -3 |
  | Menor | 1.0 | 0.5 | -1 | -3 |

  La asistencia vale la mitad que el gol en cada tier: el sistema real de la Bota de Oro no cubre asistencias, así que es una extensión propia de la fórmula original, siguiendo la convención habitual en sistemas de puntos de fútbol de que un gol vale más que una asistencia. Las tarjetas restan un valor fijo, igual en las 3 tiers, tal como se pidió explícitamente. `SCORE` se calcula sobre todas las competiciones (domésticas, copas, Champions/Europa League, selecciones) — decisión explícita, distinta de la Bota de Oro real, que solo puntúa liga doméstica.

**Criterio de valor de mercado: último valor dentro de la temporada, no la media.** El valor de mercado es una foto puntual en el tiempo; promediar la valoración de enero con la de agosto mezclaría dos momentos distintos del jugador, cuando lo que interesa en el informe es "cuánto vale ahora mismo / al final de la temporada".

**`DIM_COUNTRY` solo para nacionalidad del jugador, no para país del club.** Evita a propósito el problema de "dimensión de rol" (misma tabla física referenciada dos veces con significado distinto), que en Power BI obligaría a relaciones inactivas + `USERELATIONSHIP()` en DAX. País del club se queda como texto plano en `DIM_CLUB`. La relación real usa `COUNTRY_NAME` (texto), no `COUNTRY_ID`, porque `SILVER.PLAYERS` no trae un id numérico de nacionalidad — solo el nombre del país.

**Sin SCD Tipo 2 en `DIM_PLAYER` / `DIM_CLUB`.** No se versiona históricamente "cómo era el club antes del cambio X". El motivo es que `FACT_TRANSFER` ya captura el histórico de pertenencia a club en cada fecha de fichaje, que es el caso de uso real que importa. Añadir SCD Tipo 2 aquí sería complejidad sin un requisito de negocio detrás.

**`FACT_CLUB_GAME` a grano club-partido, no partido único.** Un partido tiene club local Y club visitante; modelarlo a nivel de partido obligaría a la misma relación activa/inactiva que se evitó en `DIM_COUNTRY`. A grano club-partido, cada fila ya tiene "un" club, y la relación con `DIM_CLUB` es directa. Coincide con el grano ya usado por `SILVER.CLUB_GAMES`, así que su automatización es una copia 1 a 1, igual que las dimensiones.

## Ampliaciones sobre el mínimo del enunciado

**`FACT_TRANSFER`** (de `SILVER.TRANSFERS`): grano = un fichaje. Conecta con la pregunta de "oportunidades" (score alto / valor bajo) mostrando qué pasó realmente en el mercado con esos jugadores.

**`FACT_CLUB_GAME`** (de `SILVER.CLUB_GAMES` + `SILVER.GAMES`): sostiene narrativa de rendimiento de clubes a lo largo de temporadas, más allá de las 5 preguntas mínimas.

**`FACT_PLAYER_MARKET_VALUE`** (de `SILVER.PLAYER_VALUATIONS`): grano = un valor de mercado por jugador y fecha de valoración real (no uno por temporada). Existe únicamente para la página "Detalle Jugador" de Power BI: el gráfico de evolución de valor de mercado de la ficha de jugador necesita ver todos los cambios reales, no el valor único por temporada que ya expone `FACT_PLAYER_SEASON`. Es un passthrough 1 a 1 de `SILVER.PLAYER_VALUATIONS` (mismo patrón de automatización que `DIM_CLUB` o `FACT_TRANSFER`, no el de recálculo de `FACT_PLAYER_SEASON`), así que no fue necesario tocar SILVER para conseguir esto — el histórico completo ya vivía ahí.

**`VW_PLAYER_VALUE_TIMELINE`** (VISTA sobre `FACT_PLAYER_MARKET_VALUE` + `FACT_TRANSFER`): grano = un evento por jugador y fecha (valoración o traspaso), con `EVENT_TYPE` como discriminador. Existe para que el gráfico de evolución de valor de mercado de la ficha de jugador pueda combinarse con barras de importe de traspaso en el mismo eje de fechas. Power BI necesita que el eje de categorías de un gráfico combinado (línea + columnas) sea una única columna de una única tabla; como las fechas de valoración y de traspaso son independientes entre sí y el proyecto no tiene `DIM_DATE`, no había ninguna columna de fecha compartida entre `FACT_PLAYER_MARKET_VALUE` y `FACT_TRANSFER` a la que "engancharse". La solución es un `UNION ALL` de ambas tablas sobre una columna `EVENT_DATE` común, con `MARKET_VALUE_EUR` relleno solo en filas de valoración y `TRANSFER_FEE` (+ `FROM_CLUB_ID`/`TO_CLUB_ID`) solo en filas de traspaso. Se implementa como **vista**, no como tabla con su propio `STREAM`+`TASK`: al construirse sobre dos tablas GOLD que ya están automatizadas de forma independiente, el `UNION ALL` se recalcula al vuelo en cada consulta y nunca puede quedar desincronizado; añadir una tercera automatización (un tercer stream, una tercera task) sería complejidad redundante para un dataset de este volumen.

## Extensiones en el modelo semántico de Power BI

No todo lo que se construyó "sobre" GOLD vive en SQL. El informe (`informe_futbol_mejorado.SemanticModel`) añade, en TMDL, medidas DAX y columnas calculadas sobre `FACT_TRANSFER` que son específicas de un visual concreto y no una entidad de negocio reutilizable por cualquier consumidor de GOLD — ese es el criterio para decidir si algo va en SQL (GOLD) o en el modelo semántico (Power BI): si la lógica es reutilizable y agnóstica del visual, va en GOLD; si solo tiene sentido para alimentar un gráfico concreto del informe, se queda en DAX.

- **Medidas** `Total Invertido` (`SUM(FACT_TRANSFER[TRANSFER_FEE])`) y `Número de Fichajes` (`COUNTROWS(FACT_TRANSFER)`) — alimentan los KPI de la página "Transferencias", en sustitución de los KPI genéricos que traía la página por defecto.
- **Columna calculada `AGE_AT_TRANSFER`** (`DATEDIFF(RELATED(DIM_PLAYER[DATE_OF_BIRTH]), FACT_TRANSFER[TRANSFER_DATE], YEAR)`) — edad del jugador en el momento del fichaje, usando la relación activa `FACT_TRANSFER.PLAYER_ID → DIM_PLAYER.PLAYER_ID`.
- **Columnas calculadas `AGE_BRACKET_SORT`** (oculta, entero 1-6) y **`AGE_BRACKET`** (texto, `< 20 años` ... `36+ años`, con `sortByColumn: AGE_BRACKET_SORT` para que el orden de la franja sea cronológico y no alfabético) — bucketing de `AGE_AT_TRANSFER` en franjas de edad.

Estas tres piezas alimentan el gráfico de burbujas "Edad, Importe Invertido y Nº de Fichajes" de la página Transferencias (X = edad, Y = importe invertido, tamaño = número de fichajes) — se descartó un combo de líneas y barras porque el importe (millones) y el número de fichajes (decenas/cientos) tienen escalas demasiado distintas para compartir un mismo eje.

## Estructura

- `00_setup.sql` — schema `FOOTBALL.GOLD`.
- `01_dim_season.sql`, `02_dim_country.sql`, `03_dim_competition.sql`, `04_dim_club.sql`, `05_dim_player.sql` — dimensiones. `01` y `03` deben ejecutarse antes que `06` (aportan `SEASON_START_DATE`/`SEASON_END_DATE` y `TIER`, que la siembra de `06` necesita).
- `06_fact_player_season.sql`, `07_fact_club_game.sql`, `08_fact_transfer.sql`, `09_fact_player_market_value.sql` — hechos.
- `10_vw_player_value_timeline.sql` — vista de reporting (no tabla; no sigue el patrón `STREAM`+`TASK` de los archivos anteriores, ver "Ampliaciones").
- `reset_gold.sql` — utilidad para vaciar las 9 tablas sin borrar streams ni tasks (la vista `10` no necesita vaciarse: no almacena datos propios).

Cada archivo sigue el mismo patrón que SILVER: `CREATE TABLE` → `INSERT` de siembra → `CREATE STREAM` → `CREATE TASK` con el `MERGE` → `ALTER TASK ... RESUME`. Todas las tasks usan el warehouse `COMPUTE_WH`.

## Pendiente de verificar contra datos reales

- Rango de fechas real de `GAMES` por `SEASON`, para confirmar la convención jul-jun asumida en `01_dim_season.sql`.
- Nombres de país de `PLAYERS.COUNTRY_OF_CITIZENSHIP` que no encuentren coincidencia exacta en `DIM_COUNTRY` (consulta de validación incluida en `02_dim_country.sql`).
- Que `CLUBS.DOMESTIC_COMPETITION_ID` use el mismo formato que `COMPETITIONS.COMPETITION_ID` (consulta de validación incluida en `04_dim_club.sql`).
