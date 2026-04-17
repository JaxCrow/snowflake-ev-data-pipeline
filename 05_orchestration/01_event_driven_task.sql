-- ============================================================
-- 05_ORCHESTRATION: Event-Driven Pipeline (GCP -> Snowflake)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE EV_PROJECT_DB;
USE SCHEMA BRONZE;

-- 1. Habilitar la Directory Table en el Stage para recibir notificaciones
ALTER STAGE EV_PROJECT_DB.BRONZE.GCP_EV_STAGE SET
  DIRECTORY = (
    ENABLE            = TRUE,
    AUTO_REFRESH      = TRUE,
    NOTIFICATION_INTEGRATION = 'GCP_EV_PUBSUB_INT'
  );

-- 2. Crear el Stream para detectar nuevos archivos (Change Data Capture en Stage)
CREATE OR REPLACE STREAM EV_PROJECT_DB.BRONZE.GCS_FILES_STREAM 
ON STAGE EV_PROJECT_DB.BRONZE.GCP_EV_STAGE;

-- 3. Crear la Tarea automatizada que llama al Stored Procedure de Python
-- Esta tarea se dispara cada 1 minuto, pero solo consume cómputo si hay datos en el Stream.
CREATE OR REPLACE TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA
    WAREHOUSE = COMPUTE_WH 
    SCHEDULE = '1 MINUTE'
WHEN
    SYSTEM$STREAM_HAS_DATA('EV_PROJECT_DB.BRONZE.GCS_FILES_STREAM')
AS
    CALL EV_PROJECT_DB.BRONZE.SP_INGEST_RAW_EV_DATA();

-- 4. Activar la tarea (Las tareas nacen suspendidas por seguridad)
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA RESUME;

-- Verificación de estado
SHOW STREAMS;
SHOW TASKS;