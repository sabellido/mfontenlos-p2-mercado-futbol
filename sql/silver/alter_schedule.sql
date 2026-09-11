-- =====================================================================
-- SILVER · alter_schedule.sql
-- UTILIDAD: cambia la periodicidad de las 9 tasks de SILVER de "cada 5
-- minutos" a "cada sábado a las 8:30", para que compensen a la carga
-- real de ADF (configurada los sábados a las 8:00). No toca tablas,
-- streams, ni la lógica de los MERGE -- solo el SCHEDULE de la task.
--
-- POR QUÉ ALTER Y NO REEJECUTAR LOS 9 ARCHIVOS DE SILVER: cada archivo
-- usa CREATE TABLE IF NOT EXISTS y CREATE STREAM IF NOT EXISTS, así que
-- reejecutarlos no perdería datos ni reiniciaría el offset del stream
-- -- pero tampoco aportaría nada, porque lo único que cambia es el
-- SCHEDULE. ALTER TASK es la operación mínima que hace exactamente eso,
-- sin tocar de forma innecesaria objetos que ya están bien.
--
-- PATRÓN POR TASK: SUSPEND -> SET SCHEDULE -> RESUME. Snowflake exige
-- que una task esté suspendida para poder modificar su definición de
-- forma segura -- alterarla mientras sigue "corriendo" (aunque sea solo
-- esperando al siguiente disparo) puede dar error o dejarla en un
-- estado inconsistente. Por eso cada bloque suspende, cambia el
-- SCHEDULE, y vuelve a reanudar.
--
-- AVISO (zona horaria a confirmar): se asume que el trigger de ADF de
-- las 8:00 está en la zona horaria Europe/Madrid (la que verías por
-- defecto si trabajas desde España). Si al configurar el trigger en
-- Azure elegiste explícitamente UTC, cambia 'Europe/Madrid' por 'UTC'
-- en las 9 sentencias de abajo.
-- =====================================================================

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_COMPETITIONS SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_COMPETITIONS SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_COMPETITIONS RESUME;

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_CLUBS SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_CLUBS SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_CLUBS RESUME;

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_PLAYERS SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_PLAYERS SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_PLAYERS RESUME;

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_GAMES SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_GAMES SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_GAMES RESUME;

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_CLUB_GAMES SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_CLUB_GAMES SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_CLUB_GAMES RESUME;

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_APPEARANCES SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_APPEARANCES SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_APPEARANCES RESUME;

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_PLAYER_VALUATIONS SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_PLAYER_VALUATIONS SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_PLAYER_VALUATIONS RESUME;

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_TRANSFERS SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_TRANSFERS SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_TRANSFERS RESUME;

ALTER TASK FOOTBALL.SILVER.TASK_LOAD_COUNTRIES SUSPEND;
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_COUNTRIES SET SCHEDULE = 'USING CRON 30 8 * * 6 Europe/Madrid';
ALTER TASK FOOTBALL.SILVER.TASK_LOAD_COUNTRIES RESUME;

-- Validación: la columna "schedule" debe mostrar el CRON nuevo en las 9,
-- y "state" debe mostrar "started" (RESUME funcionó) en todas:
-- SHOW TASKS IN SCHEMA FOOTBALL.SILVER;
