# SILVER

*(Parte de la [arquitectura general](../../README.md) · Etapa anterior: [RAW](../raw/README.md) · Siguiente: [GOLD](../gold/README.md))*

Capa de limpieza y tipado. Toma cada tabla RAW (todo STRING) y produce una versión con tipos de dato reales, valores nulos estandarizados y sin duplicados. Es la capa donde se responde a "¿por qué usaba esta función y no otra?".

## Decisiones de diseño

**`TRY_CAST` / `TRY_TO_DATE` / `TRY_TO_NUMBER` en vez de `CAST` / `TO_DATE` / `TO_NUMBER`.** La familia `TRY_*` devuelve `NULL` cuando el valor no se puede convertir, en vez de lanzar un error que aborta toda la carga. Como RAW puede contener cualquier cosa (viene sin validar), es la única forma segura de tipar sin que una fila mala tumbe el proceso completo.

**`NULLIF` + `TRIM` para estandarizar "vacíos".** Un mismo concepto de "sin valor" puede venir representado de formas distintas según el CSV (`''`, `'NA'`, `' '`, `'null'`). `TRIM` quita espacios sobrantes antes de comparar, y `NULLIF(columna, '')` convierte esas representaciones en un `NULL` real y consistente, para que las consultas de GOLD no tengan que lidiar con varias formas distintas de "no hay dato".

**`QUALIFY ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` para deduplicar, en vez de `DISTINCT`.** `DISTINCT` solo sirve si la fila duplicada es idéntica byte a byte. Aquí el caso real es distinto: pueden llegar varias cargas del mismo archivo (o el mismo registro con `_LOADED_AT` distinto) y queremos quedarnos con la versión más reciente por clave de negocio. `ROW_NUMBER() OVER (PARTITION BY <clave> ORDER BY _LOADED_AT DESC) = 1` en un `QUALIFY` expresa exactamente eso: "una fila por clave, la más nueva", cosa que `DISTINCT` no puede hacer.

**`MERGE` para cargas idempotentes.** En vez de truncar y recargar cada vez (caro y sin histórico) o solo insertar (duplica si se reprocesa el mismo archivo), `MERGE ... WHEN MATCHED THEN UPDATE ... WHEN NOT MATCHED THEN INSERT` hace que ejecutar la carga dos veces con los mismos datos no cambie el resultado. Esto es importante porque Snowpipe puede reintentar la entrega de un mismo archivo.

**`STREAM` + `TASK` para automatizar RAW → SILVER, en vez de ejecutar el `MERGE` a mano.** Es el mismo principio que llevó a Snowpipe en RAW, pero para el salto "tabla → tabla" dentro de Snowflake, que un `PIPE` no puede hacer (un pipe solo sabe ejecutar un `COPY INTO`). El `STREAM` lleva la cuenta de qué filas de RAW son nuevas desde la última vez que se consumió, y la `TASK` se despierta con un `SCHEDULE` (cada sábado a las 8:30, 30 minutos después de la carga real de ADF, que corre a las 8:00) pero solo hace trabajo real cuando `SYSTEM$STREAM_HAS_DATA` dice que hay algo pendiente — así una ejecución sin novedades no consume cómputo de verdad. `APPEND_ONLY = TRUE` en el stream porque RAW nunca actualiza ni borra filas, solo inserta: no hace falta que el stream trackee esos otros dos tipos de cambio.

**Columnas de auditoría propias (`_RAW_LOADED_AT`, `_SILVER_LOADED_AT`), en vez de solo heredar las de RAW.** `_SOURCE_FILE` y `_RAW_LOADED_AT` (renombrada desde `_LOADED_AT` de RAW, para no confundirla) dicen de dónde vino el dato originalmente; `_SILVER_LOADED_AT` dice cuándo se actualizó *esta* fila en SILVER, que puede ser mucho más tarde si la task tardó en recogerla. Son dos preguntas distintas ("¿de qué carga viene?" vs "¿cuándo se reflejó aquí?") y conviene poder responderlas por separado.

## Estructura

- `00_setup.sql` — objeto compartido: solo el schema `FOOTBALL.SILVER`. A diferencia de RAW, SILVER no necesita integrations ni stages, porque no habla con Azure — todo el movimiento de datos es interno a Snowflake (RAW → SILVER).
- `01_<tabla>.sql`, `02_<tabla>.sql`... — un archivo por tabla, cada uno con: `CREATE TABLE` tipada → `CREATE STREAM` sobre la tabla RAW correspondiente → `CREATE TASK` con el `MERGE` de tipado + limpieza + deduplicación → `ALTER TASK ... RESUME`. Todas las tasks usan el warehouse `COMPUTE_WH`.
- `alter_schedule.sql` — utilidad para cambiar el `SCHEDULE` de las 9 tasks sin reejecutar los archivos de arriba (no hace falta: `CREATE TABLE`/`CREATE STREAM` usan `IF NOT EXISTS`, así que reejecutarlos no perdería nada, pero tampoco cambiaría el `SCHEDULE` de una task ya creada -- de ahí que el cambio se haga con `ALTER TASK` en su propio archivo).

## Tablas

Las 9 tienen ya su archivo (`01_...` a `09_...`), pero con dos niveles de confianza distintos:

- **`competitions`** — verificado contra datos reales (`DESC TABLE` + una muestra de filas de tu `RAW.COMPETITIONS`). Es el patrón validado.
- **`clubs`, `players`, `games`, `club_games`, `appearances`, `player_valuations`, `transfers`, `countries`** — generados infiriendo columnas y tipos a partir del esquema público conocido del dataset (Kaggle, Transfermarkt player-scores), **sin haber visto todavía datos reales de tu cuenta**. Cada archivo lleva un aviso al principio recordando qué revisar antes de darlo por bueno (sobre todo formatos de fecha y un par de columnas monetarias en texto libre que se han dejado sin tipar a propósito). Antes de ejecutar cada uno, comprueba con un `SELECT * FROM RAW.<TABLA> LIMIT 5` que los nombres de columna coinciden.

Todas las claves de negocio usadas para el `MERGE`/deduplicación:

| Tabla | Clave de negocio |
|---|---|
| competitions | `COMPETITION_ID` |
| clubs | `CLUB_ID` |
| players | `PLAYER_ID` |
| games | `GAME_ID` |
| club_games | `GAME_ID` + `CLUB_ID` (cada partido genera una fila por club) |
| appearances | `APPEARANCE_ID` (ya viene como clave única en el CSV) |
| player_valuations | `PLAYER_ID` + fecha de valoración |
| transfers | `PLAYER_ID` + fecha + club destino (no hay id propio en el dataset; a confirmar si es realmente única en tus datos) |
| countries | `COUNTRY_ID` |
