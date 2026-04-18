-- ============================================================
-- 04_SERVING_GOLD: Schema, Audit Table, and Iceberg Metrics
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- 1. Create the GOLD schema
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.GOLD;

-- 2. Pipeline observability / audit table
CREATE OR REPLACE TABLE EV_PROJECT_DB.GOLD.PIPELINE_AUDIT (
  RUN_ID          VARCHAR DEFAULT UUID_STRING(),
  FILE_NAME       VARCHAR,
  LAYER           VARCHAR,
  START_TIME      TIMESTAMP_LTZ,
  END_TIME        TIMESTAMP_LTZ,
  ROWS_PROCESSED  INT,
  STATUS          VARCHAR,
  ERROR_MESSAGE   VARCHAR,
  QUERY_ID        VARCHAR,
  CREDITS_USED    FLOAT,
  EXECUTED_BY     VARCHAR DEFAULT CURRENT_USER()
);

-- 3. Iceberg fact table for EV market metrics (Snowflake-managed catalog)
CREATE OR REPLACE ICEBERG TABLE EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS (
  MAKE                VARCHAR,
  TOTAL_VEHICLES      INT,
  AVG_ELECTRIC_RANGE  FLOAT,
  MAX_MSRP            FLOAT,
  LOAD_TIMESTAMP      TIMESTAMP_LTZ
)
  CATALOG         = 'SNOWFLAKE'
  EXTERNAL_VOLUME = 'GCP_ICEBERG_VOLUME'
  BASE_LOCATION   = 'fact_ev_metrics/';