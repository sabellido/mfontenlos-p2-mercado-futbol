-- =====================================================================
-- GOLD · 00_setup.sql
-- Objeto compartido: solo el schema FOOTBALL.GOLD.
--
-- AUTOMATIZACIÓN: igual patrón que SILVER (STREAM + TASK), en vez del
-- CTAS de refresco manual con el que se planteó GOLD la primera vez.
-- Cada tabla de GOLD tiene un STREAM sobre su(s) tabla(s) SILVER de
-- origen y una TASK que aplica un MERGE incremental si el STREAM tiene
-- datos pendientes -- exactamente el mismo mecanismo que ya conoces de
-- SILVER.
--
-- PERIODICIDAD (SCHEDULE): las tasks de GOLD están programadas para los
-- sábados a las 9:00 (Europe/Madrid), es decir, 30 minutos después que
-- las de SILVER (8:30), que a su vez van 30 minutos después de la carga
-- real de ADF (8:00). No es un número arbitrario tipo "cada 5 minutos":
-- está anclado a la cadencia real con la que llega dato nuevo -- una
-- vez por semana, el mismo día que se ejecuta la carga de origen. Cada
-- capa deja margen a la anterior (30 minutos) para que le dé tiempo a
-- terminar antes de que la siguiente intente leer sus resultados.
--
-- DIFERENCIA IMPORTANTE respecto a SILVER, para no repetir el problema
-- que tuvimos con TASK_LOAD_COMPETITIONS (el stream no hace backfill de
-- datos que ya existían antes de crearlo): cada archivo de GOLD sigue
-- este orden exacto -- (1) CREATE TABLE, (2) UN INSERT único de siembra
-- que calcula el contenido completo a partir de todo lo que ya hay en
-- SILVER ahora mismo, (3) solo DESPUÉS de eso, CREATE STREAM, (4) CREATE
-- TASK para los incrementos futuros. Como el STREAM se crea después de
-- la siembra, su punto de partida ya es "todo lo anterior está
-- reflejado en GOLD" -- no hace falta ningún INSERT manual posterior
-- como sí tuvimos que hacer en SILVER.
--
-- LÍMITE ACEPTADO (documentado, no un bug): las tasks de GOLD leen
-- otras tablas de GOLD/SILVER completas en el momento de ejecutarse
-- (p.ej. FACT_PLAYER_SEASON lee DIM_COMPETITION para el TIER). No están
-- encadenadas con AFTER -- se sincronizan por horario fijo (SILVER a
-- las 8:30, GOLD a las 9:00), no porque una dispare literalmente a la
-- otra. Si algún sábado las 9 tasks de SILVER tardaran más de 30
-- minutos en completarse (muy improbable con este volumen de datos),
-- GOLD leería SILVER todavía a medio actualizar esa semana. Encadenar
-- con AFTER eliminaría ese riesgo por completo, pero para una carga
-- semanal con este volumen, un margen fijo de 30 minutos es más simple
-- de explicar y suficiente en la práctica.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS FOOTBALL.GOLD;

USE DATABASE FOOTBALL;
USE SCHEMA GOLD;
