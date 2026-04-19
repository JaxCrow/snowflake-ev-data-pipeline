-- ============================================================
-- GOLD SCHEMA
-- ============================================================

-- 9. Table: Manufacturer dimension (fed by Snowflake Connector for PostgreSQL / NeonDB)
CREATE OR REPLACE TABLE EV_PROJECT_DB.GOLD.DIM_MANUFACTURERS_GOLD (
    MANUFACTURER_ID NUMBER(38,0),
    MANUFACTURER_NAME VARCHAR(16777216),
    COUNTRY VARCHAR(16777216)
);

-- 10. Iceberg Table: Aggregated EV market metrics
CREATE OR REPLACE ICEBERG TABLE EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS (
    MAKE STRING,
    EV_TYPE STRING,
    TOTAL_VEHICLES INT,
    AVG_RANGE FLOAT,
    MAX_MSRP FLOAT,
    LOAD_TIMESTAMP TIMESTAMP_LTZ(6)
)
  EXTERNAL_VOLUME = 'GCP_ICEBERG_VOLUME'
  ICEBERG_VERSION = 2
  CATALOG = 'SNOWFLAKE'
  BASE_LOCATION = 'gold/fact_ev_market_metrics/';

-- 11. Stored Procedure: Aggregates silver DT data into gold iceberg table
CREATE OR REPLACE PROCEDURE EV_PROJECT_DB.GOLD.SP_TRANSFORM_SILVER_TO_GOLD()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
def main(session):
    from snowflake.snowpark.functions import col, count, avg, max as max_, current_timestamp
    try:
        df_silver = session.table("EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT")
        df_gold = df_silver.group_by("MAKE", "EV_TYPE").agg(
            count("VIN").alias("TOTAL_VEHICLES"),
            avg("ELECTRIC_RANGE").alias("AVG_RANGE"),
            max_("BASE_MSRP").alias("MAX_MSRP")
        ).with_column("LOAD_TIMESTAMP", current_timestamp())

        session.sql("TRUNCATE TABLE EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS").collect()
        df_gold.write.mode("append").save_as_table("EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS")
        return "SUCCESS"
    except Exception as e:
        return str(e)
$$;

-- 12. Task: Fires SP when stream detects new data in the DT
CREATE OR REPLACE TASK EV_PROJECT_DB.GOLD.TASK_SILVER_TO_GOLD
  WAREHOUSE = COMPUTE_WH
  WHEN SYSTEM$STREAM_HAS_DATA('EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT_STREAM')
AS
  CALL EV_PROJECT_DB.GOLD.SP_TRANSFORM_SILVER_TO_GOLD();

ALTER TASK EV_PROJECT_DB.GOLD.TASK_SILVER_TO_GOLD RESUME;