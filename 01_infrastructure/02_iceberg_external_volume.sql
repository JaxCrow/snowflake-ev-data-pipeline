-- ============================================================
-- 01_INFRASTRUCTURE: Apache Iceberg External Volume
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- Volume setup pointing to GCP bucket for Open Format storage
CREATE OR REPLACE EXTERNAL VOLUME GCP_ICEBERG_VOLUME
   STORAGE_LOCATIONS =
      (
         (
            NAME = 'gcs-us-central1'
            STORAGE_PROVIDER = 'GCS'
            STORAGE_BASE_URL = 'gcs://ev-landing-zone-lordrivas/iceberg_data/'
         )
      );