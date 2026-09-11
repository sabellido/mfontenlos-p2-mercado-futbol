-- =====================================================================
-- GOLD · 06_fact_player_season.sql
-- FOOTBALL.SILVER.APPEARANCES + FOOTBALL.SILVER.GAMES
--   + FOOTBALL.SILVER.PLAYER_VALUATIONS + FOOTBALL.GOLD.DIM_COMPETITION
--   + FOOTBALL.GOLD.DIM_SEASON
--   -> FOOTBALL.GOLD.FACT_PLAYER_SEASON
--
-- IMPORTANTE: sustituye <TU_WAREHOUSE> por el nombre real de tu
-- warehouse antes de ejecutar el CREATE TASK. Ejecuta 01_dim_season.sql
-- y 03_dim_competition.sql antes que este archivo -- la siembra de aquí
-- necesita que esas dos tablas ya tengan datos.
--
-- GRANO: jugador x temporada x club x competición (el que pide el
-- enunciado). Cada fila responde a "¿cuánto hizo este jugador, en esta
-- temporada, jugando para este club, en esta competición concreta?".
--
-- CÓMO SE AUTOMATIZA UNA TABLA DE HECHOS AGREGADA (distinto de SILVER):
-- en SILVER, el STREAM+TASK copiaba filas 1 a 1 desde RAW (mismo grano
-- origen y destino). Aquí NO -- una fila nueva en APPEARANCES no se
-- inserta tal cual en FACT_PLAYER_SEASON, sino que hay que RECALCULAR el
-- agregado de la clave (jugador, temporada, club, competición) a la que
-- pertenece esa aparición. La task hace esto en dos pasos:
--   1. Usa el STREAM solo para averiguar QUÉ claves de grano se han
--      visto tocadas por apariciones nuevas desde la última ejecución
--      (AFFECTED_KEYS).
--   2. Para esas claves exactas, recalcula el agregado COMPLETO
--      releyendo TODA la tabla SILVER.APPEARANCES (no el stream)
--      filtrada a esas claves, y hace MERGE del resultado. Recalcular
--      desde cero en vez de "sumar el delta sobre la fila existente" es
--      importante para que la task sea segura de re-ejecutar: si algo
--      falla a mitad y Snowflake reintenta, sumar el delta dos veces
--      duplicaría goles; recalcular el total siempre da el mismo
--      resultado correcto, se ejecute una vez o varias.
--
-- LÍMITE ACEPTADO: el STREAM que dispara esta task vigila solo
-- APPEARANCES. Si algún día SILVER.GAMES o SILVER.PLAYER_VALUATIONS
-- recibieran una fila nueva SIN que llegue ninguna aparición nueva
-- asociada a esa clave, ese cambio no dispararía una recomputación
-- automática hasta que sí llegue una aparición nueva para esa clave.
-- Se acepta esta simplificación porque, en la práctica, una aparición
-- nueva es justamente lo que motiva que exista una fila nueva o
-- actualizada en este hecho.
--
-- SCORE Y VALOR DE MERCADO: mismas reglas ya documentadas en el README
-- de GOLD (tiering tipo Bota de Oro por TIER de la competición, último
-- valor de mercado dentro de la temporada).
-- =====================================================================

-- CREATE OR REPLACE, no IF NOT EXISTS: fuerza el esquema aquí definido aunque ya exista una FACT_PLAYER_SEASON previa con columnas distintas.
CREATE OR REPLACE TABLE FOOTBALL.GOLD.FACT_PLAYER_SEASON (
  PLAYER_ID           NUMBER        NOT NULL,
  SEASON_ID           NUMBER        NOT NULL,
  CLUB_ID             NUMBER        NOT NULL,
  COMPETITION_ID       STRING        NOT NULL,
  APPEARANCES_COUNT    NUMBER,
  MINUTES_PLAYED       NUMBER,
  GOALS                NUMBER,
  ASSISTS              NUMBER,
  YELLOW_CARDS         NUMBER,
  RED_CARDS            NUMBER,
  TIER                 STRING,
  SCORE                NUMBER(10,2),
  MARKET_VALUE_EUR     NUMBER,
  PRIMARY KEY (PLAYER_ID, SEASON_ID, CLUB_ID, COMPETITION_ID)
);

-- ---------------------------------------------------------------------
-- Siembra inicial: agregación completa sobre todo lo que ya hay en
-- SILVER ahora mismo. Ejecutar una sola vez, antes del CREATE STREAM.
-- ---------------------------------------------------------------------
INSERT INTO FOOTBALL.GOLD.FACT_PLAYER_SEASON (
  PLAYER_ID, SEASON_ID, CLUB_ID, COMPETITION_ID, APPEARANCES_COUNT,
  MINUTES_PLAYED, GOALS, ASSISTS, YELLOW_CARDS, RED_CARDS, TIER, SCORE,
  MARKET_VALUE_EUR
)
WITH AGG AS (
  SELECT
    a.PLAYER_ID,
    g.SEASON                AS SEASON_ID,
    a.PLAYER_CLUB_ID         AS CLUB_ID,
    a.COMPETITION_ID,
    COUNT(a.APPEARANCE_ID)   AS APPEARANCES_COUNT,
    SUM(a.MINUTES_PLAYED)    AS MINUTES_PLAYED,
    SUM(a.GOALS)             AS GOALS,
    SUM(a.ASSISTS)           AS ASSISTS,
    SUM(a.YELLOW_CARDS)      AS YELLOW_CARDS,
    SUM(a.RED_CARDS)         AS RED_CARDS
  FROM FOOTBALL.SILVER.APPEARANCES a
  JOIN FOOTBALL.SILVER.GAMES g ON a.GAME_ID = g.GAME_ID
  WHERE g.SEASON IS NOT NULL
    AND a.PLAYER_CLUB_ID IS NOT NULL
    AND a.COMPETITION_ID IS NOT NULL
  GROUP BY a.PLAYER_ID, g.SEASON, a.PLAYER_CLUB_ID, a.COMPETITION_ID
),
SCORED AS (
  SELECT
    agg.*,
    comp.TIER,
    ROUND(
      agg.GOALS   * CASE comp.TIER WHEN 'Elite' THEN 2.0 WHEN 'Medio' THEN 1.5 WHEN 'Menor' THEN 1.0 END
      + agg.ASSISTS * CASE comp.TIER WHEN 'Elite' THEN 1.0 WHEN 'Medio' THEN 0.75 WHEN 'Menor' THEN 0.5 END
      - agg.YELLOW_CARDS * 1
      - agg.RED_CARDS * 3
    , 2) AS SCORE
  FROM AGG agg
  JOIN FOOTBALL.GOLD.DIM_COMPETITION comp ON agg.COMPETITION_ID = comp.COMPETITION_ID
),
LAST_VALUATION AS (
  SELECT
    v.PLAYER_ID, s.SEASON_ID, v.MARKET_VALUE_IN_EUR,
    ROW_NUMBER() OVER (
      PARTITION BY v.PLAYER_ID, s.SEASON_ID
      ORDER BY v.VALUATION_DATE DESC
    ) AS RN
  FROM FOOTBALL.SILVER.PLAYER_VALUATIONS v
  JOIN FOOTBALL.GOLD.DIM_SEASON s
    ON v.VALUATION_DATE BETWEEN s.SEASON_START_DATE AND s.SEASON_END_DATE
)
SELECT
  sc.PLAYER_ID, sc.SEASON_ID, sc.CLUB_ID, sc.COMPETITION_ID,
  sc.APPEARANCES_COUNT, sc.MINUTES_PLAYED, sc.GOALS, sc.ASSISTS,
  sc.YELLOW_CARDS, sc.RED_CARDS, sc.TIER, sc.SCORE,
  lv.MARKET_VALUE_IN_EUR AS MARKET_VALUE_EUR
FROM SCORED sc
LEFT JOIN LAST_VALUATION lv
  ON sc.PLAYER_ID = lv.PLAYER_ID AND sc.SEASON_ID = lv.SEASON_ID AND lv.RN = 1;

-- ---------------------------------------------------------------------
-- Automatización incremental
-- ---------------------------------------------------------------------
CREATE STREAM IF NOT EXISTS FOOTBALL.GOLD.STREAM_SILVER_APPEARANCES
  ON TABLE FOOTBALL.SILVER.APPEARANCES
  APPEND_ONLY = TRUE;

CREATE OR REPLACE TASK FOOTBALL.GOLD.TASK_LOAD_FACT_PLAYER_SEASON
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 9 * * 6 Europe/Madrid'
WHEN
  SYSTEM$STREAM_HAS_DATA('FOOTBALL.GOLD.STREAM_SILVER_APPEARANCES')
AS
MERGE INTO FOOTBALL.GOLD.FACT_PLAYER_SEASON AS tgt
USING (
  WITH AFFECTED_KEYS AS (
    SELECT DISTINCT
      a.PLAYER_ID,
      g.SEASON        AS SEASON_ID,
      a.PLAYER_CLUB_ID AS CLUB_ID,
      a.COMPETITION_ID
    FROM FOOTBALL.GOLD.STREAM_SILVER_APPEARANCES a
    JOIN FOOTBALL.SILVER.GAMES g ON a.GAME_ID = g.GAME_ID
    WHERE g.SEASON IS NOT NULL
      AND a.PLAYER_CLUB_ID IS NOT NULL
      AND a.COMPETITION_ID IS NOT NULL
  ),
  RECOMPUTED AS (
    SELECT
      a.PLAYER_ID,
      g.SEASON                AS SEASON_ID,
      a.PLAYER_CLUB_ID         AS CLUB_ID,
      a.COMPETITION_ID,
      COUNT(a.APPEARANCE_ID)   AS APPEARANCES_COUNT,
      SUM(a.MINUTES_PLAYED)    AS MINUTES_PLAYED,
      SUM(a.GOALS)             AS GOALS,
      SUM(a.ASSISTS)           AS ASSISTS,
      SUM(a.YELLOW_CARDS)      AS YELLOW_CARDS,
      SUM(a.RED_CARDS)         AS RED_CARDS
    FROM FOOTBALL.SILVER.APPEARANCES a
    JOIN FOOTBALL.SILVER.GAMES g ON a.GAME_ID = g.GAME_ID
    JOIN AFFECTED_KEYS k
      ON a.PLAYER_ID = k.PLAYER_ID
     AND g.SEASON = k.SEASON_ID
     AND a.PLAYER_CLUB_ID = k.CLUB_ID
     AND a.COMPETITION_ID = k.COMPETITION_ID
    GROUP BY a.PLAYER_ID, g.SEASON, a.PLAYER_CLUB_ID, a.COMPETITION_ID
  ),
  SCORED AS (
    SELECT
      r.*,
      comp.TIER,
      ROUND(
        r.GOALS   * CASE comp.TIER WHEN 'Elite' THEN 2.0 WHEN 'Medio' THEN 1.5 WHEN 'Menor' THEN 1.0 END
        + r.ASSISTS * CASE comp.TIER WHEN 'Elite' THEN 1.0 WHEN 'Medio' THEN 0.75 WHEN 'Menor' THEN 0.5 END
        - r.YELLOW_CARDS * 1
        - r.RED_CARDS * 3
      , 2) AS SCORE
    FROM RECOMPUTED r
    JOIN FOOTBALL.GOLD.DIM_COMPETITION comp ON r.COMPETITION_ID = comp.COMPETITION_ID
  ),
  LAST_VALUATION AS (
    SELECT
      v.PLAYER_ID, s.SEASON_ID, v.MARKET_VALUE_IN_EUR,
      ROW_NUMBER() OVER (
        PARTITION BY v.PLAYER_ID, s.SEASON_ID
        ORDER BY v.VALUATION_DATE DESC
      ) AS RN
    FROM FOOTBALL.SILVER.PLAYER_VALUATIONS v
    JOIN FOOTBALL.GOLD.DIM_SEASON s
      ON v.VALUATION_DATE BETWEEN s.SEASON_START_DATE AND s.SEASON_END_DATE
    JOIN AFFECTED_KEYS k ON v.PLAYER_ID = k.PLAYER_ID AND s.SEASON_ID = k.SEASON_ID
  )
  SELECT
    sc.PLAYER_ID, sc.SEASON_ID, sc.CLUB_ID, sc.COMPETITION_ID,
    sc.APPEARANCES_COUNT, sc.MINUTES_PLAYED, sc.GOALS, sc.ASSISTS,
    sc.YELLOW_CARDS, sc.RED_CARDS, sc.TIER, sc.SCORE,
    lv.MARKET_VALUE_IN_EUR AS MARKET_VALUE_EUR
  FROM SCORED sc
  LEFT JOIN LAST_VALUATION lv
    ON sc.PLAYER_ID = lv.PLAYER_ID AND sc.SEASON_ID = lv.SEASON_ID AND lv.RN = 1
) AS src
ON tgt.PLAYER_ID = src.PLAYER_ID
  AND tgt.SEASON_ID = src.SEASON_ID
  AND tgt.CLUB_ID = src.CLUB_ID
  AND tgt.COMPETITION_ID = src.COMPETITION_ID
WHEN MATCHED THEN UPDATE SET
  tgt.APPEARANCES_COUNT = src.APPEARANCES_COUNT,
  tgt.MINUTES_PLAYED    = src.MINUTES_PLAYED,
  tgt.GOALS             = src.GOALS,
  tgt.ASSISTS           = src.ASSISTS,
  tgt.YELLOW_CARDS      = src.YELLOW_CARDS,
  tgt.RED_CARDS         = src.RED_CARDS,
  tgt.TIER              = src.TIER,
  tgt.SCORE             = src.SCORE,
  tgt.MARKET_VALUE_EUR  = src.MARKET_VALUE_EUR
WHEN NOT MATCHED THEN INSERT (
  PLAYER_ID, SEASON_ID, CLUB_ID, COMPETITION_ID, APPEARANCES_COUNT,
  MINUTES_PLAYED, GOALS, ASSISTS, YELLOW_CARDS, RED_CARDS, TIER, SCORE,
  MARKET_VALUE_EUR
) VALUES (
  src.PLAYER_ID, src.SEASON_ID, src.CLUB_ID, src.COMPETITION_ID,
  src.APPEARANCES_COUNT, src.MINUTES_PLAYED, src.GOALS, src.ASSISTS,
  src.YELLOW_CARDS, src.RED_CARDS, src.TIER, src.SCORE, src.MARKET_VALUE_EUR
);

ALTER TASK FOOTBALL.GOLD.TASK_LOAD_FACT_PLAYER_SEASON RESUME;

-- Validación:
-- SELECT (SELECT COUNT(*) FROM FOOTBALL.SILVER.APPEARANCES) AS TOTAL_APPEARANCES,
--        (SELECT SUM(APPEARANCES_COUNT) FROM FOOTBALL.GOLD.FACT_PLAYER_SEASON) AS APPEARANCES_EN_GOLD;
-- SELECT * FROM FOOTBALL.GOLD.FACT_PLAYER_SEASON ORDER BY SCORE DESC LIMIT 20;
-- EXECUTE TASK FOOTBALL.GOLD.TASK_LOAD_FACT_PLAYER_SEASON;
