-- =====================================================================
-- SILVER · 00_setup.sql
-- Objeto compartido de la capa SILVER: únicamente el schema. A
-- diferencia de RAW, SILVER no necesita integrations ni stages -- todo
-- lo que hace vive dentro de Snowflake (lee de RAW, escribe en SILVER),
-- no habla con Azure en ningún momento.
-- Ver silver/README.md para el porqué de cada decisión de diseño.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS FOOTBALL.SILVER;

USE DATABASE FOOTBALL;
USE SCHEMA SILVER;

-- Cada archivo de tabla (01_competitions.sql, 02_clubs.sql...) crea, por
-- sí mismo: la tabla SILVER tipada, un STREAM sobre su tabla RAW
-- correspondiente, y una TASK que aplica el MERGE de tipado + limpieza +
-- deduplicación automáticamente en cuanto el STREAM tiene datos nuevos.
-- No hay nada más que compartir entre tablas, así que este setup es
-- deliberadamente mínimo.
