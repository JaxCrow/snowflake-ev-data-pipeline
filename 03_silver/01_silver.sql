-- ============================================================
-- 03_SILVER.sql
-- Cleansed + deduplicated layer: Dynamic Table with
-- INCREMENTAL refresh, stream for Gold trigger
-- ============================================================

USE SCHEMA EV_PROJECT_DB.SILVER;

-- Dynamic Table — JSON flatten, type cast, null rejection, dedup
CREATE OR REPLACE DYNAMIC TABLE CLEAN_EV_DATA_DT
  TARGET_LAG = '1 minute'
  REFRESH_MODE = INCREMENTAL
  INITIALIZE = ON_CREATE
  WAREHOUSE = COMPUTE_WH
AS
  SELECT
    f.value[8]::VARCHAR   AS VIN,
    f.value[14]::VARCHAR  AS MAKE,
    f.value[15]::VARCHAR  AS MODEL,
    f.value[13]::INT      AS MODEL_YEAR,
    f.value[16]::VARCHAR  AS EV_TYPE,
    f.value[18]::INT      AS ELECTRIC_RANGE,
    f.value[19]::FLOAT    AS BASE_MSRP,
    f.value[20]::VARCHAR  AS LEGISLATIVE_DISTRICT,
    f.value[21]::VARCHAR  AS DOL_VEHICLE_ID,
    f.value[22]::VARCHAR  AS VEHICLE_LOCATION,
    f.value[23]::VARCHAR  AS ELECTRIC_UTILITY,
    f.value[24]::VARCHAR  AS CENSUS_TRACT_2020,
    f.value[25]::VARCHAR  AS COUNTIES,
    SOURCE_FILE
  FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA,
    LATERAL FLATTEN(input => JSON_DATA:data) f
  WHERE f.value[8] IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.value[8]::VARCHAR ORDER BY SOURCE_FILE DESC) = 1;

-- Stream on Dynamic Table (triggers Gold transformation)
CREATE OR REPLACE STREAM CLEAN_EV_DATA_DT_STREAM
  ON DYNAMIC TABLE CLEAN_EV_DATA_DT;
