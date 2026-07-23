-- ============================================================
-- 03_DEMO_POSTGRES_SIM_BRIDGE.sql
-- Demo-only bridge: replace external PostgreSQL connection with
-- internal Snowflake schema POSTGRES_SIM, while keeping the rest
-- of the CDC process unchanged.
--
-- Keeps existing flow from 01_postgresql_cdc.sql:
-- POSTGRES_SIM source -> GOLD.PG_VEHICLE_CATALOG_STAGING
-- -> SP_SYNC_PG_VEHICLE_CATALOG_CDC() -> GOLD dimensions/views
-- ============================================================

USE DATABASE EV_PROJECT_DB;
CREATE SCHEMA IF NOT EXISTS POSTGRES_SIM;

USE SCHEMA EV_PROJECT_DB.POSTGRES_SIM;

-- ------------------------------------------------------------
-- 1) Simulated PostgreSQL source table (catalog)
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE VEHICLE_CATALOG (
    CATALOG_ID NUMBER(38,0),
    MANUFACTURER_ID NUMBER(38,0),
    MANUFACTURER_NAME VARCHAR,
    COUNTRY VARCHAR,
    VEHICLE_CLASS VARCHAR,
    VEHICLE_CATEGORY VARCHAR,
    FUEL_TYPE VARCHAR,
    TRANSMISSION VARCHAR,
    SEATING_CAPACITY NUMBER(38,0),
    LAST_UPDATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Optional seed based on existing GOLD manufacturer dimension.
-- Safe to run multiple times.
MERGE INTO EV_PROJECT_DB.POSTGRES_SIM.VEHICLE_CATALOG t
USING (
    SELECT
        MANUFACTURER_ID AS CATALOG_ID,
        MANUFACTURER_ID,
        MANUFACTURER_NAME,
        'UNKNOWN' AS COUNTRY,
        'PASSENGER' AS VEHICLE_CLASS,
        'EV' AS VEHICLE_CATEGORY,
        'ELECTRIC' AS FUEL_TYPE,
        'AUTO' AS TRANSMISSION,
        5 AS SEATING_CAPACITY,
        CURRENT_TIMESTAMP() AS LAST_UPDATED_AT
    FROM EV_PROJECT_DB.GOLD.DIM_MANUFACTURERS_GOLD
) s
ON t.CATALOG_ID = s.CATALOG_ID
WHEN MATCHED THEN UPDATE SET
    t.MANUFACTURER_ID = s.MANUFACTURER_ID,
    t.MANUFACTURER_NAME = s.MANUFACTURER_NAME,
    t.COUNTRY = s.COUNTRY,
    t.VEHICLE_CLASS = s.VEHICLE_CLASS,
    t.VEHICLE_CATEGORY = s.VEHICLE_CATEGORY,
    t.FUEL_TYPE = s.FUEL_TYPE,
    t.TRANSMISSION = s.TRANSMISSION,
    t.SEATING_CAPACITY = s.SEATING_CAPACITY,
    t.LAST_UPDATED_AT = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
    CATALOG_ID,
    MANUFACTURER_ID,
    MANUFACTURER_NAME,
    COUNTRY,
    VEHICLE_CLASS,
    VEHICLE_CATEGORY,
    FUEL_TYPE,
    TRANSMISSION,
    SEATING_CAPACITY,
    LAST_UPDATED_AT
) VALUES (
    s.CATALOG_ID,
    s.MANUFACTURER_ID,
    s.MANUFACTURER_NAME,
    s.COUNTRY,
    s.VEHICLE_CLASS,
    s.VEHICLE_CATEGORY,
    s.FUEL_TYPE,
    s.TRANSMISSION,
    s.SEATING_CAPACITY,
    s.LAST_UPDATED_AT
);

-- ------------------------------------------------------------
-- 2) Bridge procedure: POSTGRES_SIM -> GOLD CDC staging
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE EV_PROJECT_DB.GOLD.SP_LOAD_POSTGRES_SIM_TO_STAGING()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    TRUNCATE TABLE EV_PROJECT_DB.GOLD.PG_VEHICLE_CATALOG_STAGING;

    INSERT INTO EV_PROJECT_DB.GOLD.PG_VEHICLE_CATALOG_STAGING (
        CATALOG_ID,
        MANUFACTURER_ID,
        MANUFACTURER_NAME,
        COUNTRY,
        VEHICLE_CLASS,
        VEHICLE_CATEGORY,
        FUEL_TYPE,
        TRANSMISSION,
        SEATING_CAPACITY,
        LAST_UPDATED_AT,
        SOURCE_TIMESTAMP
    )
    SELECT
        CATALOG_ID,
        MANUFACTURER_ID,
        MANUFACTURER_NAME,
        COUNTRY,
        VEHICLE_CLASS,
        VEHICLE_CATEGORY,
        FUEL_TYPE,
        TRANSMISSION,
        SEATING_CAPACITY,
        LAST_UPDATED_AT,
        CURRENT_TIMESTAMP()
    FROM EV_PROJECT_DB.POSTGRES_SIM.VEHICLE_CATALOG;

    RETURN 'SUCCESS: POSTGRES_SIM loaded into PG_VEHICLE_CATALOG_STAGING';
END;
$$;

-- ------------------------------------------------------------
-- 3) Demo runner: keeps existing CDC sync procedure unchanged
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE EV_PROJECT_DB.GOLD.SP_RUN_POSTGRES_SIM_CDC_DEMO()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    step1 VARCHAR;
    step2 VARCHAR;
BEGIN
    CALL EV_PROJECT_DB.GOLD.SP_LOAD_POSTGRES_SIM_TO_STAGING() INTO :step1;
    CALL EV_PROJECT_DB.GOLD.SP_SYNC_PG_VEHICLE_CATALOG_CDC() INTO :step2;

    RETURN 'SUCCESS: ' || :step1 || ' | ' || :step2;
END;
$$;

-- ------------------------------------------------------------
-- 4) Demo task (optional): every 12h, same cadence as CDC task
-- ------------------------------------------------------------
CREATE OR REPLACE TASK EV_PROJECT_DB.GOLD.TSK_POSTGRES_SIM_CDC_DEMO
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 */12 * * * UTC'
AS
  CALL EV_PROJECT_DB.GOLD.SP_RUN_POSTGRES_SIM_CDC_DEMO();

-- ------------------------------------------------------------
-- 5) Manual execution and validation
-- ------------------------------------------------------------
-- EXECUTE once for demo:
-- CALL EV_PROJECT_DB.GOLD.SP_RUN_POSTGRES_SIM_CDC_DEMO();
--
-- Validate output:
-- SELECT COUNT(*) FROM EV_PROJECT_DB.POSTGRES_SIM.VEHICLE_CATALOG;
-- SELECT COUNT(*) FROM EV_PROJECT_DB.GOLD.DIM_VEHICLE_CATALOG_GOLD;
-- SELECT * FROM EV_PROJECT_DB.GOLD.VW_CDC_SYNC_MONITOR;
--
-- Optional task control:
-- ALTER TASK EV_PROJECT_DB.GOLD.TSK_POSTGRES_SIM_CDC_DEMO RESUME;
-- ALTER TASK EV_PROJECT_DB.GOLD.TSK_POSTGRES_SIM_CDC_DEMO SUSPEND;
