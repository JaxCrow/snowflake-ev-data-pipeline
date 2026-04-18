-- ============================================================
-- Silver Layer: Child Task (DAG) for Bronze → Silver Transform
-- ============================================================
--
-- IMPORTANT: Snowflake requires all tasks in a DAG to reside in
-- the SAME database and schema as the root task. Since the root
-- task TSK_INGEST_EV_DATA lives in EV_PROJECT_DB.BRONZE, this
-- child task must also be created there.
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE EV_PROJECT_DB;
USE SCHEMA BRONZE;

-- 1. Create the child task (runs AFTER the bronze ingestion completes)
CREATE OR REPLACE TASK EV_PROJECT_DB.BRONZE.TSK_TRANSFORM_SILVER_DATA
  WAREHOUSE = COMPUTE_WH                       -- ← replace with your warehouse if different
  AFTER EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA
AS
  CALL EV_PROJECT_DB.SILVER.SP_TRANSFORM_BRONZE_TO_SILVER();

-- 2. Resume the child task.
--    Child tasks MUST be resumed BEFORE the root task is resumed.
--    Tasks are created in a SUSPENDED state by default.
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_TRANSFORM_SILVER_DATA RESUME;

-- 3. (Optional) Resume the root task to activate the entire DAG.
--    Uncomment ONLY after verifying all child tasks are resumed.
-- ALTER TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA RESUME;