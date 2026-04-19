-- ============================================================
-- SILVER SCHEMA
-- ============================================================

-- 7. Dynamic Table (INCREMENTAL): Flattens JSON into structured columns
CREATE OR REPLACE DYNAMIC TABLE EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT
  TARGET_LAG = '1 MINUTE'
  WAREHOUSE  = COMPUTE_WH
  REFRESH_MODE = INCREMENTAL
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

-- 8. Stream: Captures new rows in the dynamic table to trigger gold refresh
CREATE OR REPLACE STREAM EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT_STREAM
  ON DYNAMIC TABLE EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT
  SHOW_INITIAL_ROWS = FALSE;