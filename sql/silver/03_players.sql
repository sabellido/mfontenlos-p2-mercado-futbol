-- =====================================================================
-- SILVER · 03_players.sql
-- FOOTBALL.RAW.PLAYERS -> FOOTBALL.SILVER.PLAYERS
--
-- AVISO (inferido, no verificado con datos reales): mismo caso que
-- 02_clubs.sql. Antes de ejecutar, comprueba con
--   SELECT * FROM FOOTBALL.RAW.PLAYERS LIMIT 5;
-- sobre todo el formato exacto de DATE_OF_BIRTH y
-- CONTRACT_EXPIRATION_DATE -- si vienen con hora (p.ej.
-- "1998-04-05 00:00:00"), TRY_TO_DATE con formato automático debería
-- seguir funcionando, pero conviene confirmarlo.
-- =====================================================================

CREATE TABLE IF NOT EXISTS FOOTBALL.SILVER.PLAYERS (
  PLAYER_ID                              NUMBER        NOT NULL,
  FIRST_NAME                             STRING,
  LAST_NAME                              STRING,
  NAME                                   STRING,
  LAST_SEASON                            NUMBER,
  CURRENT_CLUB_ID                        NUMBER,
  PLAYER_CODE                            STRING,
  COUNTRY_OF_BIRTH                       STRING,
  CITY_OF_BIRTH                          STRING,
  COUNTRY_OF_CITIZENSHIP                 STRING,
  DATE_OF_BIRTH                          DATE,
  SUB_POSITION                           STRING,
  POSITION                               STRING,
  FOOT                                   STRING,
  HEIGHT_IN_CM                           NUMBER,
  CONTRACT_EXPIRATION_DATE               DATE,
  AGENT_NAME                             STRING,
  IMAGE_URL                              STRING,
  URL                                    STRING,
  CURRENT_CLUB_DOMESTIC_COMPETITION_ID   STRING,
  CURRENT_CLUB_NAME                      STRING,
  MARKET_VALUE_IN_EUR                    NUMBER,
  HIGHEST_MARKET_VALUE_IN_EUR            NUMBER,
  _SOURCE_FILE                           STRING,
  _RAW_LOADED_AT                         TIMESTAMP_NTZ,
  _SILVER_LOADED_AT                      TIMESTAMP_NTZ,
  PRIMARY KEY (PLAYER_ID)
);

CREATE STREAM IF NOT EXISTS FOOTBALL.SILVER.STREAM_RAW_PLAYERS
  ON TABLE FOOTBALL.RAW.PLAYERS
  APPEND_ONLY = TRUE;

CREATE OR REPLACE TASK FOOTBALL.SILVER.TASK_LOAD_PLAYERS
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid'
WHEN
  SYSTEM$STREAM_HAS_DATA('FOOTBALL.SILVER.STREAM_RAW_PLAYERS')
AS
MERGE INTO FOOTBALL.SILVER.PLAYERS AS tgt
USING (
  SELECT
    TRY_TO_NUMBER(PLAYER_ID)                             AS PLAYER_ID,
    NULLIF(TRIM(FIRST_NAME), '')                         AS FIRST_NAME,
    NULLIF(TRIM(LAST_NAME), '')                          AS LAST_NAME,
    NULLIF(TRIM(NAME), '')                               AS NAME,
    TRY_TO_NUMBER(LAST_SEASON)                           AS LAST_SEASON,
    TRY_TO_NUMBER(CURRENT_CLUB_ID)                       AS CURRENT_CLUB_ID,
    NULLIF(TRIM(PLAYER_CODE), '')                        AS PLAYER_CODE,
    NULLIF(TRIM(COUNTRY_OF_BIRTH), '')                   AS COUNTRY_OF_BIRTH,
    NULLIF(TRIM(CITY_OF_BIRTH), '')                      AS CITY_OF_BIRTH,
    NULLIF(TRIM(COUNTRY_OF_CITIZENSHIP), '')             AS COUNTRY_OF_CITIZENSHIP,
    TRY_TO_DATE(DATE_OF_BIRTH)                           AS DATE_OF_BIRTH,
    NULLIF(TRIM(SUB_POSITION), '')                       AS SUB_POSITION,
    NULLIF(TRIM(POSITION), '')                           AS POSITION,
    NULLIF(TRIM(FOOT), '')                                AS FOOT,
    TRY_TO_NUMBER(HEIGHT_IN_CM)                          AS HEIGHT_IN_CM,
    TRY_TO_DATE(CONTRACT_EXPIRATION_DATE)                AS CONTRACT_EXPIRATION_DATE,
    NULLIF(TRIM(AGENT_NAME), '')                         AS AGENT_NAME,
    NULLIF(TRIM(IMAGE_URL), '')                          AS IMAGE_URL,
    NULLIF(TRIM(URL), '')                                AS URL,
    NULLIF(TRIM(CURRENT_CLUB_DOMESTIC_COMPETITION_ID), '') AS CURRENT_CLUB_DOMESTIC_COMPETITION_ID,
    NULLIF(TRIM(CURRENT_CLUB_NAME), '')                  AS CURRENT_CLUB_NAME,
    TRY_TO_NUMBER(MARKET_VALUE_IN_EUR)                   AS MARKET_VALUE_IN_EUR,
    TRY_TO_NUMBER(HIGHEST_MARKET_VALUE_IN_EUR)           AS HIGHEST_MARKET_VALUE_IN_EUR,
    _SOURCE_FILE                                         AS _SOURCE_FILE,
    _LOADED_AT                                           AS _RAW_LOADED_AT
  FROM FOOTBALL.SILVER.STREAM_RAW_PLAYERS
  WHERE PLAYER_ID IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY PLAYER_ID
    ORDER BY _LOADED_AT DESC
  ) = 1
) AS src
ON tgt.PLAYER_ID = src.PLAYER_ID
WHEN MATCHED THEN UPDATE SET
  tgt.FIRST_NAME                           = src.FIRST_NAME,
  tgt.LAST_NAME                            = src.LAST_NAME,
  tgt.NAME                                 = src.NAME,
  tgt.LAST_SEASON                          = src.LAST_SEASON,
  tgt.CURRENT_CLUB_ID                      = src.CURRENT_CLUB_ID,
  tgt.PLAYER_CODE                          = src.PLAYER_CODE,
  tgt.COUNTRY_OF_BIRTH                     = src.COUNTRY_OF_BIRTH,
  tgt.CITY_OF_BIRTH                        = src.CITY_OF_BIRTH,
  tgt.COUNTRY_OF_CITIZENSHIP               = src.COUNTRY_OF_CITIZENSHIP,
  tgt.DATE_OF_BIRTH                        = src.DATE_OF_BIRTH,
  tgt.SUB_POSITION                         = src.SUB_POSITION,
  tgt.POSITION                             = src.POSITION,
  tgt.FOOT                                 = src.FOOT,
  tgt.HEIGHT_IN_CM                         = src.HEIGHT_IN_CM,
  tgt.CONTRACT_EXPIRATION_DATE             = src.CONTRACT_EXPIRATION_DATE,
  tgt.AGENT_NAME                           = src.AGENT_NAME,
  tgt.IMAGE_URL                            = src.IMAGE_URL,
  tgt.URL                                  = src.URL,
  tgt.CURRENT_CLUB_DOMESTIC_COMPETITION_ID = src.CURRENT_CLUB_DOMESTIC_COMPETITION_ID,
  tgt.CURRENT_CLUB_NAME                    = src.CURRENT_CLUB_NAME,
  tgt.MARKET_VALUE_IN_EUR                  = src.MARKET_VALUE_IN_EUR,
  tgt.HIGHEST_MARKET_VALUE_IN_EUR          = src.HIGHEST_MARKET_VALUE_IN_EUR,
  tgt._SOURCE_FILE                         = src._SOURCE_FILE,
  tgt._RAW_LOADED_AT                       = src._RAW_LOADED_AT,
  tgt._SILVER_LOADED_AT                    = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
  PLAYER_ID, FIRST_NAME, LAST_NAME, NAME, LAST_SEASON, CURRENT_CLUB_ID,
  PLAYER_CODE, COUNTRY_OF_BIRTH, CITY_OF_BIRTH, COUNTRY_OF_CITIZENSHIP,
  DATE_OF_BIRTH, SUB_POSITION, POSITION, FOOT, HEIGHT_IN_CM,
  CONTRACT_EXPIRATION_DATE, AGENT_NAME, IMAGE_URL, URL,
  CURRENT_CLUB_DOMESTIC_COMPETITION_ID, CURRENT_CLUB_NAME,
  MARKET_VALUE_IN_EUR, HIGHEST_MARKET_VALUE_IN_EUR,
  _SOURCE_FILE, _RAW_LOADED_AT, _SILVER_LOADED_AT
) VALUES (
  src.PLAYER_ID, src.FIRST_NAME, src.LAST_NAME, src.NAME, src.LAST_SEASON,
  src.CURRENT_CLUB_ID, src.PLAYER_CODE, src.COUNTRY_OF_BIRTH,
  src.CITY_OF_BIRTH, src.COUNTRY_OF_CITIZENSHIP, src.DATE_OF_BIRTH,
  src.SUB_POSITION, src.POSITION, src.FOOT, src.HEIGHT_IN_CM,
  src.CONTRACT_EXPIRATION_DATE, src.AGENT_NAME, src.IMAGE_URL, src.URL,
  src.CURRENT_CLUB_DOMESTIC_COMPETITION_ID, src.CURRENT_CLUB_NAME,
  src.MARKET_VALUE_IN_EUR, src.HIGHEST_MARKET_VALUE_IN_EUR,
  src._SOURCE_FILE, src._RAW_LOADED_AT, CURRENT_TIMESTAMP()
);

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_PLAYERS RESUME;

-- Validación:
-- SELECT * FROM FOOTBALL.SILVER.PLAYERS;
-- EXECUTE TASK FOOTBALL.SILVER.TASK_LOAD_PLAYERS;
