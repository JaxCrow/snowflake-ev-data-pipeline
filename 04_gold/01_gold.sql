-- ============================================================
-- 04_GOLD.sql
-- Business-ready layer: Snowpark Python SP, tables,
-- stream-triggered task, dimension table
-- ============================================================

USE SCHEMA EV_PROJECT_DB.GOLD;

-- Fact table — individual registrations
CREATE OR REPLACE TABLE FACT_EV_REGISTRATIONS (
    VIN VARCHAR,
    COUNTY_NAME VARCHAR,
    MAKE VARCHAR,
    MODEL VARCHAR,
    MODEL_YEAR NUMBER(38,0),
    EV_TYPE VARCHAR,
    ELECTRIC_RANGE NUMBER(38,0),
    BASE_MSRP FLOAT,
    LEGISLATIVE_DISTRICT VARCHAR,
    DOL_VEHICLE_ID VARCHAR,
    VEHICLE_LOCATION VARCHAR,
    ELECTRIC_UTILITY VARCHAR,
    CENSUS_TRACT_2020 VARCHAR,
    COUNTIES VARCHAR,
    SOURCE_FILE VARCHAR,
    LOAD_TIMESTAMP TIMESTAMP_LTZ
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

-- Dimension table for county lookup and friendly naming
CREATE OR REPLACE TABLE DIM_COUNTY_GOLD (
    COUNTY_ID NUMBER(38,0),
    COUNTY_CODE VARCHAR,
    COUNTY_NAME VARCHAR
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
    from snowflake.snowpark.functions import col, count, avg, max as max_, current_timestamp, row_number
    from snowflake.snowpark.window import Window
    try:
        df_silver = session.table("EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT")

        # Gold detail fact: one row per registration (desagrupado)
        df_detail = df_silver.select(
            col("VIN"),
            col("COUNTY_NAME"),
            col("MAKE"),
            col("MODEL"),
            col("MODEL_YEAR"),
            col("EV_TYPE"),
            col("ELECTRIC_RANGE"),
            col("BASE_MSRP"),
            col("LEGISLATIVE_DISTRICT"),
            col("DOL_VEHICLE_ID"),
            col("VEHICLE_LOCATION"),
            col("ELECTRIC_UTILITY"),
            col("CENSUS_TRACT_2020"),
            col("COUNTIES"),
            col("SOURCE_FILE")
        ).with_column("LOAD_TIMESTAMP", current_timestamp())

        session.sql("TRUNCATE TABLE EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS").collect()
        df_detail.write.mode("append").save_as_table("EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS")

        session.sql("TRUNCATE TABLE EV_PROJECT_DB.GOLD.DIM_COUNTY_GOLD").collect()
        county_lookup = df_detail.select(
            col("COUNTIES").alias("COUNTY_CODE"),
            col("COUNTY_NAME")
        ).distinct()
        county_lookup = county_lookup.select(
            row_number().over(Window.order_by(col("COUNTY_NAME"), col("COUNTY_CODE"))).alias("COUNTY_ID"),
            col("COUNTY_CODE"),
            col("COUNTY_NAME")
        ).sort(col("COUNTY_ID"))
        county_lookup.write.mode("append").save_as_table("EV_PROJECT_DB.GOLD.DIM_COUNTY_GOLD")

        # Gold aggregate fact: summary metrics for analytics
        df_gold = df_detail.group_by("MAKE", "EV_TYPE").agg(
            count("VIN").alias("TOTAL_VEHICLES"),
            avg("ELECTRIC_RANGE").alias("AVG_RANGE"),
            max_("BASE_MSRP").alias("MAX_MSRP")
        ).with_column("LOAD_TIMESTAMP", current_timestamp())

        session.sql("TRUNCATE TABLE EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS").collect()
        df_gold.write.mode("append").save_as_table("EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS")

        detail_count = session.table("EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS").count()
        metric_count = session.table("EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS").count()
        county_count = session.table("EV_PROJECT_DB.GOLD.DIM_COUNTY_GOLD").count()
        return f"SUCCESS: FACT_EV_REGISTRATIONS={detail_count}, FACT_EV_MARKET_METRICS={metric_count}, DIM_COUNTY_GOLD={county_count}"
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
