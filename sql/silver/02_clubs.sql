-- =====================================================================
-- SILVER · 02_clubs.sql
-- FOOTBALL.RAW.CLUBS -> FOOTBALL.SILVER.CLUBS
--
-- AVISO: a diferencia de 01_competitions.sql (donde vi datos reales),
-- este archivo infiere columnas y tipos a partir del esquema público
-- conocido del dataset de Kaggle (Transfermarkt player-scores), sin
-- haber visto todavía filas reales de tu tabla RAW.CLUBS. Antes de
-- darlo por definitivo, ejecuta:
--   SELECT * FROM FOOTBALL.RAW.CLUBS LIMIT 5;
-- y compara nombres de columna y formato de valores contra lo de abajo.
-- Dos columnas monetarias con formato de texto libre (símbolo de
-- moneda + sufijo "m"/"k", p.ej. "+€19.30m") se dejan como STRING a
-- propósito: parsear eso a NUMBER de forma fiable necesitaría un REGEXP
-- aparte, y prefiero no arriesgar una conversión incorrecta sin ver
-- antes datos reales.
-- =====================================================================

CREATE TABLE IF NOT EXISTS FOOTBALL.SILVER.CLUBS (
  CLUB_ID                   NUMBER        NOT NULL,
  CLUB_CODE                 STRING,
  NAME                      STRING,
  DOMESTIC_COMPETITION_ID   STRING,
  TOTAL_MARKET_VALUE        NUMBER,
  SQUAD_SIZE                NUMBER,
  AVERAGE_AGE               NUMBER(10,2),
  FOREIGNERS_NUMBER         NUMBER,
  FOREIGNERS_PERCENTAGE     NUMBER(10,2),
  NATIONAL_TEAM_PLAYERS     NUMBER,
  STADIUM_NAME              STRING,
  STADIUM_SEATS             NUMBER,
  NET_TRANSFER_RECORD       STRING,       -- texto libre, ver aviso arriba
  COACH_NAME                STRING,
  LAST_SEASON               NUMBER,
  FILENAME                  STRING,
  URL                       STRING,
  _SOURCE_FILE              STRING,
  _RAW_LOADED_AT            TIMESTAMP_NTZ,
  _SILVER_LOADED_AT         TIMESTAMP_NTZ,
  PRIMARY KEY (CLUB_ID)
);

CREATE STREAM IF NOT EXISTS FOOTBALL.SILVER.STREAM_RAW_CLUBS
  ON TABLE FOOTBALL.RAW.CLUBS
  APPEND_ONLY = TRUE;

CREATE OR REPLACE TASK FOOTBALL.SILVER.TASK_LOAD_CLUBS
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid'
WHEN
  SYSTEM$STREAM_HAS_DATA('FOOTBALL.SILVER.STREAM_RAW_CLUBS')
AS
MERGE INTO FOOTBALL.SILVER.CLUBS AS tgt
USING (
  SELECT
    TRY_TO_NUMBER(CLUB_ID)                     AS CLUB_ID,
    NULLIF(TRIM(CLUB_CODE), '')                AS CLUB_CODE,
    NULLIF(TRIM(NAME), '')                     AS NAME,
    NULLIF(TRIM(DOMESTIC_COMPETITION_ID), '')  AS DOMESTIC_COMPETITION_ID,
    TRY_TO_NUMBER(TOTAL_MARKET_VALUE)          AS TOTAL_MARKET_VALUE,
    TRY_TO_NUMBER(SQUAD_SIZE)                  AS SQUAD_SIZE,
    TRY_TO_NUMBER(AVERAGE_AGE)                 AS AVERAGE_AGE,
    TRY_TO_NUMBER(FOREIGNERS_NUMBER)           AS FOREIGNERS_NUMBER,
    TRY_TO_NUMBER(FOREIGNERS_PERCENTAGE)       AS FOREIGNERS_PERCENTAGE,
    TRY_TO_NUMBER(NATIONAL_TEAM_PLAYERS)       AS NATIONAL_TEAM_PLAYERS,
    NULLIF(TRIM(STADIUM_NAME), '')             AS STADIUM_NAME,
    TRY_TO_NUMBER(STADIUM_SEATS)               AS STADIUM_SEATS,
    NULLIF(TRIM(NET_TRANSFER_RECORD), '')      AS NET_TRANSFER_RECORD,
    NULLIF(TRIM(COACH_NAME), '')               AS COACH_NAME,
    TRY_TO_NUMBER(LAST_SEASON)                 AS LAST_SEASON,
    NULLIF(TRIM(FILENAME), '')                 AS FILENAME,
    NULLIF(TRIM(URL), '')                      AS URL,
    _SOURCE_FILE                               AS _SOURCE_FILE,
    _LOADED_AT                                 AS _RAW_LOADED_AT
  FROM FOOTBALL.SILVER.STREAM_RAW_CLUBS
  WHERE CLUB_ID IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CLUB_ID
    ORDER BY _LOADED_AT DESC
  ) = 1
) AS src
ON tgt.CLUB_ID = src.CLUB_ID
WHEN MATCHED THEN UPDATE SET
  tgt.CLUB_CODE               = src.CLUB_CODE,
  tgt.NAME                    = src.NAME,
  tgt.DOMESTIC_COMPETITION_ID = src.DOMESTIC_COMPETITION_ID,
  tgt.TOTAL_MARKET_VALUE      = src.TOTAL_MARKET_VALUE,
  tgt.SQUAD_SIZE               = src.SQUAD_SIZE,
  tgt.AVERAGE_AGE              = src.AVERAGE_AGE,
  tgt.FOREIGNERS_NUMBER        = src.FOREIGNERS_NUMBER,
  tgt.FOREIGNERS_PERCENTAGE    = src.FOREIGNERS_PERCENTAGE,
  tgt.NATIONAL_TEAM_PLAYERS    = src.NATIONAL_TEAM_PLAYERS,
  tgt.STADIUM_NAME             = src.STADIUM_NAME,
  tgt.STADIUM_SEATS            = src.STADIUM_SEATS,
  tgt.NET_TRANSFER_RECORD      = src.NET_TRANSFER_RECORD,
  tgt.COACH_NAME               = src.COACH_NAME,
  tgt.LAST_SEASON              = src.LAST_SEASON,
  tgt.FILENAME                 = src.FILENAME,
  tgt.URL                      = src.URL,
  tgt._SOURCE_FILE             = src._SOURCE_FILE,
  tgt._RAW_LOADED_AT           = src._RAW_LOADED_AT,
  tgt._SILVER_LOADED_AT        = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
  CLUB_ID, CLUB_CODE, NAME, DOMESTIC_COMPETITION_ID, TOTAL_MARKET_VALUE,
  SQUAD_SIZE, AVERAGE_AGE, FOREIGNERS_NUMBER, FOREIGNERS_PERCENTAGE,
  NATIONAL_TEAM_PLAYERS, STADIUM_NAME, STADIUM_SEATS, NET_TRANSFER_RECORD,
  COACH_NAME, LAST_SEASON, FILENAME, URL,
  _SOURCE_FILE, _RAW_LOADED_AT, _SILVER_LOADED_AT
) VALUES (
  src.CLUB_ID, src.CLUB_CODE, src.NAME, src.DOMESTIC_COMPETITION_ID,
  src.TOTAL_MARKET_VALUE, src.SQUAD_SIZE, src.AVERAGE_AGE,
  src.FOREIGNERS_NUMBER, src.FOREIGNERS_PERCENTAGE,
  src.NATIONAL_TEAM_PLAYERS, src.STADIUM_NAME, src.STADIUM_SEATS,
  src.NET_TRANSFER_RECORD, src.COACH_NAME, src.LAST_SEASON, src.FILENAME,
  src.URL, src._SOURCE_FILE, src._RAW_LOADED_AT, CURRENT_TIMESTAMP()
);

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_CLUBS RESUME;

-- Validación:
-- SELECT * FROM FOOTBALL.SILVER.CLUBS;
-- EXECUTE TASK FOOTBALL.SILVER.TASK_LOAD_CLUBS;
