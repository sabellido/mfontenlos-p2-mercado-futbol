-- =====================================================================
-- GOLD · 01_dim_season.sql
-- FOOTBALL.SILVER.GAMES (+ FOOTBALL.SILVER.PLAYER_VALUATIONS en la siembra)
--   -> FOOTBALL.GOLD.DIM_SEASON
--
-- IMPORTANTE: sustituye <TU_WAREHOUSE> por el nombre real de tu
-- warehouse antes de ejecutar el CREATE TASK.
--
-- Sustituye a la dim_date del enunciado: por decisión explícita, GOLD
-- no incluye una dimensión de fecha diaria -- con grano temporada es
-- suficiente para todo el filtrado y las series temporales del informe.
--
-- SIEMBRA vs. AUTOMATIZACIÓN INCREMENTAL (fuentes distintas a propósito):
-- la siembra inicial calcula las temporadas a partir de DOS fuentes
-- (GAMES.SEASON y una temporada derivada de la fecha de
-- PLAYER_VALUATIONS), para no dejarse ninguna temporada fuera en la
-- carga inicial. Pero la TASK incremental solo vigila GAMES: en la
-- práctica, una temporada nueva casi siempre llega primero vía un
-- partido, no vía una valoración suelta. Vigilar también
-- PLAYER_VALUATIONS con un segundo STREAM+TASK para este caso límite
-- sería complejidad extra para un beneficio marginal -- se documenta
-- como limitación aceptada: si alguna vez llega una valoración de una
-- temporada que aún no tiene ningún partido cargado, esa temporada no
-- se creará automáticamente en DIM_SEASON hasta que llegue el primer
-- partido de esa temporada (y entonces FACT_PLAYER_SEASON tampoco podrá
-- asignarle valor de mercado hasta ese momento).
--
-- AVISO (asunción a verificar): se asume que una temporada "SEASON = N"
-- corre de julio de N a junio de N+1 (convención habitual en fútbol
-- europeo). Verifícalo con:
--   SELECT SEASON, MIN(GAME_DATE), MAX(GAME_DATE)
--   FROM FOOTBALL.SILVER.GAMES GROUP BY SEASON ORDER BY SEASON DESC LIMIT 3;
-- =====================================================================

-- CREATE OR REPLACE, no IF NOT EXISTS: fuerza el esquema aquí definido aunque ya exista una DIM_SEASON previa con columnas distintas.
CREATE OR REPLACE TABLE FOOTBALL.GOLD.DIM_SEASON (
  SEASON_ID           NUMBER    NOT NULL,
  SEASON_LABEL        STRING,
  START_YEAR          NUMBER,
  END_YEAR            NUMBER,
  SEASON_START_DATE   DATE,
  SEASON_END_DATE     DATE,
  PRIMARY KEY (SEASON_ID)
);

-- ---------------------------------------------------------------------
-- Siembra inicial: todas las temporadas presentes ahora mismo en SILVER,
-- desde las dos fuentes. Ejecutar una sola vez, antes del CREATE STREAM.
-- ---------------------------------------------------------------------
INSERT INTO FOOTBALL.GOLD.DIM_SEASON (
  SEASON_ID, SEASON_LABEL, START_YEAR, END_YEAR, SEASON_START_DATE, SEASON_END_DATE
)
WITH SEASONS AS (
  SELECT DISTINCT SEASON AS SEASON_ID
  FROM FOOTBALL.SILVER.GAMES
  WHERE SEASON IS NOT NULL

  UNION

  SELECT DISTINCT
    CASE WHEN MONTH(VALUATION_DATE) < 7 THEN YEAR(VALUATION_DATE) - 1
         ELSE YEAR(VALUATION_DATE)
    END AS SEASON_ID
  FROM FOOTBALL.SILVER.PLAYER_VALUATIONS
  WHERE VALUATION_DATE IS NOT NULL
)
SELECT
  SEASON_ID,
  SEASON_ID::STRING || '/' || RIGHT((SEASON_ID + 1)::STRING, 2),
  SEASON_ID,
  SEASON_ID + 1,
  DATE_FROM_PARTS(SEASON_ID, 7, 1),
  DATE_FROM_PARTS(SEASON_ID + 1, 6, 30)
FROM SEASONS;

-- ---------------------------------------------------------------------
-- Automatización incremental (solo GAMES, ver aviso arriba)
-- ---------------------------------------------------------------------
CREATE STREAM IF NOT EXISTS FOOTBALL.GOLD.STREAM_SILVER_GAMES_FOR_SEASON
  ON TABLE FOOTBALL.SILVER.GAMES
  APPEND_ONLY = TRUE;

CREATE OR REPLACE TASK FOOTBALL.GOLD.TASK_LOAD_DIM_SEASON
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 9 * * 6 Europe/Madrid'
WHEN
  SYSTEM$STREAM_HAS_DATA('FOOTBALL.GOLD.STREAM_SILVER_GAMES_FOR_SEASON')
AS
MERGE INTO FOOTBALL.GOLD.DIM_SEASON AS tgt
USING (
  SELECT DISTINCT SEASON AS SEASON_ID
  FROM FOOTBALL.GOLD.STREAM_SILVER_GAMES_FOR_SEASON
  WHERE SEASON IS NOT NULL
) AS src
ON tgt.SEASON_ID = src.SEASON_ID
WHEN NOT MATCHED THEN INSERT (
  SEASON_ID, SEASON_LABEL, START_YEAR, END_YEAR, SEASON_START_DATE, SEASON_END_DATE
) VALUES (
  src.SEASON_ID,
  src.SEASON_ID::STRING || '/' || RIGHT((src.SEASON_ID + 1)::STRING, 2),
  src.SEASON_ID,
  src.SEASON_ID + 1,
  DATE_FROM_PARTS(src.SEASON_ID, 7, 1),
  DATE_FROM_PARTS(src.SEASON_ID + 1, 6, 30)
);
-- Nota: no hace falta WHEN MATCHED THEN UPDATE -- los atributos de una
-- temporada son una función pura de SEASON_ID y nunca cambian.

ALTER TASK FOOTBALL.GOLD.TASK_LOAD_DIM_SEASON RESUME;

-- Validación:
-- SELECT * FROM FOOTBALL.GOLD.DIM_SEASON ORDER BY SEASON_ID;
-- EXECUTE TASK FOOTBALL.GOLD.TASK_LOAD_DIM_SEASON;