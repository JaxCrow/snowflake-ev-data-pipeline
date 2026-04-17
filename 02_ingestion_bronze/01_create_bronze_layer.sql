-- ============================================================
-- Bronze Layer: File Format, External Stage, and Raw Tables
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE EV_PROJECT_DB;
USE SCHEMA BRONZE;

-- 1. JSON File Format
CREATE OR REPLACE FILE FORMAT JSON_FORMAT
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;

-- 2. External Stage pointing to GCS landing/
CREATE OR REPLACE STAGE GCP_EV_STAGE
  URL = 'gcs://ev-landing-zone-lordrivas/landing/'
  STORAGE_INTEGRATION = GCP_EV_STORAGE_INT
  FILE_FORMAT = JSON_FORMAT;

-- 3. Raw EV data table (JSON → VARIANT)
CREATE OR REPLACE TABLE RAW_EV_DATA (
  RAW_DOCUMENT     VARIANT,
  LOAD_TIMESTAMP   TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 4. Manufacturer dimension table
CREATE OR REPLACE TABLE DIM_MANUFACTURERS_BRONZE (
  MANUFACTURER_ID    INT,
  MANUFACTURER_NAME  VARCHAR,
  COUNTRY            VARCHAR
);