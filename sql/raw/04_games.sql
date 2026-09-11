-- =====================================================================
-- RAW · 04_games.sql
-- Tabla: games.csv
-- =====================================================================

use DATABASE FOOTBALL;
use SCHEMA RAW;

-- 1. (Opcional) comprobar visualmente las columnas reales antes de crear
-- la tabla. Ya no es imprescindible para el paso 3 (MATCH_BY_COLUMN_NAME
-- empareja por nombre en tiempo de carga, no hace falta saber cuántas
-- columnas tiene el CSV de antemano), pero es una buena forma de
-- detectar nombres raros o columnas inesperadas antes de automatizar.

/*
SELECT *
FROM TABLE(
  INFER_SCHEMA(
    LOCATION => '@stage_raw_blob/landing/2026/09/04/player-scores/',
    FILE_FORMAT => 'FOOTBALL.RAW.FF_CSV_INFER',
    FILES => 'games.csv'
  )
);
*/

-- 2. Tabla RAW generada desde el propio INFER_SCHEMA (todo STRING)
CREATE OR REPLACE TABLE FOOTBALL.RAW.GAMES
  USING TEMPLATE (
    SELECT ARRAY_AGG(
             OBJECT_CONSTRUCT(
               'COLUMN_NAME', UPPER(COLUMN_NAME),
               'TYPE', 'TEXT',
               'NULLABLE', TRUE
             )
           ) WITHIN GROUP (ORDER BY ORDER_ID)
    FROM TABLE(
      INFER_SCHEMA(
        LOCATION => '@stage_raw_blob/landing/2026/09/04/player-scores/',
        FILE_FORMAT => 'FOOTBALL.RAW.FF_CSV_INFER',
        FILES => 'games.csv'
      )
    )
  );

-- Columnas de metadatos. Se rellenan solas en el COPY INTO del paso 3
-- vía INCLUDE_METADATA, no hace falta tocarlas a mano nunca.
ALTER TABLE FOOTBALL.RAW.GAMES
  ADD COLUMN _SOURCE_FILE STRING,
             _LOADED_AT   TIMESTAMP_NTZ;

-- 3. Pipe: ingesta automática vía Snowpipe + Event Grid.
-- MATCH_BY_COLUMN_NAME empareja cada columna del CSV con la columna del
-- mismo nombre en la tabla (usa la cabecera real del archivo, gracias a
-- PARSE_HEADER = TRUE en FF_CSV_INFER) — no hace falta saber cuántas
-- columnas tiene el CSV ni en qué orden vienen. INCLUDE_METADATA rellena
-- _SOURCE_FILE y _LOADED_AT automáticamente. ERROR_ON_COLUMN_COUNT_MISMATCH
-- = FALSE es obligatorio en este modo porque la tabla tiene más columnas
-- (las 2 de metadatos) que el propio CSV.
CREATE OR REPLACE PIPE FOOTBALL.RAW.PIPE_GAMES
  AUTO_INGEST = TRUE
  INTEGRATION = 'NI_AZURE_BLOB_EVENTS'
AS
COPY INTO FOOTBALL.RAW.GAMES
FROM @stage_raw_blob
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
PATTERN = '.*games\\.csv'
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
);

-- 4. Backfill del histórico ya subido antes de crear el pipe
ALTER PIPE FOOTBALL.RAW.PIPE_GAMES REFRESH;

-- Validación:
-- SELECT * FROM FOOTBALL.RAW.GAMES limit 10;
-- SELECT SYSTEM$PIPE_STATUS('FOOTBALL.RAW.PIPE_GAMES');
