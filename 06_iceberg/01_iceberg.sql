-- ============================================================
-- 06_ICEBERG.sql
-- Open table format interoperability layer:
-- Snowflake-managed Iceberg tables on GCS external volume
-- ============================================================

USE SCHEMA EV_PROJECT_DB.ICEBERG;

-- Iceberg copy of Gold registrations (Parquet on GCS)
CREATE OR REPLACE ICEBERG TABLE FACT_EV_REGISTRATIONS
  EXTERNAL_VOLUME = 'GCP_ICEBERG_VOLUME'
  CATALOG = 'SNOWFLAKE'
  BASE_LOCATION = 'fact_ev_registrations'
  AS SELECT * FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS;

-- Iceberg copy of Gold market metrics
CREATE OR REPLACE ICEBERG TABLE FACT_EV_MARKET_METRICS
  EXTERNAL_VOLUME = 'GCP_ICEBERG_VOLUME'
  CATALOG = 'SNOWFLAKE'
  BASE_LOCATION = 'fact_ev_market_metrics'
  AS SELECT * FROM EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS;

-- Iceberg copy of manufacturer dimension
CREATE OR REPLACE ICEBERG TABLE DIM_MANUFACTURERS_GOLD
  EXTERNAL_VOLUME = 'GCP_ICEBERG_VOLUME'
  CATALOG = 'SNOWFLAKE'
  BASE_LOCATION = 'dim_manufacturers_gold'
  AS SELECT * FROM EV_PROJECT_DB.GOLD.DIM_MANUFACTURERS_GOLD;
