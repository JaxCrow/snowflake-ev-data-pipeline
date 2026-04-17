-- ============================================================
-- Bronze Layer: Snowpark Event-Driven Ingestion Procedure
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE EV_PROJECT_DB;
USE SCHEMA BRONZE;

CREATE OR REPLACE PROCEDURE SP_INGEST_RAW_EV_DATA()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
def main(session):
    """
    ========================================================================
    ARCHITECTURE NOTE: EVENT-DRIVEN INGESTION & GCP ARCHIVING
    ------------------------------------------------------------------------
    1. INGESTION: This procedure loads JSON data from the GCP external stage.
    2. PURGE: Snowflake's PURGE=TRUE removes the file from the /landing zone 
       after a successful load to prevent duplicate processing.
    3. ARCHIVING: Since Snowflake cannot execute native 'MOVE' commands 
       across GCP storage buckets, archiving must be handled natively in GCP.
       Recommended approach: Configure a GCP Cloud Storage Lifecycle Rule 
       or a lightweight GCP Cloud Function (triggered by object finalization) 
       to copy the file from /landing to /archive BEFORE Snowflake consumes it.
    ========================================================================
    """
    try:
        # Execute the COPY INTO command
        result = session.sql("""
            COPY INTO EV_PROJECT_DB.BRONZE.RAW_EV_DATA (RAW_DOCUMENT)
            FROM @EV_PROJECT_DB.BRONZE.GCP_EV_STAGE
            FILE_FORMAT = (FORMAT_NAME = 'EV_PROJECT_DB.BRONZE.JSON_FORMAT')
            PURGE = TRUE
            ON_ERROR = 'ABORT_STATEMENT'
        """).collect()

        rows_loaded = sum(row['rows_loaded'] for row in result) if result else 0
        files_loaded = len(result) if result else 0

        return f"SUCCESS: {files_loaded} file(s) loaded, {rows_loaded} total row(s) ingested."

    except Exception as e:
        # Return the error string so the calling Task can capture it in the Task History
        return f"FAILURE: Ingestion aborted. Details: {str(e)}"
$$;