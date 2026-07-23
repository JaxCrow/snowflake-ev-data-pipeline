-- ============================================================
-- 01_INFRASTRUCTURE.sql
-- Account-level objects: warehouse, storage integration,
-- notification integrations, external volume
-- ============================================================

-- Warehouse
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 300
  AUTO_RESUME = TRUE;

-- Storage Integration (Azure Blob Storage)
CREATE OR REPLACE STORAGE INTEGRATION AZURE_EV_STORAGE_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  AZURE_TENANT_ID = '92d1d6ee-9c8b-4a1f-9fec-3da3e0b8b618'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('azure://evpipedev346059.blob.core.windows.net/landing/');

-- Notification Integration (Inbound — Azure Event Grid via Queue)
CREATE OR REPLACE NOTIFICATION INTEGRATION AZURE_EV_EVENTGRID_INT
  TYPE = QUEUE
  NOTIFICATION_PROVIDER = AZURE_STORAGE_QUEUE
  ENABLED = TRUE
  AZURE_STORAGE_QUEUE_PRIMARY_URI = 'https://evpipedev346059.queue.core.windows.net/evingestqueue'
  AZURE_TENANT_ID = '92d1d6ee-9c8b-4a1f-9fec-3da3e0b8b618';

-- Notification Integration (Outbound — Email for DQ Alerts)
CREATE OR REPLACE NOTIFICATION INTEGRATION EV_DQ_EMAIL_INT
  TYPE = EMAIL
  ENABLED = TRUE;

-- External Volume (Azure Blob Storage for Iceberg tables)
CREATE OR REPLACE EXTERNAL VOLUME AZURE_ICEBERG_VOLUME
  STORAGE_LOCATIONS = (
    (
      NAME = 'azure-iceberg'
      STORAGE_PROVIDER = 'AZURE'
      AZURE_TENANT_ID = '92d1d6ee-9c8b-4a1f-9fec-3da3e0b8b618'
      STORAGE_BASE_URL = 'azure://evpipedev346059.blob.core.windows.net/iceberg/'
    )
  )
  ALLOW_WRITES = TRUE;

-- Database
CREATE DATABASE IF NOT EXISTS EV_PROJECT_DB;

-- Schemas
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.BRONZE;
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.SILVER;
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.GOLD;
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.ICEBERG;
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.DBT_GOLD;
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.DATA_QUALITY;
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.SHARING;
