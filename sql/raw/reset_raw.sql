-- =====================================================================
-- RAW · reset_raw.sql
-- UTILIDAD: vacía las 9 tablas RAW para poder validar una carga nueva
-- desde cero, y fuerza la recarga de los archivos de una fecha
-- concreta aunque Snowflake ya los tenga marcados como "cargados". No
-- borra tablas, pipes, streams, tasks ni integrations -- solo el
-- contenido de las tablas.
--
-- AVISO IMPORTANTE sobre qué limpia y qué no limpia el TRUNCATE:
--
-- TRUNCATE vacía la tabla, pero NO borra el historial interno que
-- Snowflake mantiene de "qué archivos ya se cargaron" (lo usan tanto
-- COPY INTO como los pipes, durante 64 días, precisamente para no
-- cargar dos veces el mismo archivo por accidente). Esto tiene una
-- consecuencia práctica importante:
--
--   - Si vas a probar con archivos NUEVOS (la próxima carga real de
--     ADF, en una carpeta de fecha distinta), con el TRUNCATE basta:
--     los pipes cargarán esos archivos nuevos con total normalidad en
--     cuanto lleguen, exactamente igual que siempre. No hace falta la
--     sección 2 de este archivo.
--
--   - Si en cambio quieres volver a cargar los MISMOS archivos que ya
--     existen en Blob (por ejemplo, repetir a propósito la carga de
--     una fecha concreta), el TRUNCATE por sí solo no es suficiente:
--     los pipes ya tienen registrado que esos archivos "se cargaron",
--     así que ni un ALTER PIPE ... REFRESH los volverá a encolar. Para
--     eso está la sección 2: un COPY INTO manual con FORCE = TRUE por
--     tabla, que ignora ese historial y recarga el archivo sí o sí.
--
-- IMPORTANTE: la sección 2 apunta a landing/2026/09/07/. Cambia esa
-- fecha por la carpeta que quieras recargar antes de ejecutar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Vaciar las 9 tablas RAW
-- ---------------------------------------------------------------------
TRUNCATE TABLE FOOTBALL.RAW.COMPETITIONS;
TRUNCATE TABLE FOOTBALL.RAW.CLUBS;
TRUNCATE TABLE FOOTBALL.RAW.PLAYERS;
TRUNCATE TABLE FOOTBALL.RAW.GAMES;
TRUNCATE TABLE FOOTBALL.RAW.CLUB_GAMES;
TRUNCATE TABLE FOOTBALL.RAW.APPEARANCES;
TRUNCATE TABLE FOOTBALL.RAW.PLAYER_VALUATIONS;
TRUNCATE TABLE FOOTBALL.RAW.TRANSFERS;
TRUNCATE TABLE FOOTBALL.RAW.COUNTRIES;

-- ---------------------------------------------------------------------
-- 2. Forzar la recarga de los 9 archivos de landing/2026/09/07/,
-- ignorando el historial de "ya cargado" (FORCE = TRUE). Necesario
-- porque las tablas están vacías tras el TRUNCATE, pero Snowflake sigue
-- recordando que estos archivos concretos ya se procesaron antes.
-- ---------------------------------------------------------------------
COPY INTO FOOTBALL.RAW.COMPETITIONS
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/competitions.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;

COPY INTO FOOTBALL.RAW.CLUBS
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/clubs.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;

COPY INTO FOOTBALL.RAW.PLAYERS
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/players.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;

COPY INTO FOOTBALL.RAW.GAMES
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/games.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;

COPY INTO FOOTBALL.RAW.CLUB_GAMES
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/club_games.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;

COPY INTO FOOTBALL.RAW.APPEARANCES
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/appearances.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;

COPY INTO FOOTBALL.RAW.PLAYER_VALUATIONS
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/player_valuations.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;

COPY INTO FOOTBALL.RAW.TRANSFERS
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/transfers.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;

COPY INTO FOOTBALL.RAW.COUNTRIES
FROM @stage_raw_blob
FILES = ('landing/2026/09/07/player-scores/countries.csv')
FILE_FORMAT = (FORMAT_NAME = 'FOOTBALL.RAW.FF_CSV_INFER', ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
  _SOURCE_FILE = METADATA$FILENAME,
  _LOADED_AT   = METADATA$START_SCAN_TIME
)
FORCE = TRUE;
