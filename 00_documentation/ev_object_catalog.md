# EV Pipeline — Complete Object Catalog

Database: **EV_PROJECT_DB**

---

## BRONZE Schema — Raw Ingestion

| Object | Type | Rows | Description |
|--------|------|------|-------------|
| **RAW_EV_DATA** | Table | 22,183 | Raw JSON records ingested from GCS. Each row contains a VARIANT column (JSON_DATA) with the full source payload, plus SOURCE_FILE, SOURCE_FILE_ROW, and LOAD_TIMESTAMP metadata. This is the immutable audit trail — no transformations applied. |
| **GCP_EV_STAGE** | External Stage | — | Points to `gcs://ev-landing-zone-lordrivas/landing/`. Uses GCP_EV_STORAGE_INT for authentication and has directory enabled for stream support. Pub/Sub integration (GCP_EV_PUBSUB_INT) auto-refreshes on file arrival events. |
| **GCS_FILES_STREAM** | Directory Stream | — | Monitors GCP_EV_STAGE for new file arrivals. Consumed by TSK_INGEST_EV_DATA to trigger event-driven ingestion. Delta mode — tracks only new files since last consumption. |
| **SP_INGEST_RAW_EV_DATA** | Stored Procedure (Python) | — | Executes COPY INTO RAW_EV_DATA from the GCS stage. Uses ON_ERROR = ABORT_STATEMENT (atomic loads) and PURGE = TRUE (cleanup after load). Returns SUCCESS/FAILURE with row counts. |
| **TSK_INGEST_EV_DATA** | Task (Root) | — | Runs every 1 minute. Only fires when `SYSTEM$STREAM_HAS_DATA('GCS_FILES_STREAM')` is true. Calls SP_INGEST_RAW_EV_DATA. Root task of a 3-node DAG. |
| **TSK_ERROR_DETECTION** | Task (Child) | — | Runs AFTER TSK_INGEST_EV_DATA. Calls SP_DETECT_ERRORS to scan bronze and silver for data issues immediately after each ingestion cycle. |
| **TSK_ERROR_NOTIFICATION** | Task (Child) | — | Runs AFTER TSK_ERROR_DETECTION. Calls SP_NOTIFY_ERRORS to send email alerts if new errors were found. |
| **JSON_FORMAT** | File Format | — | JSON file format used by COPY INTO for parsing raw GCS files. |

---

## SILVER Schema — Cleansed & Deduplicated

| Object | Type | Rows | Description |
|--------|------|------|-------------|
| **CLEAN_EV_DATA_DT** | Dynamic Table | 4,986 | Flattened, typed, deduplicated vehicle records. Transforms RAW_EV_DATA JSON via LATERAL FLATTEN, casts 13 columns to proper types, rejects NULL VINs, and deduplicates by VIN using QUALIFY ROW_NUMBER. INCREMENTAL refresh mode with 1-minute target lag. |
| **CLEAN_EV_DATA_DT_STREAM** | Stream | — | Captures row-level changes (inserts, updates) on the Dynamic Table. Consumed by TASK_SILVER_TO_GOLD to trigger gold layer refresh. SHOW_INITIAL_ROWS = FALSE. |

### CLEAN_EV_DATA_DT Columns

| Column | Type | Description |
|--------|------|-------------|
| VIN | VARCHAR | Vehicle Identification Number (truncated to 10 chars). Primary deduplication key. |
| MAKE | VARCHAR | Manufacturer name (e.g., TESLA, CHEVROLET, FORD). |
| MODEL | VARCHAR | Vehicle model name (e.g., MODEL 3, BOLT EV). |
| MODEL_YEAR | INT | Model year of the vehicle (2011–2024). |
| EV_TYPE | VARCHAR | Battery Electric Vehicle (BEV) or Plug-in Hybrid Electric Vehicle (PHEV). |
| ELECTRIC_RANGE | INT | Electric-only driving range in miles. |
| BASE_MSRP | FLOAT | Base manufacturer's suggested retail price. |
| LEGISLATIVE_DISTRICT | VARCHAR | Legislative district of the registration address. |
| DOL_VEHICLE_ID | VARCHAR | Department of Licensing vehicle identifier. |
| VEHICLE_LOCATION | VARCHAR | Geographic coordinates of the vehicle registration. |
| ELECTRIC_UTILITY | VARCHAR | Electric utility provider serving the address. |
| CENSUS_TRACT_2020 | VARCHAR | 2020 Census tract identifier. |
| COUNTIES | VARCHAR | County of the registration address. |
| SOURCE_FILE | VARCHAR | Name of the GCS file this record was ingested from. |

---

## GOLD Schema — Business-Ready

| Object | Type | Rows | Description |
|--------|------|------|-------------|
| **FACT_EV_REGISTRATIONS** | Table | 4,986 | Enriched row-level registration data with 18 columns. Adds geographic fields (CITY, COUNTY, STATE, ZIP_CODE), CAFV eligibility, and utility provider. Powers the semantic model and Cortex Analyst. Traditional Snowflake table — full Fail-safe, cloning, and stream support. |
| **FACT_EV_MARKET_METRICS** | Iceberg Table | 46 | Pre-aggregated metrics by MAKE and EV_TYPE: TOTAL_VEHICLES, AVG_RANGE, MAX_MSRP, LOAD_TIMESTAMP. Stored as Parquet on GCS via GCP_ICEBERG_VOLUME. Designed for cross-engine access (Spark, Trino, BigQuery). |
| **DIM_MANUFACTURERS_GOLD** | Table | 35 | Manufacturer dimension with MANUFACTURER_ID, MANUFACTURER_NAME, and COUNTRY. Populated via Snowflake Connector for PostgreSQL (NeonDB CDC). Not managed by the pipeline — externally maintained. |
| **SP_TRANSFORM_SILVER_TO_GOLD** | Stored Procedure (Python) | — | Reads CLEAN_EV_DATA_DT, enriches and loads FACT_EV_REGISTRATIONS, aggregates and loads FACT_EV_MARKET_METRICS (truncate-reload pattern). |
| **TASK_SILVER_TO_GOLD** | Task | — | Fires when `SYSTEM$STREAM_HAS_DATA('CLEAN_EV_DATA_DT_STREAM')` is true. Calls SP_TRANSFORM_SILVER_TO_GOLD. |
| **SEMANTIC_MODELS** | Internal Stage | — | Stores ev_semantic_model.yaml, ev_chat_app.py, and environment.yml. Root location for the Streamlit app deployment. |
| **EV_MARKET_ANALYTICS** | Semantic View | — | Registered semantic model as a native Snowflake object. Two entities (fact_ev_registrations, dim_manufacturers), 8 metrics, 13 dimensions, 7 verified queries. Visible in Cortex AI Analyst UI and governed by RBAC. |
| **EV_MARKET_CHAT** | Streamlit App | — | Conversational analytics interface. Sidebar KPI metrics, suggested questions, multi-turn chat with Cortex Analyst, auto-generated SQL and charts. |

### FACT_EV_REGISTRATIONS Columns

| Column | Type | Description |
|--------|------|-------------|
| VIN | VARCHAR | Unique Vehicle Identification Number. |
| MAKE | VARCHAR | Manufacturer name. |
| MODEL | VARCHAR | Vehicle model name. |
| MODEL_YEAR | INT | Model year. |
| EV_TYPE | VARCHAR | BEV or PHEV. |
| CAFV_ELIGIBILITY | VARCHAR | Clean Alternative Fuel Vehicle incentive eligibility status. |
| ELECTRIC_RANGE | INT | Electric-only range in miles. |
| BASE_MSRP | FLOAT | Base MSRP. |
| LEGISLATIVE_DISTRICT | VARCHAR | Legislative district. |
| DOL_VEHICLE_ID | VARCHAR | Department of Licensing ID. |
| VEHICLE_LOCATION | VARCHAR | Geographic coordinates. |
| ELECTRIC_UTILITY | VARCHAR | Utility provider. |
| CENSUS_TRACT_2020 | VARCHAR | Census tract. |
| CITY | VARCHAR | Registration city. |
| COUNTY | VARCHAR | Registration county. |
| STATE | VARCHAR | Registration state (abbreviation). |
| ZIP_CODE | VARCHAR | Registration ZIP code. |
| LOAD_TIMESTAMP | TIMESTAMP_LTZ | When the record was loaded into gold. |

### FACT_EV_MARKET_METRICS Columns (Iceberg)

| Column | Type | Description |
|--------|------|-------------|
| MAKE | STRING | Manufacturer name. |
| EV_TYPE | STRING | BEV or PHEV. |
| TOTAL_VEHICLES | INT | Count of registered vehicles for this MAKE + EV_TYPE combination. |
| AVG_RANGE | FLOAT | Average electric range in miles. |
| MAX_MSRP | FLOAT | Maximum base MSRP in the group. |
| LOAD_TIMESTAMP | TIMESTAMP_LTZ | When the aggregation was last run. |

### DIM_MANUFACTURERS_GOLD Columns

| Column | Type | Description |
|--------|------|-------------|
| MANUFACTURER_ID | NUMBER | Unique manufacturer identifier (from PostgreSQL source). |
| MANUFACTURER_NAME | VARCHAR | Manufacturer name (join key to FACT_EV_REGISTRATIONS.MAKE). |
| COUNTRY | VARCHAR | Country of headquarters (e.g., United States, Japan, Germany). |

---

## DATA_QUALITY Schema — Monitoring & Quarantine

| Object | Type | Rows | Description |
|--------|------|------|-------------|
| **ERROR_ROWS** | Table | 1,549 | Quarantine table for data quality violations. Each row has: SOURCE_LAYER, ERROR_TYPE, VIN, MAKE, MODEL, RAW_DATA (VARIANT), DETECTED_AT, and SOURCE_FILE. Six error types: NULL_CRITICAL_FIELD, INVALID_RANGE, NEGATIVE_MSRP, ORPHAN_MAKE, DUPLICATE_VIN, DUPLICATE_DOL_ID. |
| **DUPLICATE_ROWS** | Table | 2,981 | Quarantine table for duplicate records detected across bronze and silver. Includes VIN, MAKE, MODEL, DUPLICATE_COUNT, and SOURCE_FILE. |
| **ERROR_ROWS_STREAM** | Stream | — | Captures new errors inserted into ERROR_ROWS. Triggers SP_NOTIFY_ERRORS for email alerts. |
| **DUPLICATE_ROWS_STREAM** | Stream | — | Captures new duplicates inserted into DUPLICATE_ROWS. |
| **SP_DETECT_ERRORS** | Stored Procedure | — | Scans bronze and silver for six error types. Writes violations to ERROR_ROWS and DUPLICATE_ROWS with full context. Runs as AFTER task in the ingestion DAG. |
| **SP_NOTIFY_ERRORS** | Stored Procedure | — | Sends email notification when new errors are detected. Triggered by TSK_ERROR_NOTIFICATION. |
| **V_DQ_AUDIT** | View | — | Historical DMF results from SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS. Trend analysis of quality metrics over time. |
| **V_DQ_DASHBOARD** | View | — | Summary dashboard combining error counts, reconciliation status, and DMF results. Single-pane view of pipeline health. |
| **V_ERROR_TREND** | View | — | Hourly time-series of error counts by error type. Shows whether quality is improving or degrading over time. |
| **V_PIPELINE_LINEAGE** | View | — | Traces data flow from bronze through silver to gold. Shows object dependencies and data transformation lineage. |
| **V_ROW_COUNT_RECONCILIATION** | View | — | Cross-layer consistency check. Computes: bronze raw → flattened → unique VINs → silver → gold total vehicles. Returns PASS or DRIFT_DETECTED with drift percentages. |
| **V_TOP_OFFENDERS** | View | — | Ranks manufacturers by number of data quality issues. Identifies which MAKEs contribute the most errors. |

### Data Metric Functions (DMFs)

| DMF | Type | Table | Description |
|-----|------|-------|-------------|
| SNOWFLAKE.CORE.NULL_COUNT | System | Bronze, Silver, Gold | Counts NULL values in critical columns (VIN, MAKE, MODEL, SOURCE_FILE). |
| SNOWFLAKE.CORE.DUPLICATE_COUNT | System | Silver | Counts duplicate values in VIN and DOL_VEHICLE_ID. |
| SNOWFLAKE.CORE.FRESHNESS | System | Bronze, Gold | Monitors data staleness — detects pipeline failures. |
| SNOWFLAKE.CORE.ROW_COUNT | System | Gold | Tracks row count changes for anomaly detection. |
| INVALID_ELECTRIC_RANGE | Custom | Silver | Counts vehicles with electric range <= 0 or NULL. |
| NEGATIVE_MSRP | Custom | Silver | Counts vehicles with negative retail price. |
| ORPHAN_MAKE_CHECK | Custom (multi-table) | Silver | Finds MAKEs in registrations not present in DIM_MANUFACTURERS_GOLD. |
| ROW_COUNT_DRIFT_SILVER_VS_BRONZE | Custom (cross-layer) | Silver | Detects data loss or duplication between bronze and silver. Should be 0. |
| GOLD_VEHICLE_COUNT_DRIFT | Custom (cross-layer) | Gold | Compares gold total vehicles to silver count. Should be 0. |
| GOLD_MAKE_COVERAGE | Custom (cross-layer) | Silver | Counts manufacturers missing from gold aggregation. Should be 0. |

---

## SHARING Schema — External Access

| Object | Type | Description |
|--------|------|-------------|
| **SV_FACT_EV_MARKET_METRICS** | Secure View | Exposes: MAKE, EV_TYPE, TOTAL_VEHICLES, AVG_RANGE, MAX_MSRP, LOAD_TIMESTAMP from the Iceberg table. Hides internal metadata. Prevents query pushdown attacks. |
| **SV_DIM_MANUFACTURERS** | Secure View | Exposes: MANUFACTURER_ID, MANUFACTURER_NAME, COUNTRY. Column-filtered view of the dimension table. |
| **SV_DATA_QUALITY_SUMMARY** | Secure View | Exposes: ERROR_TYPE, TOTAL_ERRORS, ERRORS_LAST_24H, RECONCILIATION_STATUS. Deliberate transparency — consumers can assess data fitness. |
| **EV_MARKET_DATA_SHARE** | Snowflake Share | Contains all three secure views above. Shared to EV_DATA_READER (reader account). Zero-copy — consumers query provider storage directly. |
| **EV_DATA_READER** | Reader Account | Managed account (locator: UA12095) for external users without Snowflake accounts. Read-only SQL access. Provider pays compute. |

---

## Account-Level Objects

| Object | Type | Description |
|--------|------|-------------|
| **GCP_EV_STORAGE_INT** | Storage Integration | Grants Snowflake access to GCS bucket `gcs://ev-landing-zone-lordrivas/`. |
| **GCP_EV_PUBSUB_INT** | Notification Integration | Pub/Sub subscription for file arrival events. Triggers stage directory auto-refresh. |
| **GCP_ICEBERG_VOLUME** | External Volume | GCS storage for Iceberg table data and metadata at `gcs://ev-landing-zone-lordrivas/iceberg_data/`. ALLOW_WRITES = TRUE. |
| **EV_PIPELINE_MONITOR** | Resource Monitor | Warehouse-level (COMPUTE_WH). 20 credits/month. Notify at 75%, suspend at 95%, immediate suspend at 100%. |
| **EV_ACCOUNT_MONITOR** | Resource Monitor | Account-level. 50 credits/month. Same trigger thresholds. Safety net for total credit consumption. |
| **COMPUTE_WH** | Warehouse (X-Small) | Single shared warehouse for all pipeline workloads. Auto-suspend 60s, auto-resume enabled. |

---

## Object Count Summary

| Schema | Tables | Dynamic Tables | Views | Streams | Tasks | Stored Procs | Stages |
|--------|--------|----------------|-------|---------|-------|-------------|--------|
| BRONZE | 1 | 0 | 0 | 1 | 3 | 1 | 1 |
| SILVER | 0 | 1 | 0 | 1 | 0 | 0 | 0 |
| GOLD | 3 | 0 | 0 | 0 | 1 | 1 | 1 |
| DATA_QUALITY | 2 | 0 | 5 | 2 | 0 | 2 | 0 |
| SHARING | 0 | 0 | 3 | 0 | 0 | 0 | 0 |
| **Total** | **6** | **1** | **8** | **4** | **4** | **4** | **2** |
