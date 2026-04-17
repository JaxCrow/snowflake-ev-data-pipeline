-- ============================================================
-- GCP Integrations: Zero-Key Service Account Method
-- Run as ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- 1. Storage Integration for GCS
CREATE OR REPLACE STORAGE INTEGRATION GCP_EV_STORAGE_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'GCS'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('gcs://ev-landing-zone-lordrivas/');

-- 2. Notification Integration for GCP Pub/Sub (inbound)
CREATE OR REPLACE NOTIFICATION INTEGRATION GCP_EV_PUBSUB_INT
  ENABLED = TRUE
  TYPE = QUEUE
  NOTIFICATION_PROVIDER = GCP_PUBSUB
  GCP_PUBSUB_SUBSCRIPTION_NAME = 'projects/ev-snowflake-pipeline/subscriptions/ev-snowflake-subscription';

-- 3. Describe integrations to retrieve service account values
DESCRIBE INTEGRATION GCP_EV_STORAGE_INT;
DESCRIBE INTEGRATION GCP_EV_PUBSUB_INT;