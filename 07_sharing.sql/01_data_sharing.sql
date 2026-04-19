-- ================================================================
-- SECURE DATA SHARING — Secure Views + Share
-- ================================================================

CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.SHARING;

-- Secure view: Fact table (market metrics)
CREATE OR REPLACE SECURE VIEW EV_PROJECT_DB.SHARING.SV_FACT_EV_MARKET_METRICS AS
SELECT
    MAKE,
    EV_TYPE,
    TOTAL_VEHICLES,
    AVG_RANGE,
    MAX_MSRP,
    LOAD_TIMESTAMP
FROM EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS;

-- Secure view: Dimension table (manufacturers)
CREATE OR REPLACE SECURE VIEW EV_PROJECT_DB.SHARING.SV_DIM_MANUFACTURERS AS
SELECT
    MANUFACTURER_ID,
    MANUFACTURER_NAME,
    COUNTRY
FROM EV_PROJECT_DB.GOLD.DIM_MANUFACTURERS_GOLD;

-- Secure view: Data quality summary (transparency for consumers)
CREATE OR REPLACE SECURE VIEW EV_PROJECT_DB.SHARING.SV_DATA_QUALITY_SUMMARY AS
SELECT
    SOURCE_LAYER,
    ERROR_TYPE,
    TOTAL_ERRORS,
    ERRORS_LAST_24H,
    RECONCILIATION_STATUS
FROM EV_PROJECT_DB.DATA_QUALITY.V_DQ_DASHBOARD;

-- ================================================================
-- SHARE: For Snowflake account consumers (zero-copy)
-- ================================================================

CREATE OR REPLACE SHARE EV_MARKET_DATA_SHARE
  COMMENT = 'EV market metrics, manufacturer dimensions, and data quality summary';

GRANT USAGE ON DATABASE EV_PROJECT_DB TO SHARE EV_MARKET_DATA_SHARE;
GRANT USAGE ON SCHEMA EV_PROJECT_DB.SHARING TO SHARE EV_MARKET_DATA_SHARE;
GRANT SELECT ON VIEW EV_PROJECT_DB.SHARING.SV_FACT_EV_MARKET_METRICS TO SHARE EV_MARKET_DATA_SHARE;
GRANT SELECT ON VIEW EV_PROJECT_DB.SHARING.SV_DIM_MANUFACTURERS TO SHARE EV_MARKET_DATA_SHARE;
GRANT SELECT ON VIEW EV_PROJECT_DB.SHARING.SV_DATA_QUALITY_SUMMARY TO SHARE EV_MARKET_DATA_SHARE;

-- To add a Snowflake consumer account:
-- ALTER SHARE EV_MARKET_DATA_SHARE ADD ACCOUNTS = <consumer_account_locator>;

-- ================================================================
-- READER ACCOUNT: For non-Snowflake users
-- ================================================================

-- Reader account created (managed by provider):
-- Name: EV_DATA_READER
-- Locator: UA12095
-- URL: https://bovwcbf-ev_data_reader.snowflakecomputing.com

-- CREATE MANAGED ACCOUNT EV_DATA_READER
--   ADMIN_NAME = 'ev_reader_admin',
--   ADMIN_PASSWORD = '********',
--   TYPE = READER;

ALTER SHARE EV_MARKET_DATA_SHARE ADD ACCOUNTS = UA12095;

