-- =====================================================================
-- GOLD · 03_dim_competition.sql
-- FOOTBALL.SILVER.COMPETITIONS -> FOOTBALL.GOLD.DIM_COMPETITION
--
-- IMPORTANTE: sustituye <TU_WAREHOUSE> por el nombre real de tu
-- warehouse antes de ejecutar el CREATE TASK.
--
-- Añade DISPLAY_NAME (nombre legible para Power BI, ya que SILVER.NAME
-- trae el slug tal cual, p.ej. "premier-league") y TIER (Elite / Medio /
-- Menor), la clasificación que alimenta el multiplicador de SCORE en
-- FACT_PLAYER_SEASON.
--
-- REGLA DE TIER (confirmada):
--   - Elite: las 5 grandes ligas por nombre fijo, MÁS cualquier
--     competición sin país propio (COUNTRY_NAME nulo: Champions League,
--     Europa League, Conference League, Super Cup, selecciones) -- no
--     tienen posición UEFA de país, se tratan como el nivel más alto.
--   - Menor: países en posición UEFA 22ª+ (Rusia, Rumanía, Ucrania,
--     Suecia, en los datos actuales).
--   - Medio: TODO LO DEMÁS -- tanto los países UEFA 6ª-21ª como las
--     ligas fuera del sistema UEFA (EEUU, Arabia Saudí, Australia,
--     Brasil, Corea del Sur, Argentina, México, Japón), que por
--     decisión explícita se tratan igual que un país UEFA de nivel
--     intermedio al no tener coeficiente propio. Cualquier país nuevo
--     no contemplado cae también aquí por defecto (ver README).
-- =====================================================================

-- CREATE OR REPLACE, no IF NOT EXISTS: fuerza el esquema aquí definido aunque ya exista una DIM_COMPETITION previa con columnas distintas.
CREATE OR REPLACE TABLE FOOTBALL.GOLD.DIM_COMPETITION (
  COMPETITION_ID          STRING    NOT NULL,
  COMPETITION_CODE        STRING,
  COMPETITION_NAME        STRING,
  DISPLAY_NAME            STRING,
  SUB_TYPE                STRING,
  TYPE                    STRING,
  COUNTRY_NAME            STRING,
  DOMESTIC_LEAGUE_CODE    STRING,
  CONFEDERATION           STRING,
  TOTAL_CLUBS             NUMBER,
  TIER                    STRING,
  URL                     STRING,
  PRIMARY KEY (COMPETITION_ID)
);

-- Siembra inicial:
INSERT INTO FOOTBALL.GOLD.DIM_COMPETITION (
  COMPETITION_ID, COMPETITION_CODE, COMPETITION_NAME, DISPLAY_NAME, SUB_TYPE, TYPE,
  COUNTRY_NAME, DOMESTIC_LEAGUE_CODE, CONFEDERATION, TOTAL_CLUBS, TIER, URL
)
SELECT
  COMPETITION_ID, COMPETITION_CODE, NAME AS COMPETITION_NAME,
  INITCAP(REPLACE(NAME, '-', ' ')) AS DISPLAY_NAME,
  SUB_TYPE, TYPE, COUNTRY_NAME, DOMESTIC_LEAGUE_CODE, CONFEDERATION, TOTAL_CLUBS,
  CASE
    WHEN COUNTRY_NAME IS NULL THEN 'Elite'
    WHEN COUNTRY_NAME IN ('England', 'Spain', 'Germany', 'Italy', 'France') THEN 'Elite'
    WHEN COUNTRY_NAME IN ('Russia', 'Romania', 'Ukraine', 'Sweden') THEN 'Menor'
    ELSE 'Medio'
  END AS TIER,
  URL
FROM FOOTBALL.SILVER.COMPETITIONS;

CREATE STREAM IF NOT EXISTS FOOTBALL.GOLD.STREAM_SILVER_COMPETITIONS
  ON TABLE FOOTBALL.SILVER.COMPETITIONS
  APPEND_ONLY = TRUE;

CREATE OR REPLACE TASK FOOTBALL.GOLD.TASK_LOAD_DIM_COMPETITION
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 9 * * 6 Europe/Madrid'
WHEN
  SYSTEM$STREAM_HAS_DATA('FOOTBALL.GOLD.STREAM_SILVER_COMPETITIONS')
AS
MERGE INTO FOOTBALL.GOLD.DIM_COMPETITION AS tgt
USING (
  SELECT
    COMPETITION_ID, COMPETITION_CODE, NAME AS COMPETITION_NAME,
    INITCAP(REPLACE(NAME, '-', ' ')) AS DISPLAY_NAME,
    SUB_TYPE, TYPE, COUNTRY_NAME, DOMESTIC_LEAGUE_CODE, CONFEDERATION, TOTAL_CLUBS,
    CASE
      WHEN COUNTRY_NAME IS NULL THEN 'Elite'
      WHEN COUNTRY_NAME IN ('England', 'Spain', 'Germany', 'Italy', 'France') THEN 'Elite'
      WHEN COUNTRY_NAME IN ('Russia', 'Romania', 'Ukraine', 'Sweden') THEN 'Menor'
      ELSE 'Medio'
    END AS TIER,
    URL
  FROM FOOTBALL.GOLD.STREAM_SILVER_COMPETITIONS
  WHERE COMPETITION_ID IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY COMPETITION_ID
    ORDER BY _SILVER_LOADED_AT DESC
  ) = 1
) AS src
ON tgt.COMPETITION_ID = src.COMPETITION_ID
WHEN MATCHED THEN UPDATE SET
  tgt.COMPETITION_CODE     = src.COMPETITION_CODE,
  tgt.COMPETITION_NAME     = src.COMPETITION_NAME,
  tgt.DISPLAY_NAME         = src.DISPLAY_NAME,
  tgt.SUB_TYPE             = src.SUB_TYPE,
  tgt.TYPE                 = src.TYPE,
  tgt.COUNTRY_NAME         = src.COUNTRY_NAME,
  tgt.DOMESTIC_LEAGUE_CODE = src.DOMESTIC_LEAGUE_CODE,
  tgt.CONFEDERATION        = src.CONFEDERATION,
  tgt.TOTAL_CLUBS          = src.TOTAL_CLUBS,
  tgt.TIER                 = src.TIER,
  tgt.URL                  = src.URL
WHEN NOT MATCHED THEN INSERT (
  COMPETITION_ID, COMPETITION_CODE, COMPETITION_NAME, DISPLAY_NAME, SUB_TYPE, TYPE,
  COUNTRY_NAME, DOMESTIC_LEAGUE_CODE, CONFEDERATION, TOTAL_CLUBS, TIER, URL
) VALUES (
  src.COMPETITION_ID, src.COMPETITION_CODE, src.COMPETITION_NAME, src.DISPLAY_NAME, src.SUB_TYPE,
  src.TYPE, src.COUNTRY_NAME, src.DOMESTIC_LEAGUE_CODE, src.CONFEDERATION,
  src.TOTAL_CLUBS, src.TIER, src.URL
);

ALTER TASK FOOTBALL.GOLD.TASK_LOAD_DIM_COMPETITION RESUME;

-- Validación:
-- SELECT TIER, COUNT(*) FROM FOOTBALL.GOLD.DIM_COMPETITION GROUP BY TIER ORDER BY TIER;
