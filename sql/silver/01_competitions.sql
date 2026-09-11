-- =====================================================================
-- SILVER · 01_competitions.sql
-- FOOTBALL.RAW.COMPETITIONS -> FOOTBALL.SILVER.COMPETITIONS
-- =====================================================================

-- 1. Tabla SILVER: mismos datos que RAW, pero con tipos de dato reales
-- (no todo STRING) y sin las columnas de auditoría propias de la carga
-- de archivos (se sustituyen por sus equivalentes de trazabilidad).
-- COMPETITION_ID es un código alfanumérico (p.ej. "A1", "ARG1", "AFAC"),
-- no un número a pesar del nombre -- se queda como STRING.
CREATE TABLE IF NOT EXISTS FOOTBALL.SILVER.COMPETITIONS (
  COMPETITION_ID          STRING        NOT NULL,
  COMPETITION_CODE        STRING,
  NAME                    STRING,
  SUB_TYPE                STRING,
  TYPE                    STRING,
  COUNTRY_ID              NUMBER,
  COUNTRY_NAME            STRING,
  DOMESTIC_LEAGUE_CODE    STRING,
  CONFEDERATION           STRING,
  TOTAL_CLUBS             NUMBER,
  URL                     STRING,
  _SOURCE_FILE            STRING,
  _RAW_LOADED_AT          TIMESTAMP_NTZ,
  _SILVER_LOADED_AT       TIMESTAMP_NTZ,
  PRIMARY KEY (COMPETITION_ID)
);

-- 2. Stream sobre RAW: lleva la cuenta de qué filas son nuevas desde la
-- última vez que la task de abajo lo consumió. APPEND_ONLY = TRUE porque
-- RAW solo recibe INSERTs (los pipes nunca actualizan ni borran nada
-- ahí), así que no hace falta que el stream trackee updates/deletes --
-- es más barato de mantener.
CREATE STREAM IF NOT EXISTS FOOTBALL.SILVER.STREAM_RAW_COMPETITIONS
  ON TABLE FOOTBALL.RAW.COMPETITIONS
  APPEND_ONLY = TRUE;

-- 3. Task: tipa, limpia, deduplica y hace upsert en SILVER, pero SOLO
-- cuando el stream tiene datos pendientes (si no, la ejecución programada
-- no hace nada y no consume crédito de cómputo real).
--   - TRY_TO_NUMBER en vez de TO_NUMBER: un valor mal formado se
--     convierte en NULL en vez de tumbar toda la carga.
--   - NULLIF(TRIM(...), '') en las columnas de texto: quita espacios y
--     convierte cadenas vacías en NULL real -- defensivo, por si algún
--     valor "vacío" llega como espacios en vez de como cadena vacía.
--   - QUALIFY ROW_NUMBER() ... = 1: si el mismo COMPETITION_ID aparece
--     más de una vez en el lote nuevo del stream (por ejemplo, porque la
--     task no se ha ejecutado en varios días y llegaron dos cargas del
--     mismo archivo), nos quedamos solo con la versión más reciente
--     según _LOADED_AT.
--   - WHERE COMPETITION_ID IS NOT NULL: descarta filas sin clave de
--     negocio antes de intentar el MERGE (una fila así rompería el ON).
CREATE OR REPLACE TASK FOOTBALL.SILVER.TASK_LOAD_COMPETITIONS
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid'
WHEN
  SYSTEM$STREAM_HAS_DATA('FOOTBALL.SILVER.STREAM_RAW_COMPETITIONS')
AS
MERGE INTO FOOTBALL.SILVER.COMPETITIONS AS tgt
USING (
  SELECT
    NULLIF(TRIM(COMPETITION_ID), '')       AS COMPETITION_ID,
    NULLIF(TRIM(COMPETITION_CODE), '')     AS COMPETITION_CODE,
    NULLIF(TRIM(NAME), '')                 AS NAME,
    NULLIF(TRIM(SUB_TYPE), '')             AS SUB_TYPE,
    NULLIF(TRIM(TYPE), '')                 AS TYPE,
    TRY_TO_NUMBER(COUNTRY_ID)              AS COUNTRY_ID,
    NULLIF(TRIM(COUNTRY_NAME), '')         AS COUNTRY_NAME,
    NULLIF(TRIM(DOMESTIC_LEAGUE_CODE), '') AS DOMESTIC_LEAGUE_CODE,
    NULLIF(TRIM(CONFEDERATION), '')        AS CONFEDERATION,
    TRY_TO_NUMBER(TOTAL_CLUBS)             AS TOTAL_CLUBS,
    NULLIF(TRIM(URL), '')                  AS URL,
    _SOURCE_FILE                           AS _SOURCE_FILE,
    _LOADED_AT                             AS _RAW_LOADED_AT
  FROM FOOTBALL.SILVER.STREAM_RAW_COMPETITIONS
  WHERE COMPETITION_ID IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY COMPETITION_ID
    ORDER BY _LOADED_AT DESC
  ) = 1
) AS src
ON tgt.COMPETITION_ID = src.COMPETITION_ID
WHEN MATCHED THEN UPDATE SET
  tgt.COMPETITION_CODE     = src.COMPETITION_CODE,
  tgt.NAME                 = src.NAME,
  tgt.SUB_TYPE             = src.SUB_TYPE,
  tgt.TYPE                 = src.TYPE,
  tgt.COUNTRY_ID           = src.COUNTRY_ID,
  tgt.COUNTRY_NAME         = src.COUNTRY_NAME,
  tgt.DOMESTIC_LEAGUE_CODE = src.DOMESTIC_LEAGUE_CODE,
  tgt.CONFEDERATION        = src.CONFEDERATION,
  tgt.TOTAL_CLUBS          = src.TOTAL_CLUBS,
  tgt.URL                  = src.URL,
  tgt._SOURCE_FILE         = src._SOURCE_FILE,
  tgt._RAW_LOADED_AT       = src._RAW_LOADED_AT,
  tgt._SILVER_LOADED_AT    = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
  COMPETITION_ID, COMPETITION_CODE, NAME, SUB_TYPE, TYPE, COUNTRY_ID,
  COUNTRY_NAME, DOMESTIC_LEAGUE_CODE, CONFEDERATION, TOTAL_CLUBS, URL,
  _SOURCE_FILE, _RAW_LOADED_AT, _SILVER_LOADED_AT
) VALUES (
  src.COMPETITION_ID, src.COMPETITION_CODE, src.NAME, src.SUB_TYPE,
  src.TYPE, src.COUNTRY_ID, src.COUNTRY_NAME, src.DOMESTIC_LEAGUE_CODE,
  src.CONFEDERATION, src.TOTAL_CLUBS, src.URL, src._SOURCE_FILE,
  src._RAW_LOADED_AT, CURRENT_TIMESTAMP()
);

-- 4. Las tasks se crean SUSPENDIDAS por defecto; hay que activarlas
-- explícitamente para que el SCHEDULE empiece a disparar.
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_COMPETITIONS RESUME;

-- Validación:
-- SELECT * FROM FOOTBALL.SILVER.COMPETITIONS;
-- SELECT SYSTEM$STREAM_HAS_DATA('FOOTBALL.SILVER.STREAM_RAW_COMPETITIONS');
-- EXECUTE TASK FOOTBALL.SILVER.TASK_LOAD_COMPETITIONS; -- fuerza una ejecución ya, sin esperar el schedule
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TASK_LOAD_COMPETITIONS'));
