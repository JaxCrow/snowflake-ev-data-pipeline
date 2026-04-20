-- ============================================================
-- 02_BRONZE.sql
-- Raw ingestion layer: stage, file format, stream, table,
-- ingestion SP (Snowpark Python), task DAG
-- ============================================================

USE SCHEMA EV_PROJECT_DB.BRONZE;

-- File Format
CREATE OR REPLACE FILE FORMAT EV_PROJECT_DB.BRONZE.JSON_FORMAT
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = FALSE;

-- External Stage (GCS with directory enabled for stream)
CREATE OR REPLACE STAGE GCP_EV_STAGE
  STORAGE_INTEGRATION = GCP_EV_STORAGE_INT
  URL = 'gcs://ev-landing-zone-lordrivas/landing/'
  DIRECTORY = (ENABLE = TRUE AUTO_REFRESH = TRUE NOTIFICATION_INTEGRATION = 'GCP_EV_PUBSUB_INT');

-- Raw data table (immutable audit trail)
CREATE OR REPLACE TABLE RAW_EV_DATA (
    JSON_DATA VARIANT,
    SOURCE_FILE VARCHAR,
    SOURCE_FILE_ROW NUMBER,
    LOAD_TIMESTAMP TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
ALTER TABLE RAW_EV_DATA SET CHANGE_TRACKING = TRUE;

-- Directory stream (detects new files in GCS)
CREATE OR REPLACE STREAM GCS_FILES_STREAM
  ON STAGE GCP_EV_STAGE;

-- Ingestion Stored Procedure (Snowpark Python)
CREATE OR REPLACE PROCEDURE SP_INGEST_RAW_EV_DATA()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
def main(session):
    try:
        result = session.sql("""
            COPY INTO EV_PROJECT_DB.BRONZE.RAW_EV_DATA (JSON_DATA)
            FROM @EV_PROJECT_DB.BRONZE.GCP_EV_STAGE
            FILE_FORMAT = (FORMAT_NAME = 'EV_PROJECT_DB.BRONZE.JSON_FORMAT')
            PURGE = TRUE
            ON_ERROR = 'ABORT_STATEMENT'
        """).collect()

        rows_loaded = sum(row['rows_loaded'] for row in result) if result else 0
        files_loaded = len(result) if result else 0

        return f"SUCCESS: {files_loaded} file(s) loaded, {rows_loaded} total row(s) ingested."

    except Exception as e:
        return f"FAILURE: {str(e)}"
$$;

-- Task DAG: Root task — stream-triggered ingestion
CREATE OR REPLACE TASK TSK_INGEST_EV_DATA
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('EV_PROJECT_DB.BRONZE.GCS_FILES_STREAM')
AS
  CALL EV_PROJECT_DB.BRONZE.SP_INGEST_RAW_EV_DATA();

-- Task DAG: Chained — error detection (fires after ingestion)
CREATE OR REPLACE TASK TSK_ERROR_DETECTION
  WAREHOUSE = COMPUTE_WH
  AFTER EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA
AS
  CALL EV_PROJECT_DB.DATA_QUALITY.SP_DETECT_ERRORS();

-- Task DAG: Chained — error notification (fires after detection)
CREATE OR REPLACE TASK TSK_ERROR_NOTIFICATION
  WAREHOUSE = COMPUTE_WH
  AFTER EV_PROJECT_DB.BRONZE.TSK_ERROR_DETECTION
AS
  CALL EV_PROJECT_DB.DATA_QUALITY.SP_NOTIFY_ERRORS();
