-- ============================================================
-- ACCOUNT-LEVEL INTEGRATIONS (GCP)
-- ============================================================

-- Storage Integration: Grants Snowflake access to GCS bucket
CREATE OR REPLACE STORAGE INTEGRATION GCP_EV_STORAGE_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'GCS'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('gcs://ev-landing-zone-lordrivas/');

-- Notification Integration: Pub/Sub subscription for new file events
CREATE OR REPLACE NOTIFICATION INTEGRATION GCP_EV_PUBSUB_INT
  TYPE = QUEUE
  NOTIFICATION_PROVIDER = GCP_PUBSUB
  ENABLED = TRUE
  GCP_PUBSUB_SUBSCRIPTION_NAME = 'projects/algebraic-craft-436723-n7/subscriptions/ev-snowflake-subscription';

-- External Volume: GCS storage for Iceberg table metadata and data
CREATE OR REPLACE EXTERNAL VOLUME GCP_ICEBERG_VOLUME
  STORAGE_LOCATIONS = (
    (
      NAME = 'gcs-us-central1'
      STORAGE_PROVIDER = 'GCS'
      STORAGE_BASE_URL = 'gcs://ev-landing-zone-lordrivas/iceberg_data/'
    )
  )
  ALLOW_WRITES = TRUE;
