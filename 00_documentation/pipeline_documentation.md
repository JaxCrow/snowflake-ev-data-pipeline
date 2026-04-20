# EV Data Pipeline — Technical Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Data Flow](#data-flow)
4. [Layer Details](#layer-details)
5. [Transformation Approaches](#transformation-approaches)
6. [Orchestration](#orchestration)
7. [Data Quality](#data-quality)
8. [Open Table Formats (Iceberg)](#open-table-formats-iceberg)
9. [Data Sharing](#data-sharing)
10. [Semantic Model & Conversational Analytics](#semantic-model--conversational-analytics)
11. [Cost Governance](#cost-governance)
12. [Deployment Guide](#deployment-guide)
13. [Operational Runbook](#operational-runbook)
14. [Design Decisions & Trade-offs](#design-decisions--trade-offs)

---

## Overview

An end-to-end Snowflake-native data engineering pipeline that ingests electric vehicle registration data from Google Cloud Storage, transforms it through a medallion architecture, and surfaces insights via a conversational analytics interface powered by Cortex Analyst.

**Domain:** Electric vehicle registrations (~22,000 raw records, ~4,986 unique vehicles)
**Cloud:** GCP (GCS + Pub/Sub) + Snowflake
**Database:** `EV_PROJECT_DB`
**Account:** `dr77061` (GCP_US_CENTRAL1)

### Key Capabilities
- Event-driven ingestion with zero idle compute cost
- Sub-minute data freshness via Dynamic Tables
- Three transformation engines: Dynamic Tables, Snowpark Python, dbt
- Open-format interoperability via Apache Iceberg
- Comprehensive data quality with 5 validation types
- Cross-account data sharing with governance
- Natural language analytics via Cortex Analyst + Streamlit

---

## Architecture

### Medallion Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    BRONZE    │     │    SILVER    │     │     GOLD     │
│  Raw JSON    │────>│ Dynamic Table│────>│ Snowpark +   │
│  (VARIANT)   │     │ (Incremental)│     │ dbt Models   │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                          ┌───────────────────────┼───────────────────────┐
                          │                       │                       │
                   ┌──────▼──────┐    ┌──────────▼────────┐   ┌─────────▼────────┐
                   │   ICEBERG   │    │     SHARING       │   │  CORTEX ANALYST  │
                   │ Parquet/GCS │    │  Secure Views +   │   │  + Streamlit     │
                   │ Open Format │    │  Outbound Share   │   │  Chat Interface  │
                   └─────────────┘    └───────────────────┘   └──────────────────┘
```

### Schema Layout

| Schema | Purpose | Object Count |
|--------|---------|-------------|
| `BRONZE` | Raw ingestion, stage, stream, tasks | 7 |
| `SILVER` | Cleansed + deduplicated data | 2 |
| `GOLD` | Business-ready tables, Snowpark SP, Streamlit | 7 |
| `ICEBERG` | Open-format copies on GCS | 3 |
| `DBT_GOLD` | dbt-managed transformation output | 3 |
| `DATA_QUALITY` | Error quarantine, monitoring views | 12 |
| `SHARING` | Governed external access | 3 |

---

## Data Flow

### End-to-End Path

```
1. JSON file lands in GCS bucket (gcs://ev-landing-zone-lordrivas/landing/)
2. GCP Pub/Sub sends notification to Snowflake (GCP_EV_PUBSUB_INT)
3. Directory stream (GCS_FILES_STREAM) detects new file
4. Root task (TSK_INGEST_EV_DATA) fires — checks WHEN SYSTEM$STREAM_HAS_DATA
5. Snowpark SP (SP_INGEST_RAW_EV_DATA) runs COPY INTO → RAW_EV_DATA
6. Chained task (TSK_ERROR_DETECTION) fires → Snowpark DQ SP
7. Chained task (TSK_ERROR_NOTIFICATION) fires → email alert if errors found
8. Dynamic Table (CLEAN_EV_DATA_DT) auto-refreshes within 1 minute
9. Stream on DT triggers TASK_SILVER_TO_GOLD
10. Snowpark SP aggregates Silver → Gold (FACT_EV_MARKET_METRICS)
11. Iceberg tables are synced from Gold (manual or post-demo)
12. Cortex Analyst queries Iceberg tables via semantic model
13. Streamlit app presents results to business users
```

### Latency Profile

| Stage | Latency | Mechanism |
|-------|---------|-----------|
| GCS → Bronze | ~30 seconds | Pub/Sub + Stream + Task (1-min check) |
| Bronze → Silver | ~1 minute | Dynamic Table target_lag |
| Silver → Gold | ~30 seconds | Stream-triggered task |
| Gold → Iceberg | Manual sync | INSERT INTO (post-pipeline) |
| Query → Answer | ~2-5 seconds | Cortex Analyst + Streamlit |

---

## Layer Details

### Bronze Layer (`EV_PROJECT_DB.BRONZE`)

**Purpose:** Ingest and store raw data as an immutable audit trail.

| Object | Type | Description |
|--------|------|-------------|
| `GCP_EV_STAGE` | External Stage | Points to GCS bucket, directory enabled, auto-refresh via Pub/Sub |
| `GCS_FILES_STREAM` | Stream (Stage) | Detects new file arrivals in the stage directory |
| `RAW_EV_DATA` | Table | Raw JSON stored as VARIANT with source file metadata |
| `SP_INGEST_RAW_EV_DATA` | SP (Snowpark Python) | COPY INTO with ON_ERROR=ABORT_STATEMENT (atomic) |
| `TSK_INGEST_EV_DATA` | Task (Root) | 1-min schedule, WHEN SYSTEM$STREAM_HAS_DATA guard |
| `TSK_ERROR_DETECTION` | Task (Chained) | AFTER ingestion, calls Snowpark DQ SP |
| `TSK_ERROR_NOTIFICATION` | Task (Chained) | AFTER detection, sends email alerts |

**Schema:**
```
RAW_EV_DATA
├── JSON_DATA          VARIANT     -- Full JSON payload
├── SOURCE_FILE        VARCHAR     -- GCS file path
├── SOURCE_FILE_ROW    NUMBER      -- Row number within file
└── LOAD_TIMESTAMP     TIMESTAMP   -- Ingestion time (default CURRENT_TIMESTAMP)
```

**Design Decision:** Raw JSON stored as VARIANT (not parsed) preserves the original data. If the source schema changes, Bronze absorbs it without breaking. Reprocessing is always possible from Bronze without touching the source.

### Silver Layer (`EV_PROJECT_DB.SILVER`)

**Purpose:** Cleanse, parse, validate, and deduplicate data.

| Object | Type | Description |
|--------|------|-------------|
| `CLEAN_EV_DATA_DT` | Dynamic Table | JSON flatten + type cast + null rejection + dedup |
| `CLEAN_EV_DATA_DT_STREAM` | Stream | Tracks changes for Gold task trigger |

**Transformation Logic:**
1. `LATERAL FLATTEN(input => JSON_DATA:data)` — Explodes nested JSON array
2. Positional array access (`f.value[8]::VARCHAR AS VIN`) — Type casting
3. `WHERE f.value[8] IS NOT NULL` — Rejects null VINs
4. `QUALIFY ROW_NUMBER() OVER (PARTITION BY VIN ORDER BY SOURCE_FILE DESC) = 1` — Dedup (latest file wins)

**Configuration:**
- `TARGET_LAG = '1 minute'` — Sub-minute freshness
- `REFRESH_MODE = INCREMENTAL` — Processes only new/changed rows
- `INITIALIZE = ON_CREATE` — Backfills existing data on creation

**Output:** 4,986 unique vehicle records from ~22,000 raw records (17,197 duplicates removed).

### Gold Layer (`EV_PROJECT_DB.GOLD`)

**Purpose:** Create business-ready aggregates, dimensions, and fact tables.

| Object | Type | Description |
|--------|------|-------------|
| `FACT_EV_REGISTRATIONS` | Table | Individual vehicle registrations (4,986 rows) |
| `FACT_EV_MARKET_METRICS` | Table | Aggregated by MAKE x EV_TYPE (46 rows) |
| `DIM_MANUFACTURERS_GOLD` | Table | Manufacturer dimension from PostgreSQL (35 rows) |
| `SP_TRANSFORM_SILVER_TO_GOLD` | SP (Snowpark Python) | DataFrame aggregation |
| `TASK_SILVER_TO_GOLD` | Task | Stream-triggered |
| `SEMANTIC_MODELS` | Internal Stage | Hosts semantic model YAML + Streamlit files |
| `EV_MARKET_CHAT` | Streamlit App | Chat interface for Cortex Analyst |

**Snowpark SP Logic:**
```python
df_silver = session.table("EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT")
df_gold = df_silver.group_by("MAKE", "EV_TYPE").agg(
    count("VIN").alias("TOTAL_VEHICLES"),
    avg("ELECTRIC_RANGE").alias("AVG_RANGE"),
    max_("BASE_MSRP").alias("MAX_MSRP")
).with_column("LOAD_TIMESTAMP", current_timestamp())
```

### Iceberg Layer (`EV_PROJECT_DB.ICEBERG`)

**Purpose:** Store Gold data in open table format for cross-engine interoperability.

| Object | Type | Storage |
|--------|------|---------|
| `FACT_EV_REGISTRATIONS` | Iceberg Table | Parquet on GCS via GCP_ICEBERG_VOLUME |
| `FACT_EV_MARKET_METRICS` | Iceberg Table | Parquet on GCS via GCP_ICEBERG_VOLUME |
| `DIM_MANUFACTURERS_GOLD` | Iceberg Table | Parquet on GCS via GCP_ICEBERG_VOLUME |

**Access Methods:**
- Snowflake SQL (standard queries)
- Iceberg REST Catalog (Spark, Trino, Flink, Dremio)
- Direct Parquet read from GCS

### DBT Gold Layer (`EV_PROJECT_DB.DBT_GOLD`)

**Purpose:** Demonstrate dbt-managed, testable SQL transformations as an alternative to Snowpark.

| Object | Type | Description |
|--------|------|-------------|
| `STG_EV_REGISTRATIONS` | View | Staging view over Silver Dynamic Table |
| `FACT_EV_REGISTRATIONS` | Table | dbt-built registrations (4,967 rows) |
| `FACT_EV_MARKET_METRICS` | Table | dbt-built aggregates |

**Tests (10 passing):**
- `unique` + `not_null` on VIN (staging + gold)
- `not_null` on MAKE, MODEL_YEAR, ELECTRIC_RANGE (gold fact)
- `not_null` on TOTAL_VEHICLES, MAKE, EV_TYPE (gold metrics)

---

## Transformation Approaches

Three engines are used deliberately to demonstrate when each is appropriate:

### Dynamic Tables (Silver)
- **Use case:** Near real-time cleansing with automatic scheduling
- **Strengths:** Zero orchestration code, incremental processing, built-in retry, sub-minute lag
- **Weaknesses:** Limited to SQL, no conditional branching, no external API calls
- **When to choose:** Streaming/real-time ETL where simplicity matters

### Snowpark Python (Gold + DQ)
- **Use case:** Aggregation + complex data quality validation
- **Strengths:** Python flexibility, DataFrame API, runs inside Snowflake compute (no external cluster), can call APIs or run ML
- **Weaknesses:** More overhead than SQL for simple transforms, debugging is harder
- **When to choose:** Complex logic, ML feature engineering, multi-step validation, API integration

### dbt (DBT_GOLD)
- **Use case:** Version-controlled, testable, documented batch transforms
- **Strengths:** Git-based CI/CD, built-in testing framework, lineage visualization, team collaboration
- **Weaknesses:** Batch-only (no sub-minute refresh), requires scheduler, SQL-only (no Python)
- **When to choose:** Team of analysts writing SQL, PR-based review process, documentation-heavy environments

### Comparison Matrix

| Criteria | Dynamic Table | Snowpark Python | dbt |
|----------|:---:|:---:|:---:|
| Near real-time | Yes | Manual trigger | No |
| Auto-scheduling | Built-in | Task required | External scheduler |
| Testing framework | No | Manual | Built-in (10 tests) |
| Version control | DDL only | DDL only | Full Git integration |
| Language | SQL | Python + SQL | SQL + Jinja |
| CI/CD | No | No | Native support |
| Incremental | Automatic | Manual logic | `is_incremental()` macro |

---

## Orchestration

### Task DAG

```
TSK_INGEST_EV_DATA (root)
├── Schedule: 1 MINUTE
├── Guard: WHEN SYSTEM$STREAM_HAS_DATA('GCS_FILES_STREAM')
├── Action: CALL SP_INGEST_RAW_EV_DATA()
│
├──> TSK_ERROR_DETECTION (chained)
│    ├── AFTER: TSK_INGEST_EV_DATA
│    └── Action: CALL SP_DETECT_ERRORS()
│
└──> TSK_ERROR_NOTIFICATION (chained)
     ├── AFTER: TSK_ERROR_DETECTION
     └── Action: CALL SP_NOTIFY_ERRORS()

TASK_SILVER_TO_GOLD (independent)
├── Guard: WHEN SYSTEM$STREAM_HAS_DATA('CLEAN_EV_DATA_DT_STREAM')
└── Action: CALL SP_TRANSFORM_SILVER_TO_GOLD()
```

### Key Design Choices
- **Event-driven, not cron:** Tasks only fire when streams have data — zero compute when idle
- **Atomic ingestion:** ON_ERROR=ABORT_STATEMENT ensures all rows load or none do
- **Error handling chain:** DQ runs in the same execution cycle as ingestion — errors caught in seconds
- **Separate Gold task:** Decoupled from Bronze DAG; fires independently when Silver DT updates

### Comparison: Snowflake Tasks vs Alternatives

| Feature | Snowflake Tasks | Apache Airflow | dbt Cloud |
|---------|:---:|:---:|:---:|
| Infrastructure | Zero | Managed cluster | SaaS |
| Event-driven | Yes (streams) | Sensors (polling) | No |
| Cross-system | Snowflake only | Any system | Snowflake + adapters |
| Cost model | Pay-per-execution | Fixed + compute | Subscription |
| DAG visualization | Basic | Full UI | Full UI |

---

## Data Quality

### Validation Types

The `SP_DETECT_ERRORS` Snowpark Python procedure performs 5 validation types in a single execution:

| # | Type | Check | Layer | Why |
|---|------|-------|-------|-----|
| 1 | **Completeness** | Null VIN detection | Bronze | VIN is the primary key; null VINs are rejected from Silver |
| 2 | **Business Rules** | Electric range 0-500 miles | Silver | No production EV exceeds 500 miles; negative values indicate corruption |
| 3 | **Referential Integrity** | MAKE exists in DIM_MANUFACTURERS_GOLD | Silver | Orphan makes break manufacturer-level analytics and joins |
| 4 | **Uniqueness** | Duplicate VIN detection with occurrence count | Bronze | Tracks source redundancy; DT handles dedup but tracking is needed |
| 5 | **Completeness** | Null MAKE, MODEL, or MODEL_YEAR | Silver | Critical fields for Gold aggregations and semantic model dimensions |

### Error Quarantine

Errors are stored in `DATA_QUALITY.ERROR_ROWS` with full context:
```
ERROR_ID, DETECTED_AT, SOURCE_LAYER, SOURCE_TABLE, ERROR_TYPE,
ERROR_DESCRIPTION, VIN, MAKE, MODEL, MODEL_YEAR, EV_TYPE,
ELECTRIC_RANGE, BASE_MSRP, DOL_VEHICLE_ID, SOURCE_FILE, RAW_RECORD
```

### Cross-Layer Reconciliation

`V_ROW_COUNT_RECONCILIATION` traces row counts end-to-end:
```
Bronze raw → Bronze flattened → Bronze unique VINs → Silver → Gold
```
Any drift between layers triggers a `DRIFT_DETECTED` status.

### Freshness Monitoring

`V_DATA_FRESHNESS` monitors all layers with tiered thresholds:

| Layer | Fresh | Acceptable | Stale |
|-------|-------|------------|-------|
| Silver (Dynamic Table) | ≤ 5 min | ≤ 60 min | > 60 min |
| Gold (LOAD_TIMESTAMP) | ≤ 15 min | ≤ 120 min | > 120 min |
| Iceberg (LAST_ALTERED) | ≤ 30 min | ≤ 180 min | > 180 min |

### Monitoring Views

| View | Purpose |
|------|---------|
| `V_DQ_DASHBOARD` | Combined error + duplicate + reconciliation dashboard |
| `V_ERROR_SUMMARY` | Error counts by type and layer |
| `V_ERROR_TREND` | Hourly error trend for time-series analysis |
| `V_TOP_OFFENDERS` | Manufacturers with most errors |
| `V_PIPELINE_LINEAGE` | Data lineage from ACCESS_HISTORY (14-day window) |
| `V_DMF_MONITORING_RESULTS` | Snowflake Data Metric Function results |
| `V_DATA_FRESHNESS` | Freshness status across all layers |
| `V_ROW_COUNT_RECONCILIATION` | Cross-layer row count validation |

### Alerting

- Streams on ERROR_ROWS and DUPLICATE_ROWS detect new issues
- `SP_NOTIFY_ERRORS` sends email via `EV_DQ_EMAIL_INT` notification integration
- Alert includes error count, duplicate count, and error type breakdown

---

## Open Table Formats (Iceberg)

### Why Iceberg at Gold Only

| Layer | Format | Reason |
|-------|--------|--------|
| Bronze | Native Snowflake | Needs change tracking (streams), VARIANT support |
| Silver | Native Snowflake | Dynamic Table requires native format |
| Gold | Native Snowflake | Operational tables with Fail-safe, used by Snowpark SP |
| Iceberg | Apache Iceberg | Open-format copies for external engine access |

### Benefits
- **No vendor lock-in:** Data stored as Parquet files on GCS
- **Multi-engine access:** Spark, Trino, Flink, Dremio via Iceberg REST catalog
- **ACID transactions:** Consistent reads across engines
- **Schema evolution:** Add/rename columns without rewriting data files

### Trade-offs vs Native Tables
- No Fail-safe (7-day recovery)
- No cloning
- No standard streams
- No auto-clustering
- You manage storage directly (lower cost, more responsibility)

### External Volume Configuration
```
External Volume: GCP_ICEBERG_VOLUME
Storage: GCS bucket
Allow Writes: TRUE
Catalog: SNOWFLAKE (Snowflake-managed metadata)
```

---

## Data Sharing

### Three Sharing Tiers

| Tier | Method | Use Case | Cross-Cloud |
|------|--------|----------|:-----------:|
| 1 | **Secure Share** | Same-region Snowflake accounts | No |
| 2 | **Listings** | Cross-region/cross-cloud consumers | Yes (auto-fulfillment) |
| 3 | **Iceberg REST** | Non-Snowflake engines (Spark, Trino) | Yes |

### Current Implementation

**Outbound Share:** `EV_MARKET_DATA_SHARE`

| Secure View | Source | Rows |
|------------|--------|------|
| `SV_FACT_EV_MARKET_METRICS` | ICEBERG.FACT_EV_MARKET_METRICS | 46 |
| `SV_DIM_MANUFACTURERS` | ICEBERG.DIM_MANUFACTURERS_GOLD | 35 |
| `SV_DATA_QUALITY_SUMMARY` | DATA_QUALITY.V_DQ_DASHBOARD | 2 |

### Governance
- **Secure views** prevent query pushdown attacks (optimizer can't see underlying logic)
- **Schema separation** enables RBAC at the schema level
- **DQ transparency:** Data quality metrics are shared externally so consumers can assess fitness
- **SHARING schema** acts as a governed boundary — only explicitly exposed objects are visible

---

## Semantic Model & Conversational Analytics

### Semantic Model (`ev_semantic_model.yaml`)

**Entities:**

| Entity | Base Table | Dims | Metrics |
|--------|-----------|------|---------|
| `fact_ev_registrations` | ICEBERG.FACT_EV_REGISTRATIONS | 13 | 8 |
| `dim_manufacturers` | ICEBERG.DIM_MANUFACTURERS_GOLD | 3 | 0 |

**Key Metrics:**
- `total_registrations` — COUNT(VIN)
- `avg_electric_range` — AVG(ELECTRIC_RANGE)
- `bev_count` / `phev_count` — CASE-based type counts
- `bev_market_share` — BEV percentage of total
- `market_share_pct` — Group share relative to total
- `cafv_eligible_pct` — CAFV incentive eligibility rate

**Relationship:** `fact_ev_registrations.MAKE = dim_manufacturers.MANUFACTURER_NAME`

**Verified Queries:** 7 pre-validated query templates (YoY growth, manufacturer ranking, BEV vs PHEV, geographic distribution, range analysis, CAFV eligibility, model diversity)

### Streamlit App (`EV_MARKET_CHAT`)

- **Sidebar:** Live KPI metrics (total EVs, BEV share, CAFV eligibility, manufacturer count)
- **Chat interface:** Multi-turn conversation with Cortex Analyst
- **SQL transparency:** Expandable SQL panels for technical users
- **Auto-charts:** Bar charts generated when query returns numeric + categorical data
- **Suggested questions:** 7 pre-built prompts for quick demo

### Guardrails
- Cortex Analyst can only query tables defined in the semantic model
- No access to Bronze, Silver, or error tables
- Runs as CALLER — inherits user RBAC permissions

---

## Cost Governance

### Resource Monitors

| Monitor | Scope | Quota | Notify | Suspend | Force |
|---------|-------|-------|--------|---------|-------|
| `EV_PIPELINE_MONITOR` | COMPUTE_WH | 20 credits/month | 75% | 95% | 100% |
| `EV_ACCOUNT_MONITOR` | Account | 50 credits/month | 75% | 90% | 100% |

### Cost Optimization Strategies

1. **Event-driven tasks:** `WHEN SYSTEM$STREAM_HAS_DATA` — zero compute when no data arrives
2. **Single XS warehouse:** Right-sized for current volume; scale up for production
3. **Auto-suspend:** 300 seconds on COMPUTE_WH; 60 seconds on Postgres warehouses
4. **Incremental DT:** Processes only changed rows, not full table scans
5. **Iceberg on your storage:** You control GCS costs directly (no Snowflake storage markup)

### Production Scaling Plan

| Workload | Warehouse | Size | Monitor |
|----------|-----------|------|---------|
| Ingestion | INGEST_WH | XS-S | INGEST_MONITOR |
| Transformation | TRANSFORM_WH | S-M | TRANSFORM_MONITOR |
| Analytics | ANALYTICS_WH | XS-S | ANALYTICS_MONITOR |
| Data Quality | DQ_WH | XS | DQ_MONITOR |

---

## Deployment Guide

### Prerequisites
- Snowflake account with ACCOUNTADMIN role
- GCS bucket with Pub/Sub notification configured
- GCP service account with storage access

### Execution Order

```
01_infrastructure.sql    -- Warehouse, integrations, database, schemas
02_bronze.sql            -- Stage, stream, table, SP, task DAG
03_silver.sql            -- Dynamic Table, stream
04_gold.sql              -- Tables, Snowpark SP, task, stage
05_data_quality.sql      -- DQ SP, tables, streams, 8 views
06_iceberg.sql           -- 3 Iceberg tables
07_sharing.sql           -- Secure views, outbound share
08_cost_governance.sql   -- Resource monitors
09_analyst_streamlit.sql -- Upload files to stage, create Streamlit app
```

### Post-Deployment
1. Upload `ev_semantic_model.yaml`, `ev_chat_app.py`, `environment.yml` to `@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS`
2. Insert manufacturer dimension data into `DIM_MANUFACTURERS_GOLD`
3. Resume tasks (leaf-to-root order): notification → detection → ingestion → gold
4. Resume Dynamic Table: `ALTER DYNAMIC TABLE ... RESUME`
5. Upload source JSON file to GCS to trigger the pipeline

### dbt Deployment
```bash
cd 09_dbt_project
dbt run --project-dir .
dbt test --project-dir .
```

---

## Operational Runbook

### Start Pipeline
```sql
ALTER DYNAMIC TABLE EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT RESUME;
ALTER TASK EV_PROJECT_DB.GOLD.TASK_SILVER_TO_GOLD RESUME;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA RESUME;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_ERROR_DETECTION RESUME;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_ERROR_NOTIFICATION RESUME;
```

### Stop Pipeline (Save Credits)
```sql
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_ERROR_NOTIFICATION SUSPEND;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_ERROR_DETECTION SUSPEND;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA SUSPEND;
ALTER TASK EV_PROJECT_DB.GOLD.TASK_SILVER_TO_GOLD SUSPEND;
ALTER DYNAMIC TABLE EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT SUSPEND;
```

### Check Pipeline Health
```sql
-- Data freshness
SELECT * FROM EV_PROJECT_DB.DATA_QUALITY.V_DATA_FRESHNESS;

-- Row count reconciliation
SELECT * FROM EV_PROJECT_DB.DATA_QUALITY.V_ROW_COUNT_RECONCILIATION;

-- Recent errors
SELECT * FROM EV_PROJECT_DB.DATA_QUALITY.V_ERROR_SUMMARY;

-- Task execution history
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -24, CURRENT_TIMESTAMP())
))
WHERE DATABASE_NAME = 'EV_PROJECT_DB'
ORDER BY SCHEDULED_TIME DESC;
```

### Sync Iceberg Tables (After Pipeline Run)
```sql
INSERT INTO EV_PROJECT_DB.ICEBERG.FACT_EV_REGISTRATIONS
  SELECT * FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS;
INSERT INTO EV_PROJECT_DB.ICEBERG.FACT_EV_MARKET_METRICS
  SELECT * FROM EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS;
INSERT INTO EV_PROJECT_DB.ICEBERG.DIM_MANUFACTURERS_GOLD
  SELECT * FROM EV_PROJECT_DB.GOLD.DIM_MANUFACTURERS_GOLD;
```

---

## Design Decisions & Trade-offs

### 1. Why Medallion Architecture?

**Decision:** Bronze → Silver → Gold with schema separation.

**Alternative:** Single staging + analytics schema, or ELT directly into final tables.

**Trade-off:** Medallion adds schemas and tables (storage cost), but provides: reprocessability from Bronze, clear separation of concerns, independent RBAC per layer, and the ability to use different transformation engines per layer.

### 2. Why Dynamic Table for Silver?

**Decision:** INCREMENTAL Dynamic Table with 1-minute target lag.

**Alternatives:**
- Streams + Tasks with MERGE: More control but more code; manual change tracking
- dbt incremental model: No sub-minute refresh; requires external scheduler
- Snowpark SP with scheduled task: No automatic incremental tracking

**Trade-off:** Dynamic Tables abstract scheduling and incremental logic but don't support Python transformations. Silver is pure SQL cleansing, so DT is the best fit.

**Lesson learned:** Including `CURRENT_TIMESTAMP()` in the DT SELECT forces FULL refresh mode (non-deterministic). Removing it enabled INCREMENTAL mode — a significant cost reduction.

### 3. Why Three Transformation Engines?

**Decision:** DT (Silver) + Snowpark (Gold) + dbt (DBT_GOLD).

**Alternative:** Pick one and standardize.

**Trade-off:** In production, you'd likely standardize. This project uses all three to demonstrate understanding of when each is appropriate. DT for streaming, Snowpark for Python-heavy logic, dbt for team-managed batch SQL.

### 4. Why Iceberg at Gold Only?

**Decision:** Native tables for Bronze/Silver/Gold; Iceberg copies in separate schema.

**Alternative:** Make Gold tables Iceberg directly.

**Trade-off:** Direct Iceberg Gold tables would simplify the architecture but lose Fail-safe, cloning, and full stream support on the primary analytical tables. The copy pattern adds a sync step but preserves the best features of both formats.

### 5. Why Event-Driven Tasks (Not Cron)?

**Decision:** `WHEN SYSTEM$STREAM_HAS_DATA` guards on all tasks.

**Alternative:** Fixed cron schedule (e.g., every 5 minutes).

**Trade-off:** Event-driven = zero cost when idle, but requires streams on all source objects. Cron is simpler but wastes compute when no data arrives. For intermittent data sources (file drops), event-driven wins decisively.

### 6. Why Share Data Quality Metrics?

**Decision:** Include `SV_DATA_QUALITY_SUMMARY` in the outbound share.

**Alternative:** Only share clean data; hide quality issues.

**Trade-off:** Transparency builds trust. Consumers can assess data fitness for their use case. Some organizations prefer to hide quality issues — that's a governance policy decision, not a technical limitation.

### 7. Why Snowpark for DQ (Not SQL)?

**Decision:** Snowpark Python SP for data quality checks.

**Alternative:** Pure SQL stored procedure.

**Trade-off:** SQL would be simpler for basic checks. Snowpark enables: DataFrame API for complex joins, conditional validation logic, programmatic error categorization, and easy extension to ML-based anomaly detection. The original SP was SQL — it was rewritten to Snowpark to demonstrate the capability.

### 8. Why Single Warehouse?

**Decision:** One COMPUTE_WH (X-Small) for all workloads.

**Alternative:** Separate warehouses per workload.

**Trade-off:** Single warehouse simplifies management at demo scale. At production scale: four warehouses (ingest, transform, analytics, DQ) with independent resource monitors for workload isolation. This is a configuration change, not an architectural change.

---

## Account-Level Objects

| Object | Type | Purpose |
|--------|------|---------|
| `COMPUTE_WH` | Warehouse (XS) | Primary compute |
| `POSTGRESQL_COMPUTE_WH` | Warehouse (XS) | Postgres connector queries |
| `POSTGRESQL_OPS_WH` | Warehouse (XS) | Postgres connector operations |
| `GCP_EV_STORAGE_INT` | Storage Integration | GCS access |
| `GCP_EV_PUBSUB_INT` | Notification Integration | File arrival events |
| `EV_DQ_EMAIL_INT` | Notification Integration | DQ email alerts |
| `GCP_ICEBERG_VOLUME` | External Volume | Iceberg Parquet storage on GCS |
| `EV_PIPELINE_MONITOR` | Resource Monitor | 20 credits/month on COMPUTE_WH |
| `EV_ACCOUNT_MONITOR` | Resource Monitor | 50 credits/month account-wide |
| `EV_MARKET_DATA_SHARE` | Outbound Share | Cross-account data sharing |
