-- ============================================================
-- BRONZE SCHEMA
-- ============================================================

-- 1. External Stage: GCS landing zone for raw EV data files
CREATE OR REPLACE STAGE EV_PROJECT_DB.BRONZE.GCP_EV_STAGE
  URL = 'gcs://ev-landing-zone-lordrivas/landing/'
  STORAGE_INTEGRATION = GCP_EV_STORAGE_INT
  DIRECTORY = (ENABLE = TRUE);

-- 2. Table: Raw JSON data ingested from GCS
CREATE OR REPLACE TABLE EV_PROJECT_DB.BRONZE.RAW_EV_DATA (
    JSON_DATA VARIANT,
    SOURCE_FILE VARCHAR(16777216),
    SOURCE_FILE_ROW NUMBER(38,0),
    LOAD_TIMESTAMP TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP()
);



-- 4. Stream: Detects new files arriving in the GCS stage
CREATE OR REPLACE STREAM EV_PROJECT_DB.BRONZE.GCS_FILES_STREAM
  ON DIRECTORY(@EV_PROJECT_DB.BRONZE.GCP_EV_STAGE);

-- 5. Stored Procedure: Loads new files from GCS into RAW_EV_DATA
CREATE OR REPLACE PROCEDURE EV_PROJECT_DB.BRONZE.SP_INGEST_RAW_EV_DATA()
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

-- 6. Task: Runs every 1 min; fires SP when stage stream has new files
CREATE OR REPLACE TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('EV_PROJECT_DB.BRONZE.GCS_FILES_STREAM')
AS
  CALL EV_PROJECT_DB.BRONZE.SP_INGEST_RAW_EV_DATA();

ALTER TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA RESUME;