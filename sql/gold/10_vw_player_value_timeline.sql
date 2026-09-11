-- =====================================================================
-- GOLD · 10_vw_player_value_timeline.sql
-- FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE + FOOTBALL.GOLD.FACT_TRANSFER
--   -> FOOTBALL.GOLD.VW_PLAYER_VALUE_TIMELINE  (VISTA, no tabla)
--
-- POR QUÉ EXISTE ESTA VISTA:
-- En la ficha de jugador queremos un gráfico combinado (línea + barras)
-- que muestre en el mismo eje de fechas tanto la evolución del valor de
-- mercado (FACT_PLAYER_MARKET_VALUE.VALUATION_DATE) como el importe de
-- cada traspaso (FACT_TRANSFER.TRANSFER_DATE). Power BI necesita que el
-- eje de categorías de un gráfico combinado venga de UNA sola columna
-- de UNA sola tabla -- no se puede poner "VALUATION_DATE" como eje y
-- luego colgar una medida de FACT_TRANSFER esperando que Power BI
-- "empareje" fechas de dos tablas sin relación entre sí. Como las
-- fechas de valoración y las de traspaso son independientes (casi nunca
-- coinciden el mismo día) y el proyecto prescinde deliberadamente de una
-- DIM_DATE, la única forma correcta de conseguir un eje compartido es
-- unificar ambos tipos de evento en una sola fila por (jugador, fecha).
--
-- POR QUÉ ES UNA VISTA Y NO UNA TABLA (sin STREAM/TASK propios):
-- FACT_PLAYER_MARKET_VALUE y FACT_TRANSFER ya están automatizadas cada
-- una con su propio STREAM+TASK semanal (ver 09_fact_player_market_value.sql
-- y 08_fact_transfer.sql). Montar una TERCERA tabla física que dependa de
-- dos streams distintos obligaría a duplicar esa automatización sin
-- necesidad: cada vez que se consulta esta vista, Snowflake hace el UNION
-- ALL al vuelo sobre las dos tablas GOLD, que ya están al día. Es más
-- simple, no puede quedarse "desincronizada" respecto a sus fuentes, y no
-- añade ningún objeto (STREAM/TASK) más que mantener o vigilar. El coste
-- -- recalcular el UNION en cada consulta -- es irrelevante al volumen de
-- este dataset y Power BI la importa igual que una tabla al hacer refresh.
--
-- Grano: un evento (valoración de mercado O traspaso) por jugador y
-- fecha de evento. EVENT_TYPE distingue de qué tipo es cada fila;
-- MARKET_VALUE_EUR solo va relleno en filas de valoración, TRANSFER_FEE
-- solo en filas de traspaso (por eso el gráfico combinado no "mezcla"
-- los dos importes: cada medida solo tiene datos en su propio tipo de
-- fila, y Sum() de la otra da 0/blank automáticamente).
-- =====================================================================

CREATE OR REPLACE VIEW FOOTBALL.GOLD.VW_PLAYER_VALUE_TIMELINE AS
SELECT
  PLAYER_ID,
  VALUATION_DATE                  AS EVENT_DATE,
  'Valoración'                    AS EVENT_TYPE,
  MARKET_VALUE_EUR                AS MARKET_VALUE_EUR,
  CAST(NULL AS NUMBER)            AS TRANSFER_FEE,
  CAST(NULL AS NUMBER)            AS FROM_CLUB_ID,
  CAST(NULL AS NUMBER)            AS TO_CLUB_ID
FROM FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE

UNION ALL

SELECT
  PLAYER_ID,
  TRANSFER_DATE                   AS EVENT_DATE,
  'Traspaso'                      AS EVENT_TYPE,
  CAST(NULL AS NUMBER)            AS MARKET_VALUE_EUR,
  TRANSFER_FEE                    AS TRANSFER_FEE,
  FROM_CLUB_ID                    AS FROM_CLUB_ID,
  TO_CLUB_ID                      AS TO_CLUB_ID
FROM FOOTBALL.GOLD.FACT_TRANSFER;

-- No hay siembra, STREAM ni TASK que crear: al ser una vista, no
-- almacena datos propios -- simplemente no aplica el patrón STREAM+TASK
-- del resto de GOLD. reset_gold.sql tampoco necesita tocarla (ver nota
-- en ese archivo).

-- Validación:
-- SELECT EVENT_TYPE, COUNT(*) FROM FOOTBALL.GOLD.VW_PLAYER_VALUE_TIMELINE GROUP BY EVENT_TYPE;
-- SELECT * FROM FOOTBALL.GOLD.VW_PLAYER_VALUE_TIMELINE WHERE PLAYER_ID = <algún id> ORDER BY EVENT_DATE;
