-- ============================================================
-- 04_GOLD.sql
-- Business-ready layer: Snowpark Python SP, tables,
-- stream-triggered task, dimension table
-- ============================================================

USE SCHEMA EV_PROJECT_DB.GOLD;

-- Fact table — individual registrations
CREATE OR REPLACE TABLE FACT_EV_REGISTRATIONS (
    VIN VARCHAR,
    MAKE VARCHAR,
    MODEL VARCHAR,
    MODEL_YEAR NUMBER(38,0),
    EV_TYPE VARCHAR,
    CAFV_ELIGIBILITY VARCHAR,
    ELECTRIC_RANGE NUMBER(38,0),
    BASE_MSRP FLOAT,
    CITY VARCHAR,
    COUNTY VARCHAR,
    STATE VARCHAR,
    ZIP_CODE VARCHAR,
    LEGISLATIVE_DISTRICT VARCHAR,
    DOL_VEHICLE_ID VARCHAR,
    VEHICLE_LOCATION VARCHAR,
    ELECTRIC_UTILITY VARCHAR,
    CENSUS_TRACT_2020 VARCHAR,
    COUNTIES VARCHAR
);

-- Fact table — aggregated market metrics
CREATE OR REPLACE TABLE FACT_EV_MARKET_METRICS (
    MAKE VARCHAR,
    EV_TYPE VARCHAR,
    TOTAL_VEHICLES NUMBER(10,0),
    AVG_RANGE FLOAT,
    MAX_MSRP FLOAT,
    LOAD_TIMESTAMP TIMESTAMP_LTZ
);

-- Dimension table (replicated from PostgreSQL)
CREATE OR REPLACE TABLE DIM_MANUFACTURERS_GOLD (
    MANUFACTURER_ID NUMBER(38,0),
    MANUFACTURER_NAME VARCHAR,
    COUNTRY VARCHAR
);

-- Snowpark Python transformation SP
CREATE OR REPLACE PROCEDURE SP_TRANSFORM_SILVER_TO_GOLD()
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

-- Stream-triggered task for Silver → Gold
CREATE OR REPLACE TASK TASK_SILVER_TO_GOLD
  WAREHOUSE = COMPUTE_WH
  WHEN SYSTEM$STREAM_HAS_DATA('EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT_STREAM')
AS
  CALL EV_PROJECT_DB.GOLD.SP_TRANSFORM_SILVER_TO_GOLD();

-- Internal stage for semantic model + Streamlit files
CREATE OR REPLACE STAGE SEMANTIC_MODELS;
