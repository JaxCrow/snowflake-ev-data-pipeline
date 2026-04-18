-- ============================================================
-- Silver Layer: Schema, Table, and Transformation Procedure
-- ============================================================

-- 1. Create the SILVER schema
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.SILVER;

-- 2. Create the CLEAN_EV_DATA table
CREATE OR REPLACE TABLE EV_PROJECT_DB.SILVER.CLEAN_EV_DATA (
  VIN              VARCHAR,
  MAKE             VARCHAR,
  MODEL            VARCHAR,
  MODEL_YEAR       INT,
  ELECTRIC_RANGE   INT,
  BASE_MSRP        FLOAT,
  LOAD_TIMESTAMP   TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 3. Stored Procedure: Transform Bronze → Silver using Snowpark DataFrame API
CREATE OR REPLACE PROCEDURE EV_PROJECT_DB.SILVER.SP_TRANSFORM_BRONZE_TO_SILVER()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
def main(session):
    from snowflake.snowpark.functions import col, current_timestamp
    from snowflake.snowpark.types import StringType, IntegerType, FloatType

    try:
        df_raw = session.table("EV_PROJECT_DB.BRONZE.RAW_EV_DATA")

        df_clean = df_raw.select(
            col("RAW_DOCUMENT")["VIN"].cast(StringType()).alias("VIN"),
            col("RAW_DOCUMENT")["Make"].cast(StringType()).alias("MAKE"),
            col("RAW_DOCUMENT")["Model"].cast(StringType()).alias("MODEL"),
            col("RAW_DOCUMENT")["Model Year"].cast(IntegerType()).alias("MODEL_YEAR"),
            col("RAW_DOCUMENT")["Electric Range"].cast(IntegerType()).alias("ELECTRIC_RANGE"),
            col("RAW_DOCUMENT")["Base MSRP"].cast(FloatType()).alias("BASE_MSRP"),
            current_timestamp().alias("LOAD_TIMESTAMP")
        ).filter(col("VIN").is_not_null())

        row_count = df_clean.count()

        df_clean.write.mode("append").save_as_table("EV_PROJECT_DB.SILVER.CLEAN_EV_DATA")

        return f"SUCCESS: {row_count} rows transformed and loaded into SILVER.CLEAN_EV_DATA."

    except Exception as e:
        return f"FAILURE: {str(e)}"
$$;
