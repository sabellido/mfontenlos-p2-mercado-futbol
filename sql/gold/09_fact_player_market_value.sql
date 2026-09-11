-- =====================================================================
-- GOLD · 09_fact_player_market_value.sql
-- FOOTBALL.SILVER.PLAYER_VALUATIONS -> FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE
--
-- POR QUÉ EXISTE ESTA TABLA (no estaba en el diseño original de GOLD):
-- FACT_PLAYER_SEASON solo guarda UN valor de mercado por jugador-temporada
-- (el último dentro del rango de fechas de la temporada, según decidimos).
-- Eso es correcto para el resto del informe, pero para la ficha de
-- jugador (página de detalle vía drillthrough) queremos el gráfico de
-- evolución con TODOS los cambios de valor reales, no uno por temporada.
--
-- Importante: esto NO requiere tocar SILVER. SILVER.PLAYER_VALUATIONS ya
-- tiene el grano correcto -- una fila por (PLAYER_ID, VALUATION_DATE),
-- igual que llega del CSV de Transfermarkt. Lo único que faltaba era
-- exponer ese histórico completo en GOLD, en vez de aplastarlo a un
-- valor por temporada. Por eso esta tabla es un passthrough 1 a 1 de
-- SILVER, con el mismo patrón STREAM+TASK que DIM_CLUB o FACT_TRANSFER
-- (grano origen = grano destino), no el patrón de recálculo que usa
-- FACT_PLAYER_SEASON.
--
-- Grano: un valor de mercado por jugador y fecha de valoración.
-- =====================================================================

CREATE TABLE IF NOT EXISTS FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE (
  PLAYER_ID           NUMBER    NOT NULL,
  VALUATION_DATE       DATE      NOT NULL,
  MARKET_VALUE_EUR     NUMBER,
  CLUB_ID              NUMBER,
  COMPETITION_ID       STRING,
  PRIMARY KEY (PLAYER_ID, VALUATION_DATE)
);

-- Siembra inicial: todo el histórico que ya existe en SILVER a día de hoy.
INSERT INTO FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE (
  PLAYER_ID, VALUATION_DATE, MARKET_VALUE_EUR, CLUB_ID, COMPETITION_ID
)
SELECT
  PLAYER_ID,
  VALUATION_DATE,
  MARKET_VALUE_IN_EUR,
  CURRENT_CLUB_ID,
  PLAYER_CLUB_DOMESTIC_COMPETITION_ID
FROM FOOTBALL.SILVER.PLAYER_VALUATIONS;

-- El stream se crea DESPUÉS de la siembra (mismo motivo que en el resto
-- de GOLD): su punto de partida ya es "todo lo anterior está reflejado",
-- así que no hace falta ningún INSERT manual adicional.
CREATE STREAM IF NOT EXISTS FOOTBALL.GOLD.STREAM_SILVER_PLAYER_VALUATIONS
  ON TABLE FOOTBALL.SILVER.PLAYER_VALUATIONS
  APPEND_ONLY = TRUE;

CREATE OR REPLACE TASK FOOTBALL.GOLD.TASK_LOAD_FACT_PLAYER_MARKET_VALUE
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 9 * * 6 Europe/Madrid'
WHEN
  SYSTEM$STREAM_HAS_DATA('FOOTBALL.GOLD.STREAM_SILVER_PLAYER_VALUATIONS')
AS
MERGE INTO FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE AS tgt
USING (
  SELECT
    PLAYER_ID,
    VALUATION_DATE,
    MARKET_VALUE_IN_EUR                    AS MARKET_VALUE_EUR,
    CURRENT_CLUB_ID                        AS CLUB_ID,
    PLAYER_CLUB_DOMESTIC_COMPETITION_ID    AS COMPETITION_ID
  FROM FOOTBALL.GOLD.STREAM_SILVER_PLAYER_VALUATIONS
  WHERE PLAYER_ID IS NOT NULL AND VALUATION_DATE IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY PLAYER_ID, VALUATION_DATE
    ORDER BY _SILVER_LOADED_AT DESC
  ) = 1
) AS src
ON tgt.PLAYER_ID = src.PLAYER_ID AND tgt.VALUATION_DATE = src.VALUATION_DATE
WHEN MATCHED THEN UPDATE SET
  tgt.MARKET_VALUE_EUR = src.MARKET_VALUE_EUR,
  tgt.CLUB_ID          = src.CLUB_ID,
  tgt.COMPETITION_ID   = src.COMPETITION_ID
WHEN NOT MATCHED THEN INSERT (
  PLAYER_ID, VALUATION_DATE, MARKET_VALUE_EUR, CLUB_ID, COMPETITION_ID
) VALUES (
  src.PLAYER_ID, src.VALUATION_DATE, src.MARKET_VALUE_EUR, src.CLUB_ID, src.COMPETITION_ID
);

ALTER TASK FOOTBALL.GOLD.TASK_LOAD_FACT_PLAYER_MARKET_VALUE RESUME;

-- Validación:
-- SELECT COUNT(*), COUNT(DISTINCT PLAYER_ID) FROM FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE;
-- SELECT * FROM FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE WHERE PLAYER_ID = <algún id> ORDER BY VALUATION_DATE;
