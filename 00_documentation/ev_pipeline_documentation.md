# EV Data Pipeline — Architecture & Technical Documentation

## Overview

The EV_PROJECT_DB pipeline is a production-grade, event-driven data engineering solution built entirely on Snowflake-native services. It ingests electric vehicle registration data from Google Cloud Storage, transforms it through a medallion architecture (Bronze → Silver → Gold), enriches it with manufacturer dimension data replicated from a NeonDB PostgreSQL database, and serves aggregated analytics through an Apache Iceberg table. The pipeline is fully automated, incrementally processed, and continuously validated by Snowflake's Data Metric Functions (DMFs).

---

## 1. Account-Level Integrations

### GCP_EV_STORAGE_INT (Storage Integration)
Establishes a trust relationship between Snowflake and Google Cloud Storage using a Snowflake-managed GCP service account. This eliminates the need to store credentials in Snowflake — instead, the GCS bucket `gcs://ev-landing-zone-lordrivas/` grants access to Snowflake's service account via IAM policy. This follows the **principle of least privilege** by restricting access to a single allowed location.

### GCP_EV_PUBSUB_INT (Notification Integration)
Subscribes to a GCP Pub/Sub topic (`projects/algebraic-craft-436723-n7/subscriptions/ev-snowflake-subscription`) that fires events whenever new files land in the GCS bucket. This enables **event-driven ingestion** rather than polling — Snowflake's directory table on the stage is automatically refreshed when Pub/Sub delivers a notification, which in turn populates the stage stream.

### GCP_ICEBERG_VOLUME (External Volume)
Defines the GCS storage location (`gcs://ev-landing-zone-lordrivas/iceberg_data/`) where Snowflake writes Iceberg table data and metadata. With `ALLOW_WRITES = TRUE`, Snowflake manages the Iceberg catalog natively, writing Parquet data files and Iceberg metadata (manifest lists, manifests, and table metadata JSON) directly to GCS. This enables **open table format interoperability** — any engine that reads Iceberg (Spark, Trino, BigQuery) can query the gold layer without going through Snowflake.

---

## 2. External Data Replication — Snowflake Connector for PostgreSQL

### How It Works
The pipeline uses the **Snowflake Connector for PostgreSQL** (a Snowflake Native App) to replicate the `dim_manufacturers` table from a NeonDB PostgreSQL instance into Snowflake. The connector runs an external agent that connects to PostgreSQL using logical replication (CDC), captures row-level changes (inserts, updates, deletes), and streams them into a destination database (`NEON_DEST_DB`). Snowflake adds metadata columns (`_SNOWFLAKE_INSERTED_AT`, `_SNOWFLAKE_UPDATED_AT`, `_SNOWFLAKE_DELETED`) to track change history.

### Configuration
- **Host**: `ep-calm-fire-akpmq090-pooler.c-3.us-west-2.aws.neon.tech`
- **Database**: `neondb`
- **SSL**: Required
- **Scheduled Replication**: Every 15 minutes
- **Destination**: `NEON_DEST_DB.public.dim_manufacturers` → loaded into `EV_PROJECT_DB.GOLD.DIM_MANUFACTURERS_GOLD`

### Best Practice Alignment
This approach follows **ELT best practices** by landing external data as-is into the bronze layer and transforming downstream. The connector's CDC mechanism ensures **near-real-time synchronization** without full table scans on the source PostgreSQL instance, minimizing load on the operational database.

---

## 3. Bronze Layer — Raw Ingestion

### Objects

**GCP_EV_STAGE** — An external stage pointing to the GCS landing zone with directory table enabled. The directory table tracks file metadata (path, size, last modified) and serves as the source for the stage stream.

**GCS_FILES_STREAM** — A directory stream on the external stage. When new files appear (detected via Pub/Sub → directory auto-refresh), the stream captures the change as a delta record. This is what makes the pipeline event-driven: no files means no stream data, which means the task does not fire.

**TSK_INGEST_EV_DATA** — A scheduled task (every 1 minute) with a `WHEN` clause: `SYSTEM$STREAM_HAS_DATA('GCS_FILES_STREAM')`. Despite the 1-minute schedule, the task only consumes compute when new files actually exist, following the **"pay only for what you use"** principle. It calls the ingestion stored procedure.

**SP_INGEST_RAW_EV_DATA** — A Python Snowpark stored procedure that executes `COPY INTO` to load JSON files from the stage into `RAW_EV_DATA`. It uses `PURGE = TRUE` to remove processed files from the stage (preventing reprocessing) and `ON_ERROR = 'ABORT_STATEMENT'` to ensure atomicity — either all rows in a file load or none do. The procedure returns a status message with file and row counts for observability.

**RAW_EV_DATA** — The bronze landing table storing raw JSON as a VARIANT column alongside metadata (source file, row number, load timestamp). Storing raw data preserves the **immutable audit trail** — the original payload is never modified, enabling reprocessing if transformation logic changes.

### Best Practices
- **Immutability**: Raw data is stored exactly as received; no transformations at ingestion.
- **Idempotency**: `PURGE = TRUE` ensures files are not re-ingested.
- **Event-driven**: Stream + Task pattern avoids wasteful polling.
- **Metadata tracking**: `SOURCE_FILE` and `LOAD_TIMESTAMP` enable full traceability.

---

## 4. Silver Layer — Cleansing & Structuring

### Objects

**CLEAN_EV_DATA_DT** — A dynamic table with `REFRESH_MODE = INCREMENTAL` and `TARGET_LAG = '1 MINUTE'`. This is the core transformation engine. It flattens the nested JSON array (`JSON_DATA:data`) using `LATERAL FLATTEN`, extracts 14 typed columns (VIN, MAKE, MODEL, MODEL_YEAR, EV_TYPE, ELECTRIC_RANGE, BASE_MSRP, etc.), filters out records with null VINs, and **explicitly deduplicates** using `QUALIFY ROW_NUMBER() OVER (PARTITION BY VIN ORDER BY SOURCE_FILE DESC) = 1` — keeping only the most recent record per VIN.

The incremental refresh mode is critical: instead of reprocessing the entire bronze table on every refresh, Snowflake tracks which rows are new since the last refresh and processes only those. This was achieved by removing `CURRENT_TIMESTAMP()` from the query (non-deterministic functions force full refresh). The `QUALIFY` clause is confirmed by Snowflake as compatible with incremental refresh.

**CLEAN_EV_DATA_DT_STREAM** — A change data capture stream on the dynamic table. Whenever the dynamic table refreshes and produces new rows, this stream captures them. It serves as the trigger for the gold layer task.

### Why a Dynamic Table Instead of a Stored Procedure
The original pipeline used `SP_TRANSFORM_BRONZE_TO_SILVER` + a scheduled task. The dynamic table replacement provides:
- **Zero maintenance**: No procedural code to write, test, or debug.
- **Declarative freshness**: `TARGET_LAG` states the SLA; Snowflake manages the execution.
- **Automatic incremental logic**: No hand-coded MERGE statements.
- **Built-in dependency resolution**: If chained with other dynamic tables, Snowflake resolves the DAG automatically.
- **Cost efficiency**: Only refreshes when upstream data changes.

### Best Practices
- **Schema-on-read to schema-on-write**: Bronze stores raw JSON; silver enforces typed columns.
- **Null filtering**: `WHERE f.value[8] IS NOT NULL` rejects malformed records at the earliest stage.
- **Explicit deduplication**: `QUALIFY ROW_NUMBER()` ensures silver contains only unique VINs, reducing 22,183 raw records to 4,986 unique vehicles.
- **Incremental processing**: Minimizes compute cost and latency.

---

## 5. Gold Layer — Aggregation & Serving

### Objects

**DIM_MANUFACTURERS_GOLD** — The manufacturer dimension table (35 rows) replicated from NeonDB PostgreSQL via the Snowflake Connector for PostgreSQL. Contains manufacturer ID, name, and country of origin. Placed in the gold layer as a serving-ready dimension for joins with the fact table and for referential integrity validation in the silver layer.

**FACT_EV_MARKET_METRICS** — An Apache Iceberg table storing aggregated market analytics: total vehicles, average electric range, and maximum MSRP, grouped by MAKE and EV_TYPE. The Iceberg format stores data as Parquet files on GCS with open metadata, enabling:
- **Cross-engine interoperability**: Query from Spark, Trino, BigQuery, or Snowflake.
- **Time travel**: Iceberg's snapshot-based architecture supports historical queries.
- **Schema evolution**: Add or rename columns without rewriting data.
- **Open governance**: Data lives in your GCS bucket, not locked in a proprietary format.

**SP_TRANSFORM_SILVER_TO_GOLD** — A Python Snowpark stored procedure that reads from the silver dynamic table, aggregates using `GROUP BY MAKE, EV_TYPE` with `COUNT(VIN)`, `AVG(ELECTRIC_RANGE)`, and `MAX(BASE_MSRP)`, adds a load timestamp, truncates the gold table, and writes the fresh aggregation. The truncate-and-reload pattern is appropriate here because the gold table is a complete re-aggregation of the silver data (not an incremental append).

**TASK_SILVER_TO_GOLD** — A triggered task with `WHEN SYSTEM$STREAM_HAS_DATA('CLEAN_EV_DATA_DT_STREAM')`. This completes the event chain: new GCS file → bronze ingestion → dynamic table refresh → stream captures changes → task fires → gold table updated. The entire pipeline is **fully reactive** — no cron jobs, no manual intervention.

### Best Practices
- **Open table format**: Iceberg avoids vendor lock-in.
- **Event-driven orchestration**: Stream-triggered tasks ensure gold is always fresh when silver changes.
- **Separation of concerns**: Each layer has a single responsibility (ingest, clean, aggregate).

---

## 6. Data Quality — Validation Framework

The pipeline implements comprehensive data quality monitoring using Snowflake's native **Data Metric Functions (DMFs)**, organized in the `EV_PROJECT_DB.DATA_QUALITY` schema. DMFs run automatically on configurable schedules and persist results to `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` for historical trending and alerting.

### 6.1 Schema Validation
**EXPECTED_COLUMN_COUNT** — A custom DMF that returns the expected column count (14) for the silver dynamic table. Any deviation indicates schema drift caused by upstream changes in the JSON structure.

### 6.2 Completeness
**NULL_COUNT** (system DMF) — Applied to critical columns across all layers:
- **Bronze**: `SOURCE_FILE` — detects files loaded without metadata.
- **Silver**: `VIN`, `MAKE`, `MODEL` — the three columns that must never be null for a valid EV record.
- **Gold**: `MAKE` — ensures the aggregation dimension key is always populated.

**How it works**: The DMF counts null values in the specified column. A result of 0 means full completeness. Any non-zero value indicates missing data that should be investigated.

### 6.3 Uniqueness
**DUPLICATE_COUNT** (system DMF) — Applied to:
- **Silver**: `VIN` — Vehicle Identification Numbers should be unique; duplicates indicate re-ingestion or data quality issues at the source.
- **Silver**: `DOL_VEHICLE_ID` — The Department of Licensing ID should also be unique per registration.

**How it works**: The DMF counts values that appear more than once. A result of 0 means all values are unique; a result of N means N values have at least one duplicate.

### 6.4 Referential Integrity
**ORPHAN_MAKE_CHECK** — A custom multi-table DMF that counts how many MAKE values in the silver layer do not exist in `DIM_MANUFACTURERS_GOLD`. This catches:
- New manufacturers not yet added to the PostgreSQL source.
- Typos or inconsistencies in the source data.
- Replication lag where the dimension table hasn't synced yet.

**How it works**: The DMF receives two table arguments — the silver MAKE column and the dimension MANUFACTURER_NAME column — and returns the count of orphaned values. A result of 0 means perfect referential integrity.

### 6.5 Business Rules
**INVALID_ELECTRIC_RANGE** — A custom DMF that counts rows where `ELECTRIC_RANGE <= 0` or is NULL. Electric vehicles must have a positive range; zero or negative values indicate data entry errors or missing sensor data.

**NEGATIVE_MSRP** — A custom DMF that counts rows where `BASE_MSRP < 0`. A negative manufacturer's suggested retail price is physically impossible and indicates data corruption.

**How it works**: Both DMFs return a count of violations. A result of 0 means all records comply with the business rule.

### 6.6 Freshness
**FRESHNESS** (system DMF) — Applied to:
- **Bronze**: `LOAD_TIMESTAMP` — monitors how recently data was ingested. If freshness degrades beyond the expected 1-minute cycle, it indicates ingestion pipeline issues (GCS delivery delay, task failure, or warehouse suspension).
- **Gold**: `LOAD_TIMESTAMP` — monitors how recently the gold table was refreshed. Staleness here indicates the silver-to-gold task isn't firing (stream issue, task suspension, or SP failure).

**How it works**: The DMF computes the time difference between the most recent timestamp value and the current time. The result is an interval — smaller intervals mean fresher data.

### 6.7 Statistical Monitoring
**AVG, MIN, MAX** (system DMFs) — Applied to gold metrics:
- `AVG(TOTAL_VEHICLES)` — tracks the average vehicle count per group over time. A sudden change could indicate data loss or duplication.
- `MIN(AVG_RANGE)` and `MAX(AVG_RANGE)` — monitors the bounds of the average electric range metric. Outliers here flag potential data quality issues upstream.

### Scheduling Strategy
| Layer | Schedule | Rationale |
|---|---|---|
| Bronze | Every 30 minutes | Periodic check; ingestion is event-driven so changes are infrequent |
| Silver | TRIGGER_ON_CHANGES | Runs only when the dynamic table refreshes; avoids unnecessary compute |
| Gold | TRIGGER_ON_CHANGES | Runs only when the SP updates the iceberg table |

This follows the **"right-size your monitoring"** principle: high-frequency layers get event-driven checks, while stable layers get periodic checks.

---

## 7. Cross-Layer Validation

### Row Count Reconciliation DMFs
Three custom DMFs provide automated cross-layer consistency checks:

**ROW_COUNT_DRIFT_SILVER_VS_BRONZE** — Compares the silver row count against the count of valid flattened records in bronze. A result of 0 confirms that every valid bronze record made it to silver. A non-zero result indicates records were lost or duplicated during the flattening/filtering transformation.

**GOLD_VEHICLE_COUNT_DRIFT** — Compares `SUM(TOTAL_VEHICLES)` in gold against the silver row count. Since gold aggregates silver by MAKE and EV_TYPE, the sum of vehicle counts should exactly equal the total silver rows. A drift of 0 confirms the aggregation is mathematically consistent.

**GOLD_MAKE_COVERAGE** — Counts distinct MAKEs present in silver but missing from gold. A result of 0 means every manufacturer in silver has a corresponding aggregation group in gold. A non-zero result indicates the gold SP failed to include certain groups (likely a filter or error issue).

### V_ROW_COUNT_RECONCILIATION (View)
A single-row dashboard view that computes all reconciliation metrics in real time, accounting for deduplication:
- `bronze_raw_rows` — Number of raw JSON documents in bronze.
- `bronze_flattened_rows` — Number of valid individual records after flattening.
- `bronze_unique_vins` — Number of distinct VINs in bronze (after dedup baseline).
- `duplicates_removed` — Count of duplicate records filtered out by the QUALIFY clause.
- `silver_rows` — Number of rows in the silver dynamic table (should equal `bronze_unique_vins`).
- `bronze_to_silver_drift` — Difference between unique VINs and silver rows (should be 0).
- `gold_groups` — Number of MAKE/EV_TYPE aggregation groups.
- `gold_total_vehicles` — Sum of all vehicles across groups.
- `silver_to_gold_drift` — Difference (should be 0).
- `status` — PASS or DRIFT_DETECTED.

---

## 8. Data Lineage & Auditability

### V_PIPELINE_LINEAGE (View)
Built on `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY`, this view provides **column-level data lineage** for all write operations in the pipeline over the last 14 days. For every DML that modified a table in EV_PROJECT_DB, it shows:
- The **source object** (where data was read from).
- The **target object** (where data was written to).
- The **specific columns** modified.
- The **user** who executed the operation and the **query ID** for full reproducibility.

This enables answering questions like "Which source populated the MAKE column in gold?" or "When was the last time RAW_EV_DATA was written to, and by which process?"

### V_DQ_AUDIT (View)
Surfaces all DMF measurement results from `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` for the EV_PROJECT_DB database. Each row represents a single metric evaluation with:
- The **measurement time** and **scheduled time** (to detect delays).
- The **DMF name** and **arguments** (which column was checked).
- The **metric value** (the actual result — e.g., 0 nulls, 5 duplicates, 2-minute freshness).
- The **change commit time** (when the underlying data change occurred).

This view enables **trend analysis** over time: plot duplicate counts over days to detect degrading source quality, or chart freshness intervals to identify ingestion slowdowns before they become outages.

---

## 9. Error Handling & Quarantine

### Error Detection Architecture
Rather than silently discarding bad data, the pipeline captures every quality violation into dedicated quarantine tables for analyst review. Error detection is **event-driven** — it runs immediately after each ingestion via a task DAG:

```
TSK_INGEST_EV_DATA (root, WHEN stream has data)
  └→ TSK_ERROR_DETECTION (AFTER ingest) → calls SP_DETECT_ERRORS
       └→ TSK_ERROR_NOTIFICATION (AFTER detection) → calls SP_NOTIFY_ERRORS → email alert
```

This approach is superior to a fixed-schedule task because:
- **Zero latency**: Errors are detected seconds after new data arrives, not up to 30 minutes later.
- **Zero waste**: No compute is consumed when no new data is ingested.
- **Causal ordering**: Errors are always detected in the same transaction boundary as the data that caused them.

### Error Tables

**ERROR_ROWS** — Captures individual rows that violate quality rules. Each row includes:
- `ERROR_TYPE` — The specific violation (NULL_VIN, INVALID_RANGE, NEGATIVE_MSRP, ORPHAN_MAKE, NULL_CRITICAL_FIELD).
- `SOURCE_LAYER` / `SOURCE_TABLE` — Where the error was detected (BRONZE or SILVER).
- `ERROR_DESCRIPTION` — Human-readable explanation.
- Full row data (VIN, MAKE, MODEL, etc.) for analyst investigation.
- `RAW_RECORD` (VARIANT) — For bronze-level errors, preserves the original JSON for forensic analysis.
- `DETECTED_AT` — Timestamp for trend analysis.

**DUPLICATE_ROWS** — Tracks VINs that appear multiple times in bronze. Includes occurrence count and the list of source files (as ARRAY) that contributed each duplicate. This helps trace whether duplicates came from the same file loaded twice or from genuinely overlapping source data.

### SP_DETECT_ERRORS
A SQL stored procedure that scans both layers for six error types:
1. **Duplicate VINs** in bronze (before the QUALIFY dedup filter removes them).
2. **Null VINs** — Records rejected from silver by the WHERE clause.
3. **Invalid electric range** — Range ≤ 0 in silver.
4. **Negative MSRP** — BASE_MSRP < 0 in silver.
5. **Orphan MAKEs** — MAKE not found in DIM_MANUFACTURERS_GOLD.
6. **Null critical fields** — MAKE or MODEL is null in silver.

Each insert is idempotent — it only adds rows not already present in the error table, preventing duplicates on re-runs.

### Email Notifications
**EV_DQ_EMAIL_INT** — A Snowflake email notification integration. When `SP_NOTIFY_ERRORS` detects new rows in the error/duplicate streams, it sends an email alert with:
- Count of new errors and duplicates.
- Breakdown by error type.
- Ready-to-run query for investigation.

### Analyst Dashboard Views

**V_DQ_DASHBOARD** — The main summary view combining error counts (total, last 24h, last 1h), duplicate statistics, and cross-layer reconciliation status in a single query. Designed for a Snowsight dashboard tile.

**V_ERROR_TREND** — Hourly error counts grouped by error type and source layer. Designed for time-series line charts to spot degrading data quality over time.

**V_TOP_OFFENDERS** — Ranks manufacturers by total quality issues, broken down by error type. Helps analysts prioritize which data sources or MAKEs need attention.

---

## 9. End-to-End Data Flow

```
[GCS Bucket] → (Pub/Sub notification) → [GCP_EV_STAGE directory refresh]
     ↓
[GCS_FILES_STREAM] detects new files
     ↓
[TSK_INGEST_EV_DATA] fires → calls [SP_INGEST_RAW_EV_DATA]
     ↓                                    ↓
[RAW_EV_DATA] (Bronze)              [TSK_ERROR_DETECTION] (AFTER ingest)
     ↓                              ↑          ↓
[CLEAN_EV_DATA_DT] auto-refreshes   [DIM_MANUFACTURERS_GOLD]   [TSK_ERROR_NOTIFICATION]
(Silver, incremental + dedup)        ← NeonDB PostgreSQL              ↓
     ↓                                                          Email alert sent
[CLEAN_EV_DATA_DT_STREAM] captures new rows
     ↓
[TASK_SILVER_TO_GOLD] fires → calls [SP_TRANSFORM_SILVER_TO_GOLD]
     ↓
[FACT_EV_MARKET_METRICS] (Gold, Iceberg on GCS)
     ↓
[DATA_QUALITY DMFs] validate every layer automatically
     ↓
[ERROR_ROWS] + [DUPLICATE_ROWS] — bad data quarantine
[V_DQ_DASHBOARD] — analyst summary
[V_ERROR_TREND] — time-series quality metrics
[V_TOP_OFFENDERS] — MAKEs ranked by issues
[V_ROW_COUNT_RECONCILIATION] — cross-layer consistency
[V_PIPELINE_LINEAGE] — who wrote what, when
[V_DQ_AUDIT] — historical DMF results
```

---

## 10. Best Practices Summary

| Practice | Implementation |
|---|---|
| **Medallion Architecture** | Bronze (raw) → Silver (clean) → Gold (aggregated) with clear schema boundaries |
| **Event-Driven Processing** | Pub/Sub + Streams + Tasks ensure zero-waste compute |
| **Incremental Processing** | Dynamic table with INCREMENTAL refresh; only new data is processed |
| **Open Table Format** | Iceberg on GCS enables multi-engine access without vendor lock-in |
| **Separation of Concerns** | Each object has a single responsibility; schemas enforce layer boundaries |
| **Immutable Audit Trail** | Bronze preserves raw JSON; lineage view tracks all modifications |
| **Native Data Quality** | DMFs run automatically with results persisted for historical analysis |
| **Cross-Layer Validation** | Row count reconciliation ensures no data loss between layers |
| **Referential Integrity** | Multi-table DMF validates foreign key relationships across schemas |
| **External Data Integration** | PostgreSQL connector uses CDC for low-impact replication |
| **Security** | Storage integration uses IAM (no stored credentials); SSL required for PostgreSQL |
| **Cost Optimization** | Tasks only fire when data exists; DMFs trigger only on changes |
| **Explicit Deduplication** | QUALIFY ROW_NUMBER() in silver ensures unique VINs; duplicates tracked in DUPLICATE_ROWS |
| **Error Quarantine** | Bad rows captured in ERROR_ROWS with full context for analyst review |
| **Event-Driven Error Detection** | Error detection task chains AFTER ingestion, not on fixed schedule — zero latency, zero waste |
| **Automated Alerting** | Email notifications sent immediately when new errors are detected via task DAG |
| **Analyst Dashboards** | Pre-built views (V_DQ_DASHBOARD, V_ERROR_TREND, V_TOP_OFFENDERS) for quality monitoring |

---

## 11. Why dbt Is Not Recommended for This Pipeline

### Overview
dbt (data build tool) is a widely adopted transformation framework that compiles SQL models, manages dependencies, and provides built-in testing. While it excels in many data engineering scenarios, this pipeline's architecture is specifically designed around Snowflake-native capabilities that make dbt redundant — and in some cases, inferior.

This section explains, layer by layer, why the current Snowflake-native approach was chosen over dbt.

### Bronze Layer — Ingestion

**dbt cannot handle data ingestion.** dbt operates exclusively on data already inside the warehouse — it has no concept of external stages, COPY INTO, file formats, or Snowpipe. The bronze layer requires:
- An external stage connected to GCS via a storage integration.
- A directory stream that detects new files via Pub/Sub notifications.
- A task that fires a stored procedure to execute `COPY INTO`.

None of these capabilities exist in dbt. The ingestion layer must remain Snowflake-native regardless of any downstream tooling choice.

### Silver Layer — Transformation

This is where dbt would typically be considered. The silver layer flattens raw JSON into typed columns, filters null VINs, and deduplicates by VIN. A dbt incremental model could theoretically handle this, but the dynamic table is superior in every dimension:

| Capability | Dynamic Table (Current) | dbt Incremental Model |
|---|---|---|
| **Scheduling** | Fully automatic — Snowflake manages refresh based on `TARGET_LAG = '1 MINUTE'` | Requires an external orchestrator (Snowflake Task, Airflow, cron, or dbt Cloud) to trigger `dbt run` |
| **Incremental logic** | Automatic — Snowflake internally tracks which bronze rows are new and processes only those | Manual — the developer must write `{% if is_incremental() %}` Jinja blocks with explicit `WHERE` clauses to filter new records |
| **Latency** | Sub-minute — data is available in silver within 1 minute of landing in bronze | Depends entirely on the orchestrator's schedule; typically 5–60 minutes |
| **Stream support** | Native — a stream on the dynamic table captures row-level changes, enabling event-driven downstream processing | Not available — dbt models are static tables/views with no change tracking; triggering downstream actions requires additional infrastructure |
| **Deduplication** | `QUALIFY ROW_NUMBER() OVER (...)` is confirmed compatible with incremental refresh — Snowflake optimizes this natively | Supported via `QUALIFY` in dbt SQL, but incremental dedup requires careful `unique_key` configuration and can cause full table scans on merge |
| **Maintenance** | Zero — no Jinja, no YAML config, no model files; the transformation is a single SQL statement | Requires maintaining `.sql` model files, `schema.yml` configs, `dbt_project.yml`, `profiles.yml`, and Jinja macros |
| **Failure recovery** | Automatic — if a refresh fails, Snowflake retries transparently | Manual — failed `dbt run` requires re-triggering, investigating logs, and potentially running `dbt retry` |

**Key insight:** The dynamic table eliminates the entire category of problems that dbt was originally built to solve — scheduling, incremental logic, and dependency management. It does so with less code, lower latency, and zero operational overhead.

### Gold Layer — Aggregation

The gold layer aggregates silver data into `FACT_EV_MARKET_METRICS` (an Iceberg table) using a Snowpark stored procedure triggered by a stream-based task. A dbt model could express this aggregation, but it would provide no practical advantage:

- **dbt's dependency graph** is unnecessary here — there is exactly one upstream dependency (the silver dynamic table), and the stream + task pattern already handles this reactively.
- **dbt's `ref()` function** resolves model dependencies at compile time, but the current pipeline resolves dependencies at data-change time (via streams), which is strictly more responsive.
- **dbt cannot write to Iceberg tables** with external volume configurations — the `CREATE OR REPLACE ICEBERG TABLE` DDL with `EXTERNAL_VOLUME`, `CATALOG`, and `BASE_LOCATION` parameters is not expressible in dbt's materializations. A custom materialization would be required, adding significant complexity.
- **The truncate-and-reload pattern** used by the gold SP is straightforward in a stored procedure but awkward in dbt (requires a custom `pre-hook` to truncate before insert).

### Data Quality — DMFs vs. dbt Tests

dbt provides built-in tests (`unique`, `not_null`, `accepted_values`, `relationships`) and supports custom tests via SQL. However, Snowflake's Data Metric Functions (DMFs) are categorically more powerful for this pipeline:

| Capability | DMFs (Current) | dbt Tests |
|---|---|---|
| **Execution model** | Continuous — run automatically on schedule or on data changes (`TRIGGER_ON_CHANGES`) | Batch — run only during `dbt test` invocations |
| **Historical results** | Persisted automatically in `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` with timestamps | Not persisted — tests pass or fail at run time; historical tracking requires a custom solution (e.g., `elementary` package) |
| **Cross-table validation** | Native — multi-table DMFs like `ORPHAN_MAKE_CHECK` can reference any table as an argument | Limited — `relationships` test supports basic FK checks, but custom cross-table logic requires singular tests with hardcoded queries |
| **Statistical monitoring** | Built-in `AVG`, `MIN`, `MAX`, `STDDEV` DMFs track metric drift over time | Not available — no equivalent to continuous statistical monitoring |
| **Freshness monitoring** | Built-in `FRESHNESS` DMF with automatic measurement | `dbt source freshness` exists but only checks source tables, not downstream models, and requires explicit scheduling |
| **Alerting** | Can trigger email notifications via streams on error tables | No native alerting — requires integration with external tools |
| **Anomaly detection** | DMFs support anomaly detection sensitivity levels (future capability) | Not available natively |

**Key insight:** dbt tests are assertions that gate a build pipeline — they answer "should I proceed?" DMFs are continuous monitors that answer "is my data healthy right now?" For a production pipeline that needs ongoing observability, DMFs are the superior choice.

### Orchestration — Streams + Tasks vs. dbt DAG

dbt's directed acyclic graph (DAG) resolves model dependencies at compile time: model B depends on model A, so dbt builds A first. This is powerful for complex transformation layers with dozens of interdependent models.

This pipeline has exactly three layers with linear dependencies:
```
Bronze → Silver (automatic via dynamic table) → Gold (triggered via stream + task)
```

Introducing dbt's DAG here would:
1. **Add an external scheduler** where none is currently needed — the pipeline is fully self-orchestrating.
2. **Replace event-driven triggers with time-based schedules** — dbt runs on a cron or interval, whereas streams fire only when data actually changes.
3. **Lose the sub-minute latency** — dbt runs take time to compile, resolve dependencies, and execute; the current pipeline propagates data in under a minute.
4. **Require a deployment mechanism** — dbt projects need to be deployed (via `dbt run`, dbt Cloud, or Snowflake's native `CREATE DBT PROJECT`), adding operational complexity.

### When dbt WOULD Be Recommended

dbt would be the right choice if this pipeline evolved into:
- **A multi-team environment** with 20+ data engineers contributing models that need PR-based review and CI/CD testing before deployment.
- **A complex transformation DAG** with dozens of intermediate models, staging layers, and cross-domain joins where dbt's `ref()` and dependency resolution provide genuine value.
- **A multi-platform deployment** where the same transformation logic needs to run on Snowflake, BigQuery, and Redshift — dbt's adapter system abstracts cross-database SQL differences.
- **A scenario requiring environment promotion** (dev → staging → prod) with different datasets — dbt's `target` system handles this natively.

### Conclusion

The current pipeline leverages Snowflake-native features (dynamic tables, streams, tasks, DMFs) that together deliver what dbt provides — scheduling, incremental logic, dependency management, testing, and documentation — but with lower latency, zero external dependencies, continuous monitoring, and less operational overhead. dbt was originally built to fill gaps in warehouse capabilities that Snowflake has since filled natively. For a focused, three-layer pipeline like this one, the Snowflake-native approach is both simpler and more performant.

---

## 12. Data Sharing & Cross-Engine Access

The pipeline supports three data distribution channels, each targeting a different consumer type:

### 12.1 Secure Data Sharing — Snowflake Account Consumers (Zero-Copy)

Snowflake's Secure Data Sharing enables sharing live data with other Snowflake accounts without copying data. Consumers query the provider's data in place — there is no ETL, no data movement, and no storage duplication.

#### Architecture

The pipeline exposes data through a dedicated `SHARING` schema containing **secure views** — not raw tables. Secure views are critical because:
- **Query pushdown protection**: Consumers cannot reverse-engineer the underlying SQL or access tables not explicitly granted.
- **Column filtering**: Only business-relevant columns are exposed; internal metadata (SOURCE_FILE, error details) is hidden.
- **Data quality transparency**: A dedicated secure view (`SV_DATA_QUALITY_SUMMARY`) lets consumers see the pipeline's health status, building trust.

#### Shared Objects

| Secure View | Source | What Consumers See |
|---|---|---|
| `SV_FACT_EV_MARKET_METRICS` | Gold Iceberg table | MAKE, EV_TYPE, TOTAL_VEHICLES, AVG_RANGE, MAX_MSRP, LOAD_TIMESTAMP |
| `SV_DIM_MANUFACTURERS` | Gold dimension table | MANUFACTURER_ID, MANUFACTURER_NAME, COUNTRY |
| `SV_DATA_QUALITY_SUMMARY` | DQ dashboard view | Error types, counts, reconciliation status |

#### Share: EV_MARKET_DATA_SHARE

The share (`EV_MARKET_DATA_SHARE`) bundles these secure views into a single distributable unit. To add a Snowflake consumer account:

```sql
ALTER SHARE EV_MARKET_DATA_SHARE ADD ACCOUNTS = <consumer_account_locator>;
```

The consumer then creates a database from the share in their account:

```sql
CREATE DATABASE EV_SHARED_DATA FROM SHARE <provider_account>.<share_name>;
```

**Key benefit**: Data is always live — consumers see the latest gold layer data within seconds of a refresh, with zero replication lag.

### 12.2 Reader Account — Non-Snowflake Users

For consumers who do not have their own Snowflake account, the pipeline provisions a **Reader Account** (also called a Managed Account). This is a Snowflake account created and paid for by the provider, giving external users a read-only SQL interface to the shared data.

#### Reader Account Details

| Property | Value |
|---|---|
| Account Name | `EV_DATA_READER` |
| Account Locator | `UA12095` |
| URL | `https://bovwcbf-ev_data_reader.snowflakecomputing.com` |
| Access | Read-only access to all views in EV_MARKET_DATA_SHARE |

External users log in to the reader account URL, run SQL queries against the shared views, and see live data. The provider controls:
- **Compute costs**: The reader account uses a provider-funded warehouse.
- **Access scope**: Only the views in the share are visible — no access to bronze, silver, or internal objects.
- **User management**: The provider can create/drop users in the reader account.

#### Use Cases
- External analysts or consultants who need ad-hoc query access.
- Partner organizations without their own Snowflake environment.
- Regulatory or audit bodies requiring read-only access to quality metrics.

### 12.3 Catalog Sync — Non-Snowflake Query Engines (Spark, Trino, BigQuery)

The gold layer's `FACT_EV_MARKET_METRICS` is an Apache Iceberg table with data stored as Parquet files on GCS. However, with `CATALOG = 'SNOWFLAKE'` (Snowflake-managed), the Iceberg metadata is inside Snowflake's internal catalog — invisible to external engines.

**Catalog Sync** publishes Snowflake's Iceberg metadata to an external catalog (**Snowflake Open Catalog / Polaris**), making the table discoverable and queryable by any Iceberg-compatible engine.

#### How It Works

1. **Snowflake writes** Parquet data files and Iceberg metadata to GCS (already happening via `GCP_ICEBERG_VOLUME`).
2. **Catalog Sync** pushes metadata pointers to the external Open Catalog instance.
3. **External engines** (Spark, Trino, BigQuery, Presto) connect to Open Catalog via the **Iceberg REST catalog protocol** and read the Parquet files directly from GCS.

#### Setup Steps (requires a Snowflake Open Catalog account)

```sql
-- Step 1: Create catalog integration
CREATE OR REPLACE CATALOG INTEGRATION EV_OPEN_CATALOG_INT
  CATALOG_SOURCE = POLARIS
  TABLE_FORMAT = ICEBERG
  REST_CONFIG = (
    CATALOG_URI = 'https://<org>-<open-catalog-account>.snowflakecomputing.com/polaris/api/catalog'
    CATALOG_NAME = '<external_catalog_name>'
  )
  REST_AUTHENTICATION = (
    TYPE = OAUTH
    OAUTH_CLIENT_ID = '<client_id>'
    OAUTH_CLIENT_SECRET = '<client_secret>'
    OAUTH_ALLOWED_SCOPES = ('PRINCIPAL_ROLE:ALL')
  )
  ENABLED = TRUE;

-- Step 2: Enable sync on the GOLD schema
ALTER SCHEMA EV_PROJECT_DB.GOLD SET CATALOG_SYNC = 'EV_OPEN_CATALOG_INT';
```

After this, every change to `FACT_EV_MARKET_METRICS` is automatically synced to Open Catalog. External engines query the table without any Snowflake credentials.

#### Comparison of Sharing Methods

| Method | Consumer Type | Data Movement | Latency | Cost to Provider |
|---|---|---|---|---|
| **Secure Share** | Snowflake accounts | Zero-copy | Real-time | None (consumer pays compute) |
| **Reader Account** | Non-Snowflake users | Zero-copy | Real-time | Provider pays compute |
| **Catalog Sync** | Spark, Trino, BigQuery | None (read from GCS) | Seconds after sync | GCS egress only |

---

## 13. Analytics, Semantic Model & Conversational AI

### 13.1 Four Key Insights from the EV Population Data

The following insights were derived from the enriched gold table `FACT_EV_REGISTRATIONS` (4,986 unique vehicles):

**Insight 1: BEV Dominates the Market**
Battery Electric Vehicles (BEVs) represent 59.8% of all registrations, with Plug-in Hybrid Electric Vehicles (PHEVs) at 40.2%. The market is clearly shifting toward fully electric powertrains.

**Insight 2: Tesla Leads but the Market Is Diversifying**
Tesla holds 19.6% market share (977 vehicles) — nearly double the next competitor, Chevrolet (11.1%). However, with 35 distinct manufacturers represented, the market is increasingly competitive. Tesla also leads in average range (152 miles), far ahead of Chevrolet (73 miles) and Ford (17 miles).

**Insight 3: 45.5% of EVs Are CAFV Incentive-Eligible**
Of all registrations, 45.5% qualify for Clean Alternative Fuel Vehicle incentives. A significant 30.5% have unknown eligibility (battery range not yet researched), representing an opportunity for data enrichment. 24% are ineligible due to low battery range (primarily PHEVs).

**Insight 4: Explosive Growth Followed by a Data Correction**
EV registrations grew 48% YoY in 2021 and 63.3% in 2022, reflecting accelerating adoption. The 2023 drop (-60.4%) likely reflects incomplete data for that year rather than an actual market decline, an important caveat for business users.

### 13.2 Enriched Gold Fact Table

`FACT_EV_REGISTRATIONS` extends the pipeline's silver data with additional dimensions not present in the aggregated `FACT_EV_MARKET_METRICS`:

| Column | Description |
|---|---|
| VIN | Unique Vehicle Identification Number |
| MAKE, MODEL, MODEL_YEAR | Vehicle identity |
| EV_TYPE | BEV or PHEV |
| CAFV_ELIGIBILITY | Incentive eligibility status |
| ELECTRIC_RANGE, BASE_MSRP | Vehicle specifications |
| CITY, COUNTY, STATE, ZIP_CODE | Geographic dimensions |
| LEGISLATIVE_DISTRICT | Political geography |
| ELECTRIC_UTILITY | Energy provider |
| CENSUS_TRACT_2020 | Demographic linkage |

This table enables the full range of executive, sales, and marketing queries that the semantic model supports.

### 13.3 Semantic Model — Cortex Analyst

The semantic model is a YAML file (`@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS/ev_semantic_model.yaml`) that describes the gold layer's tables, dimensions, measures, and verified queries for Snowflake's Cortex Analyst service.

#### Structure

The model defines two tables:
- **fact_ev_registrations** — 13 dimensions, 1 time dimension, 12 measures
- **dim_manufacturers** — 3 dimensions (manufacturer ID, name, country)

#### Dimensions (fact table)
VIN, MAKE, MODEL, MODEL_YEAR, EV_TYPE, CAFV_ELIGIBILITY, CITY, COUNTY, STATE, ZIP_CODE, LEGISLATIVE_DISTRICT, ELECTRIC_UTILITY, CENSUS_TRACT

#### Measures
| Measure | Expression | Description |
|---|---|---|
| total_registrations | COUNT(VIN) | Total registered EVs |
| avg_electric_range | AVG(ELECTRIC_RANGE) | Average miles per charge |
| max_electric_range | MAX(ELECTRIC_RANGE) | Best range observed |
| avg_base_msrp | AVG(BASE_MSRP) | Average retail price |
| unique_models | COUNT(DISTINCT MODEL) | Model variety |
| unique_manufacturers | COUNT(DISTINCT MAKE) | Brand diversity |
| cafv_eligible_count | COUNT(CASE WHEN eligible...) | Incentive-eligible vehicles |
| cafv_eligible_pct | Eligible / Total * 100 | Eligibility rate |
| bev_count / phev_count | COUNT by type | Type-specific counts |
| bev_market_share | BEV / Total * 100 | BEV penetration |
| market_share_pct | Group / Total * 100 | Relative market share |

#### Verified Queries (7)
Pre-validated SQL queries that Cortex Analyst uses as ground truth:
1. YoY growth trend in EV registrations
2. BEV vs PHEV market penetration
3. Tesla vs other manufacturers by state
4. CAFV incentive eligibility breakdown
5. Top vehicle models by region
6. EV adoption rates by state
7. Market share by manufacturer

Each verified query includes the SQL, the question it answers, and verification metadata. Cortex Analyst prioritizes these when it detects a matching user question.

### 13.4 Streamlit Chat Interface

A Streamlit-in-Snowflake (SiS) app (`EV_PROJECT_DB.GOLD.EV_MARKET_CHAT`) provides a conversational interface for business users:

#### Features
- **Natural language queries**: Users type questions in plain English; Cortex Analyst translates them to SQL.
- **Auto-visualization**: Query results are displayed as tables with automatic bar charts for numeric data.
- **SQL transparency**: An expandable "View SQL" panel shows the generated query for technical users.
- **Sidebar metrics**: Key KPIs (total EVs, BEV share, CAFV eligibility, manufacturer count) are always visible.
- **Suggested questions**: Pre-built question buttons in the sidebar for quick exploration.
- **Multi-turn conversation**: Full chat history is maintained, enabling follow-up questions.
- **Suggestion chips**: Cortex Analyst suggests related questions after each response.

#### Access
The app is available at: Snowsight → Projects → Streamlit → EV_MARKET_CHAT

### 13.5 Agent Integration Considerations

#### Cortex Agents with Tool-Calling Capabilities
The semantic model is designed to be consumed by Snowflake's Cortex Agents, which extend Cortex Analyst with tool-calling capabilities. A Cortex Agent could:

- **Semantic model tool**: Use the EV semantic model as a data retrieval tool, translating natural language to SQL exactly as the Streamlit app does.
- **Cortex Search tool**: Pair with a Cortex Search service over manufacturer documentation or regulatory text to answer questions like "What are the CAFV eligibility requirements for PHEVs in Washington state?"
- **Python tool**: Call custom functions to run statistical analysis, generate forecasts (using Snowflake ML), or trigger pipeline actions.
- **Multi-tool orchestration**: An agent could answer "Which manufacturers are losing market share and what's their warranty policy?" by calling the semantic model for market data and a search service for warranty documents — in a single response.

#### Integration with External Systems (CRM, ERP)

The semantic model and agent architecture can be extended to external systems:

- **CRM Integration** (e.g., Salesforce): Ingest CRM data (dealer inventory, customer demographics, lead scores) into a new gold table via External Access Integration + scheduled SP. The semantic model can then answer questions like "Which dealers have the most Tesla inventory in WA?" by joining CRM data with EV registrations.
- **ERP Integration** (e.g., SAP): Pull supply chain data (parts availability, delivery timelines) to correlate with registration demand. "Are there supply chain bottlenecks for the top 3 selling models?"
- **API Gateway**: Expose the Cortex Analyst endpoint via Snowflake's External Functions or the REST API, enabling chatbots, Slack bots, or custom web apps to query the semantic model programmatically.

#### Multi-Turn Conversational Analytics

The Streamlit app already supports multi-turn conversations by maintaining chat history. To enhance this for production:

- **Context window management**: The app passes full conversation history to Cortex Analyst, enabling follow-ups like "Now break that down by state" without repeating the original question.
- **Session memory**: Cortex Analyst understands pronoun references ("those manufacturers", "that region") based on prior turns.
- **Guardrails**: The semantic model constrains Cortex Analyst to only query the defined tables and measures — it cannot access bronze/silver data, error tables, or any object outside the model definition.
- **Audit trail**: Every query generated by Cortex Analyst is logged in `ACCESS_HISTORY`, providing full lineage from natural language question to SQL to data accessed.

