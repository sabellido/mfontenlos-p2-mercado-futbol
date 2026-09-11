-- =====================================================================
-- GOLD · reset_gold.sql
-- UTILIDAD: vacía las 8 tablas GOLD (5 dimensiones + 3 hechos). No
-- borra tablas, streams ni tasks -- solo el contenido de las tablas.
--
-- AVISO IMPORTANTE: a diferencia de SILVER, los STREAM_SILVER_* de GOLD
-- vigilan tablas SILVER, no las tablas GOLD que este script vacía --
-- truncar aquí no toca esos streams para nada. Eso significa que, tras
-- este TRUNCATE:
--
--   - Si el STREAM correspondiente todavía tiene datos pendientes de
--     consumir, la siguiente ejecución de la TASK los recogerá con
--     normalidad, pero solo repobla lo que ese incremento trae -- no
--     el histórico completo que tenía la tabla antes de truncarla.
--
--   - En cualquier caso (haya o no datos pendientes en el stream), la
--     forma correcta de repoblar una tabla al completo tras este
--     TRUNCATE es volver a ejecutar su archivo de origen
--     (01_dim_season.sql .. 08_fact_transfer.sql): el CREATE OR REPLACE
--     TABLE + la siembra inicial recalculan el contenido entero desde
--     SILVER, igual que la primera vez. Respeta el orden del README
--     (01 y 03 antes que 06) si vas a repoblar FACT_PLAYER_SEASON.
--
-- ORDEN: hechos primero, dimensiones después -- sin FKs reales que
-- Snowflake fuerce, el orden no es obligatorio, pero evita dejar un
-- hueco visible en Power BI si alguien consulta a mitad de ejecución.
--
-- NOTA: VW_PLAYER_VALUE_TIMELINE (10_vw_player_value_timeline.sql) no
-- aparece aquí a propósito -- es una VISTA, no una tabla, así que no
-- almacena filas propias que vaciar. Al ser un UNION ALL calculado al
-- vuelo sobre FACT_PLAYER_MARKET_VALUE y FACT_TRANSFER, truncar esas dos
-- tablas ya "vacía" lo que la vista mostraría.
-- =====================================================================

TRUNCATE TABLE FOOTBALL.GOLD.FACT_PLAYER_MARKET_VALUE;
TRUNCATE TABLE FOOTBALL.GOLD.FACT_TRANSFER;
TRUNCATE TABLE FOOTBALL.GOLD.FACT_CLUB_GAME;
TRUNCATE TABLE FOOTBALL.GOLD.FACT_PLAYER_SEASON;
TRUNCATE TABLE FOOTBALL.GOLD.DIM_PLAYER;
TRUNCATE TABLE FOOTBALL.GOLD.DIM_CLUB;
TRUNCATE TABLE FOOTBALL.GOLD.DIM_COMPETITION;
TRUNCATE TABLE FOOTBALL.GOLD.DIM_COUNTRY;
TRUNCATE TABLE FOOTBALL.GOLD.DIM_SEASON;
