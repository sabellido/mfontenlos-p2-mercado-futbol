-- =====================================================================
-- SILVER · reset_silver.sql
-- UTILIDAD: vacía las 9 tablas SILVER. No borra tablas, streams ni
-- tasks -- solo el contenido de las tablas.
--
-- AVISO IMPORTANTE: a diferencia de RAW, aquí no hay ningún pipe ni
-- Snowpipe de por medio, pero el mismo tipo de matiz aplica al STREAM:
-- truncar SILVER no mueve ni reinicia el offset del STREAM que vigila
-- la tabla RAW correspondiente. Eso significa que, tras este TRUNCATE:
--
--   - Si el STREAM todavía tiene datos pendientes de consumir, la
--     siguiente ejecución de la TASK los recogerá con normalidad y
--     repoblará la tabla sin que tengas que hacer nada más.
--
--   - Si el STREAM ya está vacío (SYSTEM$STREAM_HAS_DATA = FALSE,
--     como nos pasa ahora mismo con COMPETITIONS), truncar SILVER NO
--     hace que el STREAM "recuerde" las filas antiguas de RAW -- ya se
--     consideran vistas desde el punto de vista del stream, aunque
--     acabes de borrar su copia en SILVER. En ese caso hay que repetir
--     la siembra inicial manual, con un INSERT directo desde la tabla
--     RAW correspondiente (no desde el stream), igual que la primera
--     vez.
-- =====================================================================

TRUNCATE TABLE FOOTBALL.SILVER.COMPETITIONS;
TRUNCATE TABLE FOOTBALL.SILVER.CLUBS;
TRUNCATE TABLE FOOTBALL.SILVER.PLAYERS;
TRUNCATE TABLE FOOTBALL.SILVER.GAMES;
TRUNCATE TABLE FOOTBALL.SILVER.CLUB_GAMES;
TRUNCATE TABLE FOOTBALL.SILVER.APPEARANCES;
TRUNCATE TABLE FOOTBALL.SILVER.PLAYER_VALUATIONS;
TRUNCATE TABLE FOOTBALL.SILVER.TRANSFERS;
TRUNCATE TABLE FOOTBALL.SILVER.COUNTRIES;

