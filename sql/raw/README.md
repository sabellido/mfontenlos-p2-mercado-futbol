# RAW

*(Parte de la [arquitectura general](../../README.md) · Siguientes etapas: [SILVER](../silver/README.md) · [GOLD](../gold/README.md))*

Capa de aterrizaje de los datos tal cual llegan del CSV, sin limpiar ni tipar. Es una copia fiel del archivo fuente dentro de Snowflake.

## Decisiones de diseño

**Todas las columnas son STRING.** Aunque `INFER_SCHEMA` sugiere tipos (por ejemplo `NUMBER` para `country_id`), los ignoramos a propósito. El motivo es que RAW tiene que aceptar el archivo *siempre*, incluso si viene con un valor mal formado, un campo vacío o un texto donde se esperaba un número. Si tipáramos aquí, una sola fila rara podría tumbar toda la carga. Ese control de calidad y conversión de tipos se hace de forma segura en SILVER (con `TRY_CAST`, que convierte a `NULL` en vez de fallar).

**Columnas de metadatos (`_SOURCE_FILE`, `_LOADED_AT`).** No vienen del CSV, las añadimos nosotros en la carga. Dan trazabilidad: de qué archivo concreto y en qué momento llegó cada fila. Esto es necesario en cuanto la ingesta es automática (Snowpipe) y pueden llegar varias cargas de golpe sin que nadie lo esté mirando en directo.

**Storage Integration en vez de SAS token.** El acceso de Snowflake al contenedor de Azure Blob se hace vía Azure AD (Service Principal gestionado por Azure, con el rol RBAC "Storage Blob Data Reader"), no con un SAS token embebido en el `CREATE STAGE`. Un SAS token caduca y hay que rotarlo a mano; la integration es la vía recomendada por Snowflake para producción porque el control de acceso vive en Azure RBAC, de forma centralizada.

## Ingesta automática (Snowpipe + Event Grid)

Una vez que un archivo aterriza en Blob, ¿cómo llega a Snowflake sin que nadie ejecute un `COPY INTO` a mano? La cadena es la siguiente:

1. El pipeline de ADF descarga, descomprime y escribe los CSV en `landing/<fecha>/player-scores/` dentro del contenedor Blob.
2. En cuanto Azure Blob Storage termina de escribir un blob nuevo, emite un evento `Blob Created` — esto es una propiedad del propio servicio de almacenamiento, no algo que programemos nosotros.
3. Event Grid tiene una suscripción a ese tipo de evento (filtrada a `landing/*.csv`) y deposita el evento como un mensaje en una Storage Queue de Azure.
4. Snowflake, a través de una Notification Integration (`NOTIFICATION_PROVIDER = AZURE_STORAGE_QUEUE`), está permanentemente escuchando esa cola — esto es lo que activa `AUTO_INGEST = TRUE` en un pipe.
5. Cuando llega un mensaje cuya ruta de archivo coincide con el `PATTERN` de un pipe (por ejemplo, termina en `competitions.csv`), Snowflake dispara automáticamente el `COPY INTO` de ese pipe, solo para ese archivo.

El disparador es la llegada del archivo, no el horario del trigger de ADF ni ninguna consulta periódica desde Snowflake — por eso es "basado en eventos" y no en sondeo. El `PATTERN` del pipe apunta a la raíz del stage y filtra por nombre de archivo, no por carpeta de fecha: así, cualquier `competitions.csv` nuevo que llegue, en cualquier fecha, dispara su propia carga sin que haya que calcular ni mantener "cuál es la última carpeta".

Tres matices a tener en cuenta:

- **No es instantáneo.** Snowflake documenta un retraso típico de hasta 1-2 minutos entre que llega el evento y se ejecuta el `COPY INTO`. Es "casi en tiempo real", no tiempo real.
- **Es por archivo, no por tabla.** Cada pipe reacciona solo a los archivos que coinciden con su `PATTERN`. Cada tabla RAW necesita su propio pipe (`PIPE_COMPETITIONS`, `PIPE_CLUBS`...); si un archivo no tiene pipe, sigue necesitando `COPY INTO` manual.
- **No hace backfill de lo que ya estaba antes de crear el pipe**, salvo que se lo pidamos explícitamente con `ALTER PIPE ... REFRESH` (ver más abajo).

`MATCH_BY_COLUMN_NAME` + `INCLUDE_METADATA` Snowflake lee la cabecera real del CSV (gracias a `PARSE_HEADER = TRUE`) y empareja cada columna del archivo con la columna del mismo nombre en la tabla, sea cual sea el número de columnas o el orden en que vengan. `INCLUDE_METADATA = (_SOURCE_FILE = METADATA$FILENAME, _LOADED_AT = METADATA$START_SCAN_TIME)` hace lo mismo para las dos columnas de metadatos, que no vienen en el CSV. El resultado: el mismo `CREATE PIPE` funciona para cualquier tabla sin tocar nada más que el nombre de la tabla y del archivo — no hay ningún valor que haya que calcular o contar a mano.

Un detalle técnico obligatorio en este modo: `ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE` en el `FILE_FORMAT` del `COPY INTO`. Sin él, Snowflake se queja de que la tabla tiene más columnas que el archivo (las 2 de metadatos) — cosa que aquí es intencional, no un error.

**`ALTER PIPE ... REFRESH` en vez de un `COPY INTO` manual de validación.** Un pipe recién creado solo reacciona a eventos *nuevos*: el archivo que ya estaba en Blob antes de crear el pipe no se carga solo. En vez de mantener un `COPY INTO` manual aparte (que sería una segunda vía de carga, redundante con el pipe y fácil de desincronizar), usamos `REFRESH`, el mecanismo propio de Snowpipe para decirle "revisa el stage y encola también lo que ya estaba ahí". Así hay una única vía de carga (el pipe), tanto para el histórico como para lo nuevo.

## Estructura

- `00_setup.sql` — objetos compartidos por toda la capa: base de datos, schema, storage integration, stage, el file format y la notification integration. Nada específico de una tabla concreta va aquí.
- `01_<tabla>.sql`, `02_<tabla>.sql`... — un archivo por tabla origen, cada uno de principio a fin: descubrir columnas (`INFER_SCHEMA`, opcional/informativo) → crear tabla (`CREATE TABLE ... USING TEMPLATE`) → añadir metadatos (`ALTER TABLE`) → crear el pipe (`MATCH_BY_COLUMN_NAME` + `INCLUDE_METADATA`) → `REFRESH` para el histórico ya existente. No hay ningún valor que rellenar a mano en ninguno de los archivos: son ejecutables tal cual, solo cambiando qué archivo ejecutas.

## Tablas

`competitions`, `clubs`, `players`, `games`, `club_games`, `appearances`, `player_valuations`, `transfers`, `countries` — los 9 tienen ya su archivo completo en `01_...` a `09_...`, listos para ejecutar sin ediciones.
