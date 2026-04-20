-- ============================================================
-- 05_DATA_QUALITY.sql
-- Comprehensive DQ: Snowpark Python validation SP, error
-- quarantine, duplicate tracking, monitoring views, alerting
-- ============================================================

USE SCHEMA EV_PROJECT_DB.DATA_QUALITY;

-- Error quarantine table
CREATE OR REPLACE TABLE ERROR_ROWS (
    ERROR_ID NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1 NOORDER,
    DETECTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    SOURCE_LAYER VARCHAR,
    SOURCE_TABLE VARCHAR,
    ERROR_TYPE VARCHAR,
    ERROR_DESCRIPTION VARCHAR,
    VIN VARCHAR,
    MAKE VARCHAR,
    MODEL VARCHAR,
    MODEL_YEAR NUMBER(38,0),
    EV_TYPE VARCHAR,
    ELECTRIC_RANGE NUMBER(38,0),
    BASE_MSRP FLOAT,
    DOL_VEHICLE_ID VARCHAR,
    SOURCE_FILE VARCHAR,
    RAW_RECORD VARIANT
);
ALTER TABLE ERROR_ROWS SET CHANGE_TRACKING = TRUE;

-- Duplicate tracking table
CREATE OR REPLACE TABLE DUPLICATE_ROWS (
    DUPLICATE_ID NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1 NOORDER,
    DETECTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    VIN VARCHAR,
    OCCURRENCE_COUNT NUMBER(38,0),
    MAKE VARCHAR,
    MODEL VARCHAR,
    SOURCE_FILES ARRAY
);
ALTER TABLE DUPLICATE_ROWS SET CHANGE_TRACKING = TRUE;

-- Streams for alerting
CREATE OR REPLACE STREAM ERROR_ROWS_STREAM ON TABLE ERROR_ROWS;
CREATE OR REPLACE STREAM DUPLICATE_ROWS_STREAM ON TABLE DUPLICATE_ROWS;

-- ============================================================
-- Snowpark Python DQ Procedure — 5 validation types:
-- 1. NULL_VIN (completeness)
-- 2. INVALID_RANGE (business rules)
-- 3. ORPHAN_MAKE (referential integrity)
-- 4. Duplicate VINs (uniqueness)
-- 5. NULL_CRITICAL_FIELD (completeness)
-- + Cross-layer reconciliation
-- ============================================================
CREATE OR REPLACE PROCEDURE SP_DETECT_ERRORS()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
def main(session):
    from snowflake.snowpark.functions import col, count, lit, current_timestamp, array_unique_agg, max as max_
    results = []

    silver = session.table("EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT")
    dim_mfg = session.table("EV_PROJECT_DB.GOLD.DIM_MANUFACTURERS_GOLD")

    flattened = session.sql("""
        SELECT f.value[8]::VARCHAR AS VIN, f.value[14]::VARCHAR AS MAKE,
               f.value[15]::VARCHAR AS MODEL, f.value[13]::INT AS MODEL_YEAR,
               f.value[16]::VARCHAR AS EV_TYPE, f.value[18]::INT AS ELECTRIC_RANGE,
               f.value[19]::FLOAT AS BASE_MSRP, SOURCE_FILE
        FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA, LATERAL FLATTEN(input => JSON_DATA:data) f
        WHERE f.value[8] IS NOT NULL
    """)

    dupes = flattened.group_by("VIN").agg(
        count("*").alias("OCCURRENCE_COUNT"),
        max_("MAKE").alias("MAKE"),
        max_("MODEL").alias("MODEL"),
        array_unique_agg("SOURCE_FILE").alias("SOURCE_FILES")
    ).filter(col("OCCURRENCE_COUNT") > 1)

    existing_dupes = session.table("EV_PROJECT_DB.DATA_QUALITY.DUPLICATE_ROWS").select(col("VIN"))
    new_dupes = dupes.join(existing_dupes, "VIN", "left_anti")
    dup_count = new_dupes.count()
    if dup_count > 0:
        new_dupes.select("VIN","OCCURRENCE_COUNT","MAKE","MODEL","SOURCE_FILES").write.mode("append").save_as_table("EV_PROJECT_DB.DATA_QUALITY.DUPLICATE_ROWS")
    results.append(f"Duplicates: {dup_count} new")

    def build_error_df(src_df, layer, table, etype, edesc, vin_col="VIN"):
        return src_df.select(
            lit(layer).alias("SOURCE_LAYER"), lit(table).alias("SOURCE_TABLE"),
            lit(etype).alias("ERROR_TYPE"), lit(edesc).alias("ERROR_DESCRIPTION"),
            col(vin_col).alias("VIN"), col("MAKE"), col("MODEL"),
            col("MODEL_YEAR").cast("int").alias("MODEL_YEAR"),
            col("EV_TYPE"),
            col("ELECTRIC_RANGE").cast("int").alias("ELECTRIC_RANGE"),
            col("BASE_MSRP").cast("float").alias("BASE_MSRP"),
            lit(None).cast("string").alias("DOL_VEHICLE_ID"),
            col("SOURCE_FILE"), lit(None).cast("variant").alias("RAW_RECORD")
        )

    null_vins = session.sql("""
        SELECT 'BRONZE' AS SOURCE_LAYER, 'RAW_EV_DATA' AS SOURCE_TABLE,
               'NULL_VIN' AS ERROR_TYPE, 'VIN is null' AS ERROR_DESCRIPTION,
               NULL AS VIN, f.value[14]::VARCHAR AS MAKE, f.value[15]::VARCHAR AS MODEL,
               f.value[13]::INT AS MODEL_YEAR, f.value[16]::VARCHAR AS EV_TYPE,
               f.value[18]::INT AS ELECTRIC_RANGE, f.value[19]::FLOAT AS BASE_MSRP,
               NULL AS DOL_VEHICLE_ID, SOURCE_FILE, f.value::VARIANT AS RAW_RECORD
        FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA, LATERAL FLATTEN(input => JSON_DATA:data) f
        WHERE f.value[8] IS NULL
    """)

    invalid_range = build_error_df(
        silver.filter((col("ELECTRIC_RANGE") < 0) | (col("ELECTRIC_RANGE") > 500)),
        "SILVER", "CLEAN_EV_DATA_DT", "INVALID_RANGE", "Electric range out of valid bounds (0-500)"
    )

    valid_makes = dim_mfg.select(col("MANUFACTURER_NAME"))
    orphan_rows = silver.join(valid_makes, silver["MAKE"] == valid_makes["MANUFACTURER_NAME"], "left_anti")
    orphan_errors = build_error_df(
        orphan_rows, "SILVER", "CLEAN_EV_DATA_DT", "ORPHAN_MAKE", "Make not in DIM_MANUFACTURERS_GOLD"
    )

    null_critical = build_error_df(
        silver.filter(col("MAKE").is_null() | col("MODEL").is_null() | col("MODEL_YEAR").is_null()),
        "SILVER", "CLEAN_EV_DATA_DT", "NULL_CRITICAL_FIELD", "Critical field is null"
    )

    all_errors = null_vins.union_all(invalid_range).union_all(orphan_errors).union_all(null_critical)
    err_count = all_errors.count()
    if err_count > 0:
        session.sql(f"""
            INSERT INTO EV_PROJECT_DB.DATA_QUALITY.ERROR_ROWS
            (SOURCE_LAYER, SOURCE_TABLE, ERROR_TYPE, ERROR_DESCRIPTION, VIN, MAKE, MODEL,
             MODEL_YEAR, EV_TYPE, ELECTRIC_RANGE, BASE_MSRP, DOL_VEHICLE_ID, SOURCE_FILE, RAW_RECORD)
            SELECT SOURCE_LAYER, SOURCE_TABLE, ERROR_TYPE, ERROR_DESCRIPTION, VIN, MAKE, MODEL,
                   MODEL_YEAR, EV_TYPE, ELECTRIC_RANGE, BASE_MSRP, DOL_VEHICLE_ID, SOURCE_FILE, RAW_RECORD
            FROM ({all_errors.queries['queries'][-1]})
        """).collect()
    results.append(f"Errors: {err_count} detected")

    bronze_cnt = session.sql("""
        SELECT COUNT(DISTINCT f.value[8]::VARCHAR) AS C
        FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA, LATERAL FLATTEN(input => JSON_DATA:data) f
        WHERE f.value[8] IS NOT NULL
    """).collect()[0]["C"]
    silver_cnt = silver.count()
    gold_cnt = session.sql("SELECT SUM(TOTAL_VEHICLES) AS C FROM EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS").collect()[0]["C"]
    results.append(f"Reconciliation: Bronze(unique)={bronze_cnt}, Silver={silver_cnt}, Gold(sum)={gold_cnt}")

    return " | ".join(results)
$$;

-- Email notification SP
CREATE OR REPLACE PROCEDURE SP_NOTIFY_ERRORS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    new_errors NUMBER;
    new_dupes NUMBER;
    email_body VARCHAR;
BEGIN
    SELECT COUNT(*) INTO :new_errors
    FROM EV_PROJECT_DB.DATA_QUALITY.ERROR_ROWS_STREAM
    WHERE METADATA$ACTION = 'INSERT';

    SELECT COUNT(*) INTO :new_dupes
    FROM EV_PROJECT_DB.DATA_QUALITY.DUPLICATE_ROWS_STREAM
    WHERE METADATA$ACTION = 'INSERT';

    IF (:new_errors > 0 OR :new_dupes > 0) THEN
        email_body := 'EV Pipeline Data Quality Alert' || CHR(10) || CHR(10)
            || 'New error rows detected: ' || :new_errors || CHR(10)
            || 'New duplicate VINs detected: ' || :new_dupes || CHR(10) || CHR(10)
            || 'Check EV_PROJECT_DB.DATA_QUALITY.V_DQ_DASHBOARD for details.';

        CALL SYSTEM$SEND_EMAIL(
            'EV_DQ_EMAIL_INT',
            'jaxdamon@example.com',
            'EV Pipeline DQ Alert',
            :email_body
        );
        RETURN 'ALERT SENT: ' || :new_errors || ' errors, ' || :new_dupes || ' dupes';
    ELSE
        RETURN 'NO NEW ISSUES';
    END IF;
END;
$$;

-- ============================================================
-- Monitoring Views
-- ============================================================

-- Error summary by type
CREATE OR REPLACE VIEW V_ERROR_SUMMARY AS
SELECT
  ERROR_TYPE, SOURCE_LAYER, SOURCE_TABLE,
  COUNT(*) AS error_count,
  MIN(DETECTED_AT) AS first_seen,
  MAX(DETECTED_AT) AS last_seen
FROM EV_PROJECT_DB.DATA_QUALITY.ERROR_ROWS
GROUP BY ERROR_TYPE, SOURCE_LAYER, SOURCE_TABLE
ORDER BY error_count DESC;

-- Hourly error trend
CREATE OR REPLACE VIEW V_ERROR_TREND AS
SELECT
    DATE_TRUNC('hour', DETECTED_AT) AS HOUR,
    ERROR_TYPE, SOURCE_LAYER,
    COUNT(*) AS ERROR_COUNT
FROM EV_PROJECT_DB.DATA_QUALITY.ERROR_ROWS
GROUP BY DATE_TRUNC('hour', DETECTED_AT), ERROR_TYPE, SOURCE_LAYER;

-- Top offending manufacturers
CREATE OR REPLACE VIEW V_TOP_OFFENDERS AS
SELECT
    MAKE,
    COUNT(*) AS TOTAL_ERRORS,
    COUNT(DISTINCT ERROR_TYPE) AS DISTINCT_ERROR_TYPES,
    ARRAY_UNIQUE_AGG(ERROR_TYPE) AS ERROR_TYPES,
    COUNT(CASE WHEN ERROR_TYPE = 'INVALID_RANGE' THEN 1 END) AS INVALID_RANGE_COUNT,
    COUNT(CASE WHEN ERROR_TYPE = 'ORPHAN_MAKE' THEN 1 END) AS ORPHAN_MAKE_COUNT,
    COUNT(CASE WHEN ERROR_TYPE = 'NULL_CRITICAL_FIELD' THEN 1 END) AS NULL_FIELD_COUNT
FROM EV_PROJECT_DB.DATA_QUALITY.ERROR_ROWS
WHERE MAKE IS NOT NULL
GROUP BY MAKE
ORDER BY TOTAL_ERRORS DESC;

-- Data lineage from ACCESS_HISTORY
CREATE OR REPLACE VIEW V_PIPELINE_LINEAGE AS
SELECT
  DIRECTSOURCES.VALUE:"objectDomain"::STRING  AS SOURCE_TYPE,
  DIRECTSOURCES.VALUE:"objectName"::STRING     AS SOURCE_OBJECT,
  OBJECTS_MODIFIED.VALUE:"objectDomain"::STRING AS TARGET_TYPE,
  OBJECTS_MODIFIED.VALUE:"objectName"::STRING   AS TARGET_OBJECT,
  OBJECTS_MODIFIED.VALUE:"columns"              AS COLUMNS_MODIFIED,
  AH.USER_NAME, AH.QUERY_ID, AH.QUERY_START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY AH,
  LATERAL FLATTEN(input => AH.OBJECTS_MODIFIED) OBJECTS_MODIFIED,
  LATERAL FLATTEN(input => OBJECTS_MODIFIED.VALUE:"directSources") DIRECTSOURCES
WHERE OBJECTS_MODIFIED.VALUE:"objectDomain"::STRING IN ('Table', 'Dynamic Table')
  AND (
    OBJECTS_MODIFIED.VALUE:"objectName"::STRING ILIKE '%EV_PROJECT_DB%'
    OR DIRECTSOURCES.VALUE:"objectName"::STRING ILIKE '%EV_PROJECT_DB%'
  )
  AND AH.QUERY_START_TIME >= DATEADD('day', -14, CURRENT_TIMESTAMP());

-- DMF monitoring results
CREATE OR REPLACE VIEW V_DMF_MONITORING_RESULTS AS
SELECT
  TABLE_DATABASE || '.' || TABLE_SCHEMA || '.' || TABLE_NAME AS FULL_TABLE_NAME,
  TABLE_NAME,
  METRIC_DATABASE || '.' || METRIC_SCHEMA || '.' || METRIC_NAME AS DMF_NAME,
  ARGUMENT_NAMES, VALUE AS METRIC_VALUE,
  SCHEDULED_TIME, CHANGE_COMMIT_TIME
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE TABLE_DATABASE = 'EV_PROJECT_DB';

-- Cross-layer row count reconciliation
CREATE OR REPLACE VIEW V_ROW_COUNT_RECONCILIATION AS
WITH bronze AS (
  SELECT COUNT(*) AS row_count FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA
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
  SELECT COUNT(*) AS row_count FROM EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT
),
gold AS (
  SELECT COUNT(*) AS group_count, SUM(TOTAL_VEHICLES) AS total_vehicles
  FROM EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS
)
SELECT
  b.row_count AS bronze_raw_rows,
  bf.row_count AS bronze_flattened_rows,
  bu.row_count AS bronze_unique_vins,
  bf.row_count - bu.row_count AS duplicates_removed,
  s.row_count AS silver_rows,
  s.row_count - bu.row_count AS bronze_to_silver_drift,
  g.group_count AS gold_groups,
  g.total_vehicles AS gold_total_vehicles,
  g.total_vehicles - s.row_count AS silver_to_gold_drift,
  CURRENT_TIMESTAMP() AS reconciliation_timestamp,
  CASE
    WHEN s.row_count - bu.row_count = 0 AND g.total_vehicles - s.row_count = 0 THEN 'PASS'
    ELSE 'DRIFT_DETECTED'
  END AS status
FROM bronze b, bronze_flattened bf, bronze_unique bu, silver s, gold g;

-- Data freshness monitoring
CREATE OR REPLACE VIEW V_DATA_FRESHNESS AS
WITH silver_refresh AS (
    SELECT NAME, DATA_TIMESTAMP,
        DATEDIFF('minute', DATA_TIMESTAMP, CURRENT_TIMESTAMP()) AS MINUTES_SINCE_REFRESH, STATE
    FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
        NAME => 'EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT'))
    WHERE STATE = 'SUCCEEDED'
    ORDER BY DATA_TIMESTAMP DESC LIMIT 1
),
gold_freshness AS (
    SELECT MAX(LOAD_TIMESTAMP) AS LAST_REFRESH,
        DATEDIFF('minute', MAX(LOAD_TIMESTAMP), CURRENT_TIMESTAMP()) AS MINUTES_SINCE_REFRESH
    FROM EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS
),
iceberg_freshness AS (
    SELECT TABLE_NAME, LAST_ALTERED,
        DATEDIFF('minute', LAST_ALTERED, CURRENT_TIMESTAMP()) AS MINUTES_SINCE_REFRESH
    FROM EV_PROJECT_DB.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'ICEBERG' AND TABLE_TYPE = 'BASE TABLE'
)
SELECT 'SILVER' AS LAYER, 'CLEAN_EV_DATA_DT' AS TABLE_NAME, sr.DATA_TIMESTAMP AS LAST_REFRESH,
    sr.MINUTES_SINCE_REFRESH,
    CASE WHEN sr.MINUTES_SINCE_REFRESH <= 5 THEN 'FRESH'
         WHEN sr.MINUTES_SINCE_REFRESH <= 60 THEN 'ACCEPTABLE' ELSE 'STALE' END AS FRESHNESS_STATUS
FROM silver_refresh sr
UNION ALL
SELECT 'GOLD', 'FACT_EV_MARKET_METRICS', gf.LAST_REFRESH, gf.MINUTES_SINCE_REFRESH,
    CASE WHEN gf.MINUTES_SINCE_REFRESH <= 15 THEN 'FRESH'
         WHEN gf.MINUTES_SINCE_REFRESH <= 120 THEN 'ACCEPTABLE' ELSE 'STALE' END
FROM gold_freshness gf
UNION ALL
SELECT 'ICEBERG', icf.TABLE_NAME, icf.LAST_ALTERED, icf.MINUTES_SINCE_REFRESH,
    CASE WHEN icf.MINUTES_SINCE_REFRESH <= 30 THEN 'FRESH'
         WHEN icf.MINUTES_SINCE_REFRESH <= 180 THEN 'ACCEPTABLE' ELSE 'STALE' END
FROM iceberg_freshness icf;

-- Combined DQ dashboard
CREATE OR REPLACE VIEW V_DQ_DASHBOARD AS
WITH error_summary AS (
    SELECT ERROR_TYPE, SOURCE_LAYER,
        COUNT(*) AS TOTAL_ERRORS,
        COUNT(CASE WHEN DETECTED_AT >= DATEADD('hour', -24, CURRENT_TIMESTAMP()) THEN 1 END) AS ERRORS_LAST_24H,
        COUNT(CASE WHEN DETECTED_AT >= DATEADD('hour', -1, CURRENT_TIMESTAMP()) THEN 1 END) AS ERRORS_LAST_1H,
        MIN(DETECTED_AT) AS FIRST_SEEN, MAX(DETECTED_AT) AS LAST_SEEN
    FROM EV_PROJECT_DB.DATA_QUALITY.ERROR_ROWS
    GROUP BY ERROR_TYPE, SOURCE_LAYER
),
duplicate_summary AS (
    SELECT COUNT(*) AS TOTAL_DUPLICATE_VINS,
        SUM(OCCURRENCE_COUNT) AS TOTAL_DUPLICATE_ROWS,
        COUNT(CASE WHEN DETECTED_AT >= DATEADD('hour', -24, CURRENT_TIMESTAMP()) THEN 1 END) AS DUPES_LAST_24H
    FROM EV_PROJECT_DB.DATA_QUALITY.DUPLICATE_ROWS
),
reconciliation AS (
    SELECT * FROM EV_PROJECT_DB.DATA_QUALITY.V_ROW_COUNT_RECONCILIATION
)
SELECT
    'ERROR_SUMMARY' AS SECTION,
    e.SOURCE_LAYER, e.ERROR_TYPE, e.TOTAL_ERRORS, e.ERRORS_LAST_24H, e.ERRORS_LAST_1H,
    e.FIRST_SEEN, e.LAST_SEEN,
    d.TOTAL_DUPLICATE_VINS, d.TOTAL_DUPLICATE_ROWS, d.DUPES_LAST_24H,
    r.BRONZE_RAW_ROWS, r.SILVER_ROWS, r.GOLD_TOTAL_VEHICLES,
    r.BRONZE_TO_SILVER_DRIFT, r.SILVER_TO_GOLD_DRIFT, r.STATUS AS RECONCILIATION_STATUS
FROM error_summary e
CROSS JOIN duplicate_summary d
CROSS JOIN reconciliation r;
