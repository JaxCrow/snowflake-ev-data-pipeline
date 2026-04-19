-- ================================================================
-- CROSS-LAYER VALIDATION — Custom DMFs
-- ================================================================

-- Row count drift: Silver vs Bronze (flattened). 0 = perfect match.
CREATE OR REPLACE DATA METRIC FUNCTION EV_PROJECT_DB.DATA_QUALITY.ROW_COUNT_DRIFT_SILVER_VS_BRONZE(
  arg_t TABLE(arg_c1 VARCHAR)
)
RETURNS NUMBER
COMMENT = 'Returns difference: silver row count minus flattened bronze row count. 0 = perfect reconciliation.'
AS
$$
  SELECT
    (SELECT COUNT(*) FROM EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT)
    -
    (SELECT COUNT(*) FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA, LATERAL FLATTEN(input => JSON_DATA:data) f WHERE f.value[8] IS NOT NULL)
$$;

-- Row count drift: Gold total vehicles vs Silver row count. 0 = perfect match.
CREATE OR REPLACE DATA METRIC FUNCTION EV_PROJECT_DB.DATA_QUALITY.GOLD_VEHICLE_COUNT_DRIFT(
  arg_t TABLE(arg_c1 NUMBER)
)
RETURNS NUMBER
COMMENT = 'Returns difference: sum of TOTAL_VEHICLES in gold minus silver row count. 0 = perfect reconciliation.'
AS
$$
  SELECT
    (SELECT COALESCE(SUM(arg_c1), 0) FROM arg_t)
    -
    (SELECT COUNT(*) FROM EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT)
$$;

-- Coverage: Count distinct MAKEs in silver NOT represented in gold.
CREATE OR REPLACE DATA METRIC FUNCTION EV_PROJECT_DB.DATA_QUALITY.GOLD_MAKE_COVERAGE(
  arg_t TABLE(arg_c1 VARCHAR)
)
RETURNS NUMBER
COMMENT = 'Returns count of distinct MAKEs in silver NOT represented in gold. 0 = full coverage.'
AS
$$
  SELECT COUNT(DISTINCT arg_c1) FROM arg_t
  WHERE arg_c1 NOT IN (SELECT DISTINCT MAKE FROM EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS)
$$;

-- Attach cross-layer DMFs
ALTER TABLE EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT
  ADD DATA METRIC FUNCTION EV_PROJECT_DB.DATA_QUALITY.ROW_COUNT_DRIFT_SILVER_VS_BRONZE ON (VIN);
ALTER TABLE EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT
  ADD DATA METRIC FUNCTION EV_PROJECT_DB.DATA_QUALITY.GOLD_MAKE_COVERAGE ON (MAKE);
ALTER TABLE EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS
  ADD DATA METRIC FUNCTION EV_PROJECT_DB.DATA_QUALITY.GOLD_VEHICLE_COUNT_DRIFT ON (TOTAL_VEHICLES);

-- ================================================================
-- CROSS-LAYER VALIDATION — Row Count Reconciliation View
-- (accounts for deduplication in silver)
-- ================================================================

CREATE OR REPLACE VIEW EV_PROJECT_DB.DATA_QUALITY.V_ROW_COUNT_RECONCILIATION AS
WITH bronze AS (
  SELECT COUNT(*) AS row_count
  FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA
),
bronze_flattened AS (
  SELECT COUNT(*) AS row_count
  FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA,
    LATERAL FLATTEN(input => JSON_DATA:data) f
  WHERE f.value[8] IS NOT NULL
),
bronze_unique AS (
  SELECT COUNT(DISTINCT f.value[8]::VARCHAR) AS row_count
  FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA,
    LATERAL FLATTEN(input => JSON_DATA:data) f
  WHERE f.value[8] IS NOT NULL
),
silver AS (
  SELECT COUNT(*) AS row_count
  FROM EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT
),
gold AS (
  SELECT
    COUNT(*) AS group_count,
    SUM(TOTAL_VEHICLES) AS total_vehicles
  FROM EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS
)
SELECT
  b.row_count                               AS bronze_raw_rows,
  bf.row_count                              AS bronze_flattened_rows,
  bu.row_count                              AS bronze_unique_vins,
  bf.row_count - bu.row_count               AS duplicates_removed,
  s.row_count                               AS silver_rows,
  bu.row_count - s.row_count                AS bronze_to_silver_drift,
  g.group_count                             AS gold_groups,
  g.total_vehicles                          AS gold_total_vehicles,
  g.total_vehicles - s.row_count            AS silver_to_gold_drift,
  CURRENT_TIMESTAMP()                       AS reconciliation_timestamp,
  CASE
    WHEN bu.row_count - s.row_count = 0 AND g.total_vehicles - s.row_count = 0
    THEN 'PASS'
    ELSE 'DRIFT_DETECTED'
  END                                       AS status
FROM bronze b, bronze_flattened bf, bronze_unique bu, silver s, gold g;