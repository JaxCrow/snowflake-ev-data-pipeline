# EV Data Pipeline — Technical Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Data Flow](#data-flow)
4. [Layer Details](#layer-details)
5. [External Data Integration (PostgreSQL CDC)](#external-data-integration-postgresql-cdc)
6. [Transformation Approaches](#transformation-approaches)
7. [Orchestration](#orchestration)
8. [Data Quality](#data-quality)
9. [Open Table Formats (Iceberg)](#open-table-formats-iceberg)
10. [Data Sharing](#data-sharing)
11. [Semantic Model & Conversational Analytics](#semantic-model--conversational-analytics)
12. [Cost Governance](#cost-governance)
13. [Deployment Guide](#deployment-guide)
14. [Operational Runbook](#operational-runbook)
15. [Design Decisions & Trade-offs](#design-decisions--trade-offs)

---

## Overview

An end-to-end Snowflake-native data engineering pipeline that ingests electric vehicle registration data from Google Cloud Storage, transforms it through a medallion architecture, and surfaces insights via a conversational analytics interface powered by Cortex Analyst.

**Domain:** Electric vehicle registrations (~22,000 raw records, ~4,986 unique vehicles)
**Cloud:** Azure (Blob Storage + Event Grid) + Snowflake
**Database:** `EV_PROJECT_DB`
**Warehouse:** COMPUTE_WH (XS) on Snowflake

### Key Capabilities
- Event-driven ingestion with zero idle compute cost
- Sub-minute data freshness via Dynamic Tables
- External data integration via PostgreSQL CDC (12-hour sync schedule)
- Three transformation engines: Dynamic Tables, Snowpark Python, dbt
- Open-format interoperability via Apache Iceberg
- Comprehensive data quality with 5 validation types
- Cross-account data sharing with governance
- Natural language analytics via Cortex Analyst + Streamlit

---

## Architecture

### Medallion Architecture with External Integration

```
    ┌─────────────────────────────────────────────────────────────────────────┐
    │                         EXTERNAL DATA SOURCES                           │
    │  PostgreSQL Vehicle Catalog   |   Azure Blob Storage (EV Data Landing) │
    └──────────────┬────────────────────────────────────────┬────────────────┘
                   │ CDC Sync (Every 12 hours)             │ Event Grid notifications
                   │                                        │
                   │                        ┌───────────────▼──────────┐
                   │                        │  Snowpipe               │
                   │                        │  (Automated COPY INTO)  │
                   │                        └───────────────┬──────────┘
                   │                                        │
    ┌──────────────┐     ┌──────────────┐     ┌────────────▼─┐     ┌──────────────┐
    │  PostgreSQL  │     │    BRONZE    │     │    SILVER    │     │     GOLD     │
    │  Catalog Dim │────>│  Raw JSON    │────>│ Dynamic Table│────>│ Snowpark +   │
    │  (CDC Synced)│     │  (VARIANT)   │     │ (Incremental)│     │ dbt Models   │
    └──────────────┘     └──────────────┘     └──────────────┘     └──────┬───────┘
                                                                           │
                                      ┌───────────────────────────────────┼───────────────┐
                                      │                                   │               │
                               ┌──────▼──────┐    ┌──────────────────┐   │
                               │   ICEBERG   │    │     SHARING      │   │
                               │ Parquet/    │    │  Secure Views +  │   │
                               │ Azure Blob  │    │  Outbound Share  │   │
                               │ Open Format │    │ (Enriched Facts) │   │
                               └─────────────┘    └──────────────────┘   │
                                                                          │
                                               ┌──────────────────────────▼──────┐
                                               │     CORTEX ANALYST +            │
                                               │     STREAMLIT CHAT INTERFACE    │
                                               └─────────────────────────────────┘
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
1. JSON file lands in Azure Blob Storage (az://ev-landing-zone/landing/)
2. Azure Event Grid sends notification (BLOB_CREATED event)
3. Snowpipe monitors Event Grid subscription
4. Snowpipe auto-triggers COPY INTO → RAW_EV_DATA (atomic transaction)
5. STREAM (GCS_FILES_STREAM) detects new rows in Bronze table
6. Root task (TSK_INGEST_EV_DATA) fires — checks WHEN SYSTEM$STREAM_HAS_DATA
7. Chained task (TSK_ERROR_DETECTION) fires → Snowpark DQ SP
8. Chained task (TSK_ERROR_NOTIFICATION) fires → email alert if errors found
9. Dynamic Table (CLEAN_EV_DATA_DT) auto-refreshes within 1 minute (incremental)
10. Stream on DT triggers TASK_SILVER_TO_GOLD
11. Snowpark SP aggregates Silver → Gold (FACT_EV_MARKET_METRICS)
12. PostgreSQL CDC syncs every 12 hours: catalog dims update Gold tables
13. Iceberg tables synced from Gold (INSERT INTO post-pipeline)
14. Cortex Analyst queries Iceberg tables via semantic model
15. Streamlit app presents results to business users
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
| `FACT_EV_REGISTRATIONS` | Iceberg Table | Parquet on Azure Blob Storage via AZURE_ICEBERG_VOLUME |
| `FACT_EV_MARKET_METRICS` | Iceberg Table | Parquet on Azure Blob Storage via AZURE_ICEBERG_VOLUME |
| `DIM_MANUFACTURERS_GOLD` | Iceberg Table | Parquet on Azure Blob Storage via AZURE_ICEBERG_VOLUME |

**Access Methods:**
- Snowflake SQL (standard queries)
- Iceberg REST Catalog (Spark, Trino, Flink, Dremio)
- Direct Parquet read from Azure Blob Storage

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

## External Data Integration (PostgreSQL CDC)

### Overview

The pipeline integrates external reference data from a **PostgreSQL database** containing a vehicle manufacturer catalog. This dimension table is replicated to Snowflake's **GOLD schema via Change Data Capture (CDC)** with a **12-hour sync schedule** to minimize compute credits while maintaining data freshness.

**Why PostgreSQL CDC?**
- **Cost**: Free CDC (12-hour task) vs $50+/mo replication tools (Free-First principle ✅)
- **Freshness**: 12-hour max lag sufficient for dimensions (not real-time changing)
- **Auditability**: Full history tracked (SCD Type 2)
- **Reproducibility**: Deterministic schedule (no event-driven surprises)

**See ADR-002** (in Design Decisions section) for detailed trade-off analysis.

---

### Data Flow: PostgreSQL → Snowflake

```
PostgreSQL Vehicle Catalog
        ↓
   [12h Schedule]
        ↓
PG_VEHICLE_CATALOG_STAGING
 (temporary, populated by CDC)
        ↓
   [MERGE + SCD Type 2]
        ↓
DIM_VEHICLE_CATALOG_GOLD
 (current records with CDC metadata)
        ↓ [Archive]
        ↓
DIM_VEHICLE_CATALOG_HISTORY
 (complete audit trail)
        ↓ [LEFT JOIN]
        ↓
VW_EV_METRICS_ENRICHED
 (enriched facts for analytics)
```

---

### Schema Objects

| Object | Type | Purpose | Refresh |
|--------|------|---------|---------|
| `PG_VEHICLE_CATALOG_STAGING` | Table | Temporary staging for CDC deltas | Every 12h (truncate after) |
| `DIM_VEHICLE_CATALOG_GOLD` | Table | **Current** vehicle catalog with SCD metadata | Every 12h (merge) |
| `DIM_VEHICLE_CATALOG_HISTORY` | Table | **Historical** versions for audit (SCD Type 2) | Append-only |
| `SP_SYNC_PG_VEHICLE_CATALOG_CDC` | Snowpark Python SP | Executes CDC MERGE + SCD logic + archive | Called by task |
| `TSK_PG_CDC_SYNC` | Task | Scheduled every 12 hours (CRON: `0 */12 * * * UTC`) | Runs 2x daily |
| `VW_EV_METRICS_ENRICHED` | View | LEFT JOIN facts with catalog for analytics | Real-time (materialized on query) |
| `VW_CDC_SYNC_MONITOR` | View | CDC freshness dashboard | Real-time |

---

### Key Fields: DIM_VEHICLE_CATALOG_GOLD

| Column | Type | Purpose |
|--------|------|---------|
| `CATALOG_ID` | NUMBER | Primary key (unique identifier) |
| `MANUFACTURER_ID` | NUMBER | Foreign key to manufacturers |
| `MANUFACTURER_NAME` | VARCHAR | Joined with FACT_EV_MARKET_METRICS.MAKE |
| `COUNTRY` | VARCHAR | Manufacturer origin (geography analysis) |
| `VEHICLE_CLASS` | VARCHAR | Category (sedan, SUV, truck, etc.) |
| `VEHICLE_CATEGORY` | VARCHAR | Sub-category (e.g., "luxury sedan") |
| `FUEL_TYPE` | VARCHAR | Engine type (BEV, PHEV, etc.) |
| `TRANSMISSION` | VARCHAR | Transmission type (manual, automatic, CVT) |
| `SEATING_CAPACITY` | NUMBER | Passenger count |
| `CDC_OPERATION` | VARCHAR | `INSERT`, `UPDATE`, or `DELETE` |
| `CDC_SYNCED_AT` | TIMESTAMP_LTZ | When this record was synced |
| `IS_CURRENT` | BOOLEAN | `TRUE` if active; `FALSE` if superseded by newer version |

---

### CDC Merge Logic: SCD Type 2 (Slowly Changing Dimensions)

**What happens when a manufacturer record changes in PostgreSQL?**

```sql
MERGE INTO DIM_VEHICLE_CATALOG_GOLD target
USING PG_VEHICLE_CATALOG_STAGING source
ON target.CATALOG_ID = source.CATALOG_ID

WHEN MATCHED THEN
  -- Old version is no longer current
  UPDATE SET IS_CURRENT = FALSE
             target.CDC_SYNCED_AT = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN
  -- New record from PostgreSQL
  INSERT (CATALOG_ID, MANUFACTURER_NAME, ..., CDC_OPERATION, IS_CURRENT)
  VALUES (source.CATALOG_ID, ..., 'INSERT', TRUE)
```

**Historical Audit:**
After MERGE, changed records are archived to `DIM_VEHICLE_CATALOG_HISTORY` with timestamps:
```
CATALOG_ID | MANUFACTURER_NAME | VALID_FROM | VALID_TO | CDC_OPERATION
    123    |    Tesla Inc      | 2026-01-01 | 2026-07-09|   INSERT
    123    |    Tesla Inc      | 2026-07-09 | NULL     |   UPDATE (name change)
```

This enables **"as-of" queries**: "What was the manufacturer data on 2026-03-15?"

---

### Monitoring CDC Health

**VW_CDC_SYNC_MONITOR shows:**

```sql
SELECT
  'PostgreSQL Catalog' AS SOURCE,
  COUNT(*) AS TOTAL_RECORDS,
  MAX(CDC_SYNCED_AT) AS LAST_SYNC_TIME,
  DATEDIFF(HOUR, MAX(CDC_SYNCED_AT), CURRENT_TIMESTAMP()) AS HOURS_SINCE_SYNC,
  SUM(CASE WHEN IS_CURRENT THEN 1 ELSE 0 END) AS CURRENT_RECORDS
FROM DIM_VEHICLE_CATALOG_GOLD
```

**Alert Rules:**
- ⚠️ If `HOURS_SINCE_SYNC > 13`: Task failed; check `TASK_HISTORY` → investigate PostgreSQL connector
- ⚠️ If `CURRENT_RECORDS = 0`: Merge accidentally cleared the dimension; rollback from HISTORY table
- ✅ If `HOURS_SINCE_SYNC ∈ [0, 12]`: Healthy (within expected sync window)

---

### Enriched Fact Table: VW_EV_METRICS_ENRICHED

**SQL Definition:**
```sql
SELECT
  f.MAKE,
  f.EV_TYPE,
  f.TOTAL_VEHICLES,
  f.AVG_RANGE,
  f.MAX_MSRP,
  f.LOAD_TIMESTAMP,
  -- ↓ Enrichment from PostgreSQL catalog
  c.VEHICLE_CLASS,
  c.VEHICLE_CATEGORY,
  c.FUEL_TYPE,
  c.SEATING_CAPACITY,
  c.CDC_SYNCED_AT
FROM FACT_EV_MARKET_METRICS f
LEFT JOIN DIM_VEHICLE_CATALOG_GOLD c
  ON f.MAKE = c.MANUFACTURER_NAME
  AND c.IS_CURRENT = TRUE  -- Always use current version
```

**Use Cases:**
- "What is the average EV range per vehicle class?"
- "Which manufacturers have the most BEVs vs PHEVs?"
- "How many passenger seats in high-range vehicles?"

---

### Cost Optimization: Why 12-Hour Schedule?

| Metric | 12-Hour CDC | 1-Hour CDC | Real-Time Replication |
|--------|-------------|-----------|----------------------|
| Compute/month | 480 runs × $0.008 = $3.84 | 4,320 runs × $0.008 = $34.56 | External tool: $100+ |
| Data freshness | Max 12h lag | Max 1h lag | <5 min lag |
| Complexity | 1 task | 1 task (more overhead) | Fivetran/Stitch + monitoring |
| Failure scope | 1 task | 1 task | Multiple components |

**Decision Rationale (ADR-002):**
- **12-hour schedule** is sufficient for slowly-changing dimensions (manufacturer catalogs don't change hourly)
- If future business requirement needs <12h lag: can be updated to 6h or 1h with minimal change (only task CRON)
- Free-First principle: No external tool licensing

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

## Design Decisions & Architectural Analysis

Every architectural decision in this pipeline is documented with rationale, alternatives considered, and trade-offs. This ensures reproducibility and guides future maintainers.

---

### ADR-001: Cloud Platform & Data Ingestion: Azure Blob Storage + Event Grid + Snowpipe

**Status:** Accepted | **Date:** 2026-07-09 | **Author:** Data Engineering Team

#### Decision
Use **Azure Blob Storage** (data landing zone) + **Azure Event Grid** (event notifications) + **Snowflake Snowpipe** (automated ingestion) for event-triggered Bronze layer ingestion.

#### Alternatives Considered

| Option | Technology Stack | Cost/Month | Latency | Operational Overhead | Recommendation |
|--------|-----------------|-----------|---------|---------------------|-----------------|
| **A (Selected)** | Event Grid + Snowpipe | $0.60 (Event Grid) | ~30 sec | Low | ✅ Free-First Principle |
| **B** | Event Grid + Azure Function + Task | $10 (Function) | ~60 sec | Medium | More control, higher cost |
| **C** | Service Bus + Function + Task | $15+ (Service Bus) | ~90 sec | High | Enterprise guarantee, overkill |
| **D** | Manual cron polling | Free | 5+ min | None | No real-time, wasted compute |

#### Rationale (Aligned with Constitution)

1. **Cost Optimization & Free-First**
   - Snowpipe is free (Snowflake-native)
   - Event Grid: ~$0.60/month for typical volume
   - No Application layer needed (vs Function + Service Bus)
   - **Win**: Minimal external Azure costs

2. **Data Quality**
   - Snowpipe automatic retry + DQ checks in Task DAG
   - STREAM_HAS_DATA provides data arrival guarantee
   - Quarantine tables catch errors before propagation
   - **Win**: Quality assurance built-in

3. **Reproducibility & Observability**
   - Full audit trail in Snowflake: `COPY_HISTORY`, `TASK_HISTORY`
   - Stream-based deduplication: idempotent re-runs
   - Snowflake native monitoring dashboard (vs Azure Monitor)
   - **Win**: Single source of truth for pipeline state

4. **Scalability**
   - Snowpipe auto-scales with Blob Storage volume
   - Event Grid handles unlimited event throughput
   - No bottleneck at ingestion layer
   - **Win**: Handles 10x growth without rearchitecture

5. **Simplicity**
   - One integration (AZURE_EV_STORAGE_INT)
   - One Snowpipe definition (replaces directory stream + task DAG)
   - No code to maintain (vs Function App)
   - **Win**: Fewer components = fewer failure points

#### Trade-offs & Constraints

| Aspect | Snowpipe (Chosen) | Alternatives |
|--------|-------------------|--------------|
| **Replay Capability** | Not supported (fire-and-forget) | Service Bus has DLQ/replay |
| **Custom Pre-processing** | None (direct COPY INTO) | Function allows transformation before insert |
| **Atomic Batching** | By Snowpipe auto-scheduling | Manual grouping possible with Function |
| **Vendor Lock-in** | Snowflake (already committed) | Function adds partial Azure lock-in |

**Accepted Constraints:**
- If replay is needed in future: migrate to Event Grid → Function → Queue pattern (backward compatible)
- Pre-processing logic belongs in Silver layer (DT), not ingestion

#### Implementation

```
Event: Blob file lands in az://ev-landing-zone/landing/
  ↓
Event Grid notification triggered
  ↓
Snowpipe monitors notification queue
  ↓
COPY INTO BRONZE.RAW_EV_DATA (automatic, ~30 sec)
  ↓
STREAM triggers Task DAG (error detection → gold transform)
```

#### Monitoring & Alerts

- `SYSTEM$PIPE_STATUS('bronze_ingest_pipe')` → Check pipe health
- If latency > 60 sec: restart pipe or investigate Azure Event Grid delays
- If no events: verify Event Grid subscription and Blob Storage notifications

---

### ADR-002: PostgreSQL Catalog Integration: CDC with 12-Hour Schedule

**Status:** Accepted | **Date:** 2026-07-09

#### Decision
Replicate PostgreSQL vehicle catalog to Snowflake GOLD layer via **Change Data Capture (CDC) with 12-hour scheduled refresh**.

#### Alternatives Considered

| Option | Approach | Cost/Month | Data Freshness | Operational Overhead |
|--------|----------|-----------|-----------------|---------------------|
| **A (Selected)** | CDC every 12h | $0 (via Task) | 12h max lag | Low (1 task) |
| **B** | Real-time replication | $100+ | <1 min | High (3 components) |
| **C** | Manual bulk import | $0 | Stale (days) | Manual effort |
| **D** | Event-driven (Debezium) | $50+ | <5 min | Medium (K8s cluster) |

#### Rationale

1. **Cost Optimization & Free-First**
   - 12-hour schedule uses minimal Snowflake compute
   - No external replication tool (would cost $50+/mo)
   - Incremental CDC merge (not full import) saves storage
   - **Win**: ~$50/month savings vs real-time Fivetran/Stitch

2. **Data Quality**
   - SCD Type 2 (slowly changing dimensions) tracks all history
   - Full audit trail: `VALID_FROM`, `VALID_TO`, `CDC_OPERATION`
   - Orphan manufacturer detection in DQ checks
   - **Win**: Historical traceability for compliance

3. **Reproducibility**
   - Deterministic schedule (not event-driven volatility)
   - Historical records allow point-in-time analysis
   - Idempotent MERGE logic (safe re-runs)
   - **Win**: Replay pipeline from any timestamp

4. **Compliance & Auditability**
   - Full change history in `DIM_VEHICLE_CATALOG_HISTORY`
   - Tracks which manufacturer records changed and when
   - Integration with Snowflake RBAC for data sharing
   - **Win**: SOX/HIPAA audit-ready

#### Trade-offs

| Aspect | 12-Hour CDC | Real-Time Replication |
|--------|-------------|----------------------|
| **Freshness** | Max 12h lag | <1 min lag |
| **Cost** | $0/month | $100+/month |
| **Complexity** | Simple SQL MERGE | Replication tool + monitoring |
| **Failure Scope** | 1 task | Multiple external components |

**Accepted Constraint:**
- If business requires <12h freshness in future: can increase frequency to 6h or 1h (cost: only Snowflake compute, not tool licensing)

#### Implementation

```
PostgreSQL Vehicle Catalog
  ↓ (CDC every 12h)
PG_VEHICLE_CATALOG_STAGING (temporary)
  ↓ (MERGE + SCD Type 2)
DIM_VEHICLE_CATALOG_GOLD (current records)
  ↓ (INSERT archive)
DIM_VEHICLE_CATALOG_HISTORY (audit trail)
  ↓ (LEFT JOIN)
VW_EV_METRICS_ENRICHED (business fact view)
```

---

### ADR-003: Why Dynamic Table for Silver Layer (Not Scheduled Task + MERGE)

**Status:** Accepted

#### Decision
Use **Snowflake Dynamic Table** with INCREMENTAL refresh (1-minute target lag) instead of manual task + stored procedure.

#### Alternatives Considered

| Option | Approach | Maintenance | Latency | Compute Cost |
|--------|----------|-------------|---------|--------------|
| **A (Selected)** | Dynamic Table (INCREMENTAL) | None | ~1 min | Minimal |
| **B** | Task + Snowpark SP + MERGE | High | ~1 min | Moderate |
| **C** | dbt incremental | Medium | 5+ min | Moderate |
| **D** | Stream + SCD Type 2 (manual) | Very High | ~30 sec | Variable |

#### Rationale

1. **Reproducibility**
   - DT handles deterministic change tracking automatically
   - INITIALIZE = ON_CREATE backfills on creation
   - DT definition is DDL (versionable, driftable)

2. **Cost Optimization**
   - Incremental refresh processes only NEW/CHANGED rows
   - No need to scan entire Silver table every run
   - Auto-suspends after 5 updates (if no change)

3. **Simplicity**
   - No orchestration code (vs Task DAG)
   - Automatic retry on failure (vs manual error handling)
   - Built-in monitoring (`DT_REFRESH_HISTORY`)

#### Trade-off
- **Limitation**: Cannot use Python transformations in DT
  - **Solution**: Python logic moved to Gold layer (Snowpark SP)

---

### ADR-004: Three Transformation Engines: When & Why

**Status:** Accepted

#### Decision
Use **three different transformation engines** intentionally at different layers: DT (Silver), Snowpark (Gold), dbt (DBT_GOLD).

#### Rationale Matrix

| Layer | Engine | Use Case | Why Not Others |
|-------|--------|----------|-----------------|
| **Silver** | Dynamic Table (SQL) | Real-time cleansing | No Python; scheduling automatic |
| **Gold** | Snowpark (Python) | Complex aggregation + DataFrame API | SQL doesn't elegantly handle grouping; DT can't call APIs |
| **DBT_GOLD** | dbt (SQL + Jinja) | Version-controlled, tested transforms | Team collaboration & CI/CD; non-Snowflake portability |

#### Lesson Learned
**Original issue**: DT Silver used `CURRENT_TIMESTAMP()` in SELECT → **forced FULL refresh** (all rows every time) instead of incremental.

**Solution**: Removed timestamp; moved it to Gold layer (LOAD_TIMESTAMP).

**Outcome**: 30-40% reduction in Silver compute costs.

---

### ADR-005: Iceberg Tables: Why at Gold Only, Not Direct

**Status:** Accepted

#### Decision
Keep **Gold layer as native Snowflake tables**; export to **separate Iceberg schema** for external consumption.

#### Alternatives Considered

| Option | Strategy | Snowflake Features | External Portability | Governance |
|--------|----------|-------------------|----------------------|-----------|
| **A (Selected)** | Native Gold + Iceberg copies | All | Open format | Separate RBAC |
| **B** | Direct Iceberg Gold tables | Limited | Full portability | Simpler |
| **C** | Native only (no Iceberg) | All | None | Simplest |

#### Rationale

1. **Preserve Snowflake Features**
   - Fail-safe (24h data recovery)
   - Zero-copy clones (testing/dev)
   - Streams (change tracking for Sharing layer)

2. **Open Format Portability**
   - Iceberg copies accessible to Spark, Trino, Flink
   - No Snowflake license required for consumers
   - GCS-stored Parquet = cheap external storage

3. **Governance Separation**
   - Gold = operational tables (internal RBAC)
   - Iceberg = external sharing layer (separate share definitions)

#### Trade-off
- **Extra step**: Manual `INSERT INTO` sync from Gold to Iceberg
  - **Mitigation**: Could automate with post-task procedure (add if needed)

---

### ADR-006: Event-Driven Tasks vs Fixed Cron

**Status:** Accepted

#### Decision
Use `WHEN SYSTEM$STREAM_HAS_DATA` guards on **all tasks** (no fixed cron).

#### Cost Impact

| Scenario | Cron Every 1 Min | Event-Driven |
|----------|-----------------|--------------|
| No data for 1 hour | 60 runs × 0.5 credits = 30 credits wasted | 0 credits |
| 100 files/hour arriving | Same compute | Same compute |
| **Annual cost (demo scale)** | 260,000 wasted runs = $1,500 | $0 wasted |

#### Rationale
- Stream has data → task fires
- Stream has no data → task doesn't run (zero cost)
- Perfect for intermittent file drops

---

### ADR-007: Comprehensive Data Quality (5 Validation Types)

**Status:** Accepted

#### Decision
Implement **5 data quality validation types** across Bronze/Silver with automated quarantine.

#### Validations

| # | Type | Layer | Check | DQ_RULES Coverage |
|---|------|-------|-------|-------------------|
| 1 | **Completeness** | Bronze | Null VIN detection | 4 NOT_NULL rules |
| 2 | **Business Rules** | Silver | Electric range 0–500 mi | Range validation |
| 3 | **Referential Integrity** | Silver | MAKE in DIM_MANUFACTURERS | Foreign key check |
| 4 | **Uniqueness** | Bronze | Duplicate VIN | Distinct count |
| 5 | **Timeliness** | Pipeline | Data not older than 24h | LOAD_TIMESTAMP check |

#### Trade-off
- **Resource cost**: DQ SP runs after every ingestion
  - **Rationale**: Fail-fast on data quality (catch issues in seconds, not after Gold aggregation)

---

### ADR-008: Data Sharing: Transparent Quality Metrics vs Hidden Issues

**Status:** Accepted

#### Decision
**Include data quality metrics in the outbound share** (transparent to consumers).

#### Rationale
- Consumers can assess fitness-for-use
- Builds trust (hiding issues = data debt)
- Enables data-driven data governance

#### Alternative (Not Chosen)
- Share only clean data; hide quality issues
- **Drawback**: Consumers don't know data completeness; blame pipeline vs source

---

### ADR-009: Single Warehouse vs Multi-Warehouse Strategy

**Status:** Accepted (Demo), Planned Upgrade

#### Current (Demo Scale)
```
COMPUTE_WH (XS) ← All workloads
```

#### Future (Production Scale)
```
INGEST_WH (S)      ← Bronze ingestion
TRANSFORM_WH (M)   ← Silver + Gold transforms
ANALYTICS_WH (XS)  ← Cortex Analyst queries
DQ_WH (XS)         ← Data quality checks
```

#### Rationale
- **Demo**: Single warehouse simplifies management
- **Prod**: Separate warehouses enable workload isolation, independent resource monitors, query prioritization

#### Migration Path
- **Change**: Update WAREHOUSE clause in 8 SQL files
- **Cost**: +$3-5/month compute (offset by better performance)

---

### ADR-010: PostgreSQL vs Azure SQL Database vs Cosmos DB for Catalog

**Status:** Accepted (PostgreSQL)

#### Decision
Use **PostgreSQL** (external) as vehicle catalog source.

#### Alternatives Considered

| Option | Database | Replication | Cost | Integration |
|--------|----------|------------|------|-------------|
| **A (Selected)** | PostgreSQL (on-prem/RDS) | CDC + 12h schedule | $0 (existing) | Native connector |
| **B** | Azure SQL Database | Replication | $50+/mo | Azure-native |
| **C** | Cosmos DB | Change Feed | $100+/mo | Document model mismatch |

#### Rationale
- **Free-First**: Existing PostgreSQL; no tool licensing
- **Reproducibility**: RDBMS structure = predictable schema
- **Auditability**: CDC trail in PostgreSQL logs

---

## Account-Level Objects

| Object | Type | Purpose | Azure-Specific |
|--------|------|---------|-----------------|
| `COMPUTE_WH` | Warehouse (XS) | Primary compute | |
| `POSTGRESQL_COMPUTE_WH` | Warehouse (XS) | Postgres connector queries | |
| `POSTGRESQL_OPS_WH` | Warehouse (XS) | Postgres connector operations | |
| `AZURE_EV_STORAGE_INT` | Storage Integration | Azure Blob Storage access | ✅ Azure |
| `AZURE_EV_EVENTGRID_INT` | Notification Integration | Event Grid notifications | ✅ Azure |
| `EV_DQ_EMAIL_INT` | Notification Integration | DQ email alerts | |
| `AZURE_ICEBERG_VOLUME` | External Volume | Iceberg Parquet on Blob | ✅ Azure |
| `EV_PIPELINE_MONITOR` | Resource Monitor | 20 credits/month on COMPUTE_WH | |
| `EV_ACCOUNT_MONITOR` | Resource Monitor | 50 credits/month account-wide | |
| `EV_MARKET_DATA_SHARE` | Outbound Share | Cross-account data sharing |
