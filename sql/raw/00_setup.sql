-- =====================================================================
-- RAW · 00_setup.sql
-- Objetos COMPARTIDOS por toda la capa RAW: base de datos, schema,
-- integración de almacenamiento con Azure Blob, stage externo, el file
-- format y la integración de notificaciones para Snowpipe.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS FOOTBALL;
CREATE SCHEMA IF NOT EXISTS FOOTBALL.RAW;

USE DATABASE FOOTBALL;
USE SCHEMA RAW;

-- ---------------------------------------------------------------------
-- Storage Integration: acceso de Snowflake al contenedor de Azure Blob
-- vía Azure AD (sin SAS token embebido). Ver raw/README.md.
-- Actúa de puente entre Azure y Snowflake
-- ---------------------------------------------------------------------
CREATE OR REPLACE STORAGE INTEGRATION integration_azure_blob_raw
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '35cd5c67-eb9c-4930-a44c-845061d6b9c3'
  STORAGE_ALLOWED_LOCATIONS = ('azure://stp2futbolmfontenlos.blob.core.windows.net/raw/');

-- Da AZURE_CONSENT_URL / AZURE_MULTI_TENANT_APP_NAME (solo necesario la
-- primera vez, para el consentimiento de administrador en Azure AD).
DESC STORAGE INTEGRATION integration_azure_blob_raw;

CREATE OR REPLACE STAGE stage_raw_blob
  URL = 'azure://stp2futbolmfontenlos.blob.core.windows.net/raw/'
  STORAGE_INTEGRATION = integration_azure_blob_raw;

-- Prueba de acceso end-to-end (integration + RBAC + stage correctos).
LIST @stage_raw_blob;

-- ---------------------------------------------------------------------
-- File format único. PARSE_HEADER = TRUE le sirve a la vez para:
--   1) INFER_SCHEMA (descubrir nombres de columna reales)
--   2) CREATE TABLE ... USING TEMPLATE (generar la tabla automáticamente)
--   3) COPY INTO / pipes con MATCH_BY_COLUMN_NAME (cargar automáticamente
--      emparejando por nombre de columna, sin contar campos a mano)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FILE FORMAT FOOTBALL.RAW.FF_CSV_INFER
  TYPE = CSV
  FIELD_DELIMITER = ','
  PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NA', 'null')
  EMPTY_FIELD_AS_NULL = TRUE
  ENCODING = 'UTF8';

-- ---------------------------------------------------------------------
-- Notification Integration: puente entre la Storage Queue de Azure
-- (donde Event Grid deposita los eventos "blob creado") y los pipes de
-- Snowflake (AUTO_INGEST = TRUE). Ver raw/README.md, sección "Ingesta
-- automática".
-- ---------------------------------------------------------------------
CREATE OR REPLACE NOTIFICATION INTEGRATION ni_azure_blob_events
  TYPE = QUEUE
  NOTIFICATION_PROVIDER = AZURE_STORAGE_QUEUE
  ENABLED = TRUE
  AZURE_STORAGE_QUEUE_PRIMARY_URI = 'https://stp2futbolmfontenlos.queue.core.windows.net/snowpipe-landing-queue'
  AZURE_TENANT_ID = '35cd5c67-eb9c-4930-a44c-845061d6b9c3';

-- Igual que con la storage integration: puede devolver un consent URL
-- la primera vez. Si es la misma app ya consentida, solo falta el rol
-- RBAC "Procesador de mensajes de datos de Queue Storage" sobre la cola.
DESC NOTIFICATION INTEGRATION ni_azure_blob_events;

SELECT SYSTEM$PIPE_STATUS('FOOTBALL.RAW.PIPE_COMPETITIONS');
