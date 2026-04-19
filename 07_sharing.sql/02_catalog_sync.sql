-- ================================================================
-- CATALOG SYNC: For non-Snowflake query engines (Spark, Trino, etc.)
-- Requires a Snowflake Open Catalog (Polaris) account.
-- ================================================================

-- Step 1: Create catalog integration to Open Catalog
-- CREATE OR REPLACE CATALOG INTEGRATION EV_OPEN_CATALOG_INT
--   CATALOG_SOURCE = POLARIS
--   TABLE_FORMAT = ICEBERG
--   REST_CONFIG = (
--     CATALOG_URI = 'https://<org>-<open-catalog-account>.snowflakecomputing.com/polaris/api/catalog'
--     CATALOG_NAME = '<external_catalog_name>'
--   )
--   REST_AUTHENTICATION = (
--     TYPE = OAUTH
--     OAUTH_CLIENT_ID = '<client_id>'
--     OAUTH_CLIENT_SECRET = '<client_secret>'
--     OAUTH_ALLOWED_SCOPES = ('PRINCIPAL_ROLE:ALL')
--   )
--   ENABLED = TRUE;

-- Step 2: Enable catalog sync on the GOLD schema
-- ALTER SCHEMA EV_PROJECT_DB.GOLD SET CATALOG_SYNC = 'EV_OPEN_CATALOG_INT';

-- After this, FACT_EV_MARKET_METRICS is automatically synced to Open Catalog.
-- Spark, Trino, BigQuery can query it via the Iceberg REST catalog protocol.
