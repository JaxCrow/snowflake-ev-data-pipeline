# EV Data Pipeline — Panel Interview Presentation Guide

---

## 1. Architecture Design

### Medallion Layer Design

This pipeline implements a three-layer medallion architecture with strict schema boundaries enforced by separate Snowflake schemas:

```
EV_PROJECT_DB
├── BRONZE   — Raw ingestion (immutable JSON landing zone)
├── SILVER   — Cleansed, typed, deduplicated (structured analytics-ready)
├── GOLD     — Aggregated metrics + enriched fact table (business-facing)
├── DATA_QUALITY — DMFs, error quarantine, reconciliation views
└── SHARING  — Secure views for external consumers
```

**Bronze** stores raw JSON as VARIANT in `RAW_EV_DATA` — no transformations at ingestion. This preserves the immutable audit trail and allows reprocessing if transformation logic changes later.

**Silver** uses a Dynamic Table (`CLEAN_EV_DATA_DT`) with `REFRESH_MODE = INCREMENTAL` to flatten JSON into 14 typed columns, filter null VINs, and deduplicate using `QUALIFY ROW_NUMBER() OVER (PARTITION BY VIN ORDER BY SOURCE_FILE DESC) = 1`. This reduced 22,183 raw records to 4,986 unique vehicles.

**Gold** serves two distinct consumption patterns:
- `FACT_EV_MARKET_METRICS` — An Iceberg table with pre-aggregated metrics (total vehicles, avg range, max MSRP by MAKE/EV_TYPE) for cross-engine interoperability.
- `FACT_EV_REGISTRATIONS` — A traditional Snowflake table with enriched row-level data (18 columns including geography, CAFV eligibility, utility provider) for the semantic model and Cortex Analyst.

### Separation of Concerns

Each Snowflake object has a single responsibility:

| Object | Responsibility |
|--------|---------------|
| External Stage | File access to GCS |
| Directory Stream | Detect new file arrivals |
| Task + SP | Execute COPY INTO for ingestion |
| Dynamic Table | Transform, type-cast, deduplicate |
| Stream on DT | Capture row-level changes for downstream |
| Task + SP | Aggregate into gold |
| DMFs | Continuous quality validation |
| Secure Views | Column-filtered, pushdown-protected sharing |

### Why This Shape

- **Three layers (not two, not five)**: The data goes through exactly three state changes — raw, clean, aggregated. Adding a "staging" or "presentation" layer would add objects without adding value for a single-domain pipeline.
- **Schemas as boundaries**: Using separate schemas (BRONZE, SILVER, GOLD) rather than separate databases avoids cross-database privilege complexity while still providing RBAC isolation at the schema level.
- **DATA_QUALITY as its own schema**: Error tables, DMFs, reconciliation views, and dashboard views are decoupled from the data layers so that quality monitoring can be granted independently.

---

## 2. Tool Selection

### Feature Selection Matrix

| Requirement | Feature Chosen | Alternatives Considered | Why This Choice |
|-------------|---------------|------------------------|-----------------|
| File ingestion from GCS | External Stage + COPY INTO via SP | Snowpipe, Auto-Ingest | SP gives explicit error handling and return status; PURGE=TRUE prevents reprocessing |
| Change detection on stage | Directory Stream + Pub/Sub notification integration | Polling, scheduled LIST | Event-driven — zero compute when no files arrive |
| JSON to structured columns | Dynamic Table (INCREMENTAL) | Stored Procedure + MERGE, dbt incremental model | Zero maintenance, automatic incremental logic, sub-minute lag, native stream support |
| Aggregation into gold | Snowpark SP triggered by stream | Dynamic Table, dbt model | Gold is an Iceberg table — DT cannot materialize as Iceberg; SP allows truncate-reload pattern |
| Open format serving | Iceberg Table (Snowflake-managed catalog) | Regular table + COPY OUT to Parquet | Native Iceberg support means automatic metadata management, ACID transactions, schema evolution |
| Data quality | Native DMFs (system + custom) | dbt tests, Great Expectations | Continuous monitoring (not batch), auto-persisted history, TRIGGER_ON_CHANGES scheduling |
| Error detection | Task DAG chained AFTER ingestion | Fixed-schedule task, Snowpipe error handling | Zero-latency detection — errors caught seconds after data arrives |
| External dimension data | Snowflake Connector for PostgreSQL (CDC) | COPY INTO from CSV export, External Table | Near-real-time sync without full table scans on source PostgreSQL |
| Sharing | Secure Share + Reader Account + Catalog Sync | Data export, API, Marketplace listing | Three tiers cover all consumer types (Snowflake accounts, non-Snowflake users, external engines) |
| Business analytics | Cortex Analyst + Semantic Model + Streamlit | Tableau, Looker, custom dashboards | Conversational interface; natural language to SQL; no BI tool licensing |

### Dynamic Table vs. Stored Procedure (Silver Layer)

The original pipeline used a stored procedure with a MERGE statement for the silver layer. It was replaced with a Dynamic Table because:

- **Scheduling**: DT is fully automatic via `TARGET_LAG = '1 MINUTE'`; SP required a task with explicit scheduling.
- **Incremental logic**: DT automatically tracks which bronze rows are new; SP required hand-coded `WHERE` clauses.
- **Stream support**: A stream on a DT captures row-level changes natively; a stream on a table written by an SP works, but the DT approach is cleaner.
- **Failure recovery**: DT retries transparently; SP failures require manual re-triggering.
- **Code maintenance**: DT is a single SQL statement; SP required Python + SQL + error handling.

### Why Not dbt

dbt is not used because the Snowflake-native features collectively provide what dbt offers — with lower latency, zero external dependencies, and continuous monitoring:

- **Bronze**: dbt cannot handle ingestion (stages, COPY INTO, Snowpipe).
- **Silver**: Dynamic Tables replace dbt incremental models with less code and sub-minute latency.
- **Gold**: dbt cannot write to Iceberg tables with external volumes without custom materializations.
- **Quality**: DMFs are continuous monitors; dbt tests are batch assertions.
- **Orchestration**: Streams + Tasks are event-driven; dbt requires an external scheduler.

**When dbt would be the right choice**: 20+ engineers, complex multi-domain DAGs, multi-platform deployment (Snowflake + BigQuery + Redshift), or environments needing PR-based CI/CD for SQL.

---

## 3. Transformation Approach

### Bronze to Silver

The Dynamic Table handles three transformations in a single declarative statement:

**1. Flattening**: `LATERAL FLATTEN(input => JSON_DATA:data)` unpacks the nested JSON array into individual records.

**2. Type casting**: Each positional array element is cast to its target type:
```sql
f.value[8]::VARCHAR   AS VIN,
f.value[14]::VARCHAR  AS MAKE,
f.value[13]::INT      AS MODEL_YEAR,
f.value[19]::FLOAT    AS BASE_MSRP
```

**3. Deduplication**: `QUALIFY ROW_NUMBER() OVER (PARTITION BY VIN ORDER BY SOURCE_FILE DESC) = 1` keeps only the most recent record per VIN, handling cases where the same vehicle appears in multiple source files.

**4. Null rejection**: `WHERE f.value[8] IS NOT NULL` filters records without a VIN — these are captured separately in the ERROR_ROWS quarantine table.

### Silver to Gold (Aggregation)

The Snowpark SP reads the full silver DT, aggregates by MAKE and EV_TYPE, then truncate-and-reloads the Iceberg table. The truncate-reload pattern (not MERGE) is appropriate because the gold table is a complete re-aggregation — not an incremental append.

### Validation of Transformations

Transformations are validated at three levels:

**Automated (continuous):**
- DMFs on silver: NULL_COUNT on VIN/MAKE/MODEL, DUPLICATE_COUNT on VIN/DOL_VEHICLE_ID, INVALID_ELECTRIC_RANGE, NEGATIVE_MSRP, ORPHAN_MAKE_CHECK.
- Cross-layer DMFs: ROW_COUNT_DRIFT_SILVER_VS_BRONZE (should be 0), GOLD_VEHICLE_COUNT_DRIFT (should be 0), GOLD_MAKE_COVERAGE (should be 0).

**Reconciliation (on-demand):**
- `V_ROW_COUNT_RECONCILIATION` computes a single-row summary: bronze raw rows → flattened rows → unique VINs → silver rows → gold total vehicles, with drift calculations and a PASS/DRIFT_DETECTED status.

**Error quarantine (event-driven):**
- `SP_DETECT_ERRORS` runs immediately after each ingestion (AFTER task in DAG), scanning both layers for six error types and writing violations to ERROR_ROWS with full context for investigation.

---

## 4. Orchestration Knowledge

### Pipeline Orchestration Model

The pipeline uses two orchestration patterns:

**Pattern 1: Event-driven task chain (Bronze)**
```
Pub/Sub notification → Directory auto-refresh → GCS_FILES_STREAM has data
    → TSK_INGEST_EV_DATA fires (every 1 min WHEN stream has data)
        → TSK_ERROR_DETECTION (AFTER ingest)
            → TSK_ERROR_NOTIFICATION (AFTER detection)
```

**Pattern 2: Stream-triggered task (Gold)**
```
Dynamic Table auto-refreshes → CLEAN_EV_DATA_DT_STREAM captures changes
    → TASK_SILVER_TO_GOLD fires (WHEN stream has data)
```

**Pattern 3: Declarative freshness (Silver)**
```
RAW_EV_DATA changes → Dynamic Table detects new rows → refreshes incrementally
(No task, no stream, no SP — Snowflake manages everything via TARGET_LAG)
```

### Error Handling Strategy

Errors are handled at three levels:

| Level | Mechanism | Behavior |
|-------|-----------|----------|
| **Ingestion** | `ON_ERROR = 'ABORT_STATEMENT'` in COPY INTO | Atomic: all rows in a file load or none do |
| **SP failure** | Python try/catch returning status string | SP returns "FAILURE: {error}" — task history captures this |
| **Data quality** | SP_DETECT_ERRORS → ERROR_ROWS table → stream → SP_NOTIFY_ERRORS → email | Bad data is quarantined with full context; email sent automatically |

The task DAG ensures causal ordering: errors are always detected in the same execution cycle as the ingestion that caused them — not on a delayed schedule.

### Comparison: Streams+Tasks vs. Airflow vs. dbt

| Dimension | Streams + Tasks (this pipeline) | Airflow | dbt |
|-----------|--------------------------------|---------|-----|
| **Trigger model** | Event-driven (stream has data) | Time-based (cron) or event (sensors) | Time-based (cron or dbt Cloud) |
| **Latency** | Sub-minute | Minutes to hours | Minutes |
| **Infrastructure** | Zero — native Snowflake | Requires separate cluster (MWAA, Astronomer, self-hosted) | Requires dbt Cloud or CLI + scheduler |
| **DAG complexity** | Best for linear/simple chains | Best for complex multi-system DAGs | Best for SQL-only transformation DAGs |
| **Error handling** | Task history + SP return values + email integration | Rich (retries, SLA alerts, callbacks) | Limited (pass/fail per model) |
| **Cost** | Pay only when tasks fire (event-driven) | Fixed infra cost + Snowflake compute | dbt Cloud licensing + Snowflake compute |

**When to upgrade**: If the pipeline grows to orchestrate across multiple systems (GCS + Snowflake + ML platform + BI tool), Airflow becomes valuable. For Snowflake-only pipelines, Streams + Tasks are simpler and cheaper.

---

## 5. Open Table Formats

### Iceberg Implementation

`FACT_EV_MARKET_METRICS` is a Snowflake-managed Apache Iceberg table:

```sql
CREATE OR REPLACE ICEBERG TABLE EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS (...)
  EXTERNAL_VOLUME = 'GCP_ICEBERG_VOLUME'
  ICEBERG_VERSION = 2
  CATALOG = 'SNOWFLAKE'
  BASE_LOCATION = 'gold/fact_ev_market_metrics/';
```

**How it works**: Snowflake writes Parquet data files and Iceberg metadata (manifest lists, manifests, table metadata JSON) to `gcs://ev-landing-zone-lordrivas/iceberg_data/gold/fact_ev_market_metrics/`. The `CATALOG = 'SNOWFLAKE'` setting means Snowflake manages the catalog internally.

**What Iceberg enables**:
- ACID transactions on open-format data
- Schema evolution (add/rename columns without rewriting Parquet files)
- Snapshot-based time travel
- Parquet files readable by any engine

### Why Iceberg for Aggregated Metrics, Traditional for Row-Level Data

| Table | Format | Reason |
|-------|--------|--------|
| `FACT_EV_MARKET_METRICS` | Iceberg | Small, aggregated table designed for cross-engine access (Spark, Trino, BigQuery). Catalog Sync publishes metadata to Open Catalog. |
| `FACT_EV_REGISTRATIONS` | Traditional | 18-column, 4,986-row detail table consumed exclusively within Snowflake (semantic model, Streamlit app, secure views). Benefits from full platform support: Fail-safe, cloning, replication, full stream support, auto-clustering. |

### Catalog Sync for External Engines

The pipeline is pre-configured for Catalog Sync to Snowflake Open Catalog (Polaris):

```sql
ALTER SCHEMA EV_PROJECT_DB.GOLD SET CATALOG_SYNC = 'EV_OPEN_CATALOG_INT';
```

After enabling, Spark/Trino/BigQuery connect via the Iceberg REST catalog protocol and read Parquet files directly from GCS — no Snowflake credentials needed.

### Trade-Off: Vendor Lock-In vs. Performance

Iceberg trades some Snowflake-native features (Fail-safe, cloning, full stream support) for portability. The pipeline uses Iceberg only where interoperability justifies it (the aggregated gold table), and keeps everything else native. This is a deliberate, targeted choice — not a blanket "Iceberg everything" approach.

---

## 6. Data Sharing

### Three-Tier Sharing Architecture

The pipeline supports three consumer types through three mechanisms:

**Tier 1: Snowflake Secure Sharing (zero-copy)**
- **Consumer**: Other Snowflake accounts
- **Mechanism**: `EV_MARKET_DATA_SHARE` with three secure views in the SHARING schema
- **Data movement**: None — consumer queries provider's storage directly
- **Latency**: Real-time (consumer sees latest gold data)
- **Cost**: Consumer pays their own compute
- **Security**: Secure views prevent query pushdown attacks and hide internal columns

Shared objects:
| Secure View | Source | Columns Exposed |
|-------------|--------|----------------|
| SV_FACT_EV_MARKET_METRICS | Gold Iceberg table | MAKE, EV_TYPE, TOTAL_VEHICLES, AVG_RANGE, MAX_MSRP, LOAD_TIMESTAMP |
| SV_DIM_MANUFACTURERS | Gold dimension | MANUFACTURER_ID, MANUFACTURER_NAME, COUNTRY |
| SV_DATA_QUALITY_SUMMARY | DQ dashboard | Error types, counts, reconciliation status |

**Tier 2: Reader Account (non-Snowflake users)**
- **Consumer**: External analysts, partners, auditors without Snowflake accounts
- **Mechanism**: Managed account `EV_DATA_READER` (locator: UA12095) with read-only SQL access
- **Cost**: Provider pays compute
- **Use case**: Regulatory bodies needing read-only quality metrics; partner orgs without Snowflake

**Tier 3: Catalog Sync (external engines)**
- **Consumer**: Spark, Trino, BigQuery, Presto
- **Mechanism**: Iceberg table + Open Catalog integration via REST catalog protocol
- **Data movement**: None — engines read Parquet from GCS directly
- **Cost**: GCS egress only

### Why Share DQ Metrics

The `SV_DATA_QUALITY_SUMMARY` secure view is shared alongside the data. This is a deliberate transparency decision — consumers can see error counts and reconciliation status, building trust and enabling them to make informed decisions about data fitness.

---

## 7. Cost Optimization

### Compute Cost Controls

| Mechanism | How It Saves | Where Applied |
|-----------|-------------|---------------|
| **WHEN SYSTEM$STREAM_HAS_DATA()** | Tasks fire only when new data exists — zero compute on idle | TSK_INGEST_EV_DATA, TASK_SILVER_TO_GOLD |
| **AFTER task chaining** | Error detection runs only when ingestion runs, not on independent schedule | TSK_ERROR_DETECTION, TSK_ERROR_NOTIFICATION |
| **REFRESH_MODE = INCREMENTAL** | Dynamic Table processes only new bronze rows, not full table scan | CLEAN_EV_DATA_DT |
| **TRIGGER_ON_CHANGES DMF schedule** | DMFs run only when the monitored table changes | Silver and Gold DMFs |
| **TARGET_LAG = '1 MINUTE'** | DT refreshes only as fast as needed — adjustable SLA | CLEAN_EV_DATA_DT |
| **Pub/Sub notifications** | Stage directory auto-refreshes on events, not polling | GCP_EV_PUBSUB_INT |

### Storage Cost Controls

| Mechanism | Impact |
|-----------|--------|
| **PURGE = TRUE** in COPY INTO | Processed files deleted from GCS stage — no accumulation |
| **Iceberg on customer-managed GCS** | No Snowflake storage charges for gold Iceberg table; GCS billed directly at lower rates |
| **Single warehouse (COMPUTE_WH)** | All tasks share one warehouse — avoids proliferation of idle warehouses |
| **Truncate-reload for gold** | No historical versions accumulate in the Iceberg table; always fresh aggregation |

### Architectural Cost Decisions

- **Dynamic Table vs. SP+Task for silver**: DT with incremental refresh avoids full-table MERGE operations, reducing compute by processing only deltas.
- **Traditional table for FACT_EV_REGISTRATIONS**: Avoids GCS egress costs and external volume overhead for a table consumed exclusively within Snowflake.
- **DMF scheduling strategy**: Bronze gets fixed 30-minute checks (infrequent changes); Silver/Gold get TRIGGER_ON_CHANGES (event-driven, pay only when data moves).

### What I Would Change at Scale

- **Multi-cluster warehouse**: Replace single COMPUTE_WH with auto-scaling warehouse for concurrent task + query workloads.
- **Warehouse per workload**: Separate ingestion, transformation, and serving warehouses for cost attribution and isolation.
- **Resource monitors**: Set credit quotas per warehouse to prevent runaway costs.
- **Iceberg compaction tuning**: Monitor Parquet file sizes and adjust compaction frequency for query performance vs. cost.

---

## 8. Semantic Modeling

### Business-Aligned Design

The semantic model (`ev_semantic_model.yaml`) maps technical table columns to business concepts:

**Two entities**:
- `fact_ev_registrations` — 13 dimensions, 1 time dimension, 12 measures
- `dim_manufacturers` — 3 dimensions (manufacturer ID, name, country)

**Key measures** (business-aligned naming):
| Measure | Expression | Business Question It Answers |
|---------|-----------|------------------------------|
| total_registrations | COUNT(VIN) | "How many EVs are registered?" |
| avg_electric_range | AVG(ELECTRIC_RANGE) | "What's the typical range?" |
| bev_market_share | BEV / Total * 100 | "What % of the market is fully electric?" |
| cafv_eligible_pct | Eligible / Total * 100 | "How many qualify for incentives?" |
| market_share_pct | Group / Total * 100 | "Who's winning the market?" |
| unique_manufacturers | COUNT(DISTINCT MAKE) | "How diverse is the market?" |

### Verified Queries

Seven pre-validated SQL queries serve as ground truth for Cortex Analyst:
1. YoY growth trend in EV registrations
2. BEV vs PHEV market penetration
3. Tesla vs other manufacturers by state
4. CAFV incentive eligibility breakdown
5. Top vehicle models by region
6. EV adoption rates by state
7. Market share by manufacturer

These ensure Cortex Analyst returns accurate SQL for the most common business questions, eliminating hallucinated joins or incorrect aggregations.

### Enabling Conversational Analytics

The semantic model powers a Streamlit chat app (`EV_MARKET_CHAT`) where business users type natural language questions:

- "Which manufacturer has the highest average range?" → Cortex Analyst generates SQL against the semantic model → result displayed as table + auto-chart
- Multi-turn support: "Now break that down by state" works because full conversation history is passed
- Guardrails: Cortex Analyst can only query tables/measures defined in the semantic model — it cannot access bronze, silver, or error tables

---

## 9. Cortex Code Adoption

### How I Used AI Assistance

This pipeline was built iteratively with Snowflake's Cortex Code (AI coding assistant in Snowsight). Here is how the workflow looked:

**Prompt strategy — iterative, not monolithic**:
- Started with the architecture outline and ingestion layer, validated it worked, then moved to transformations.
- Each prompt was scoped to a single concern: "Create the bronze ingestion with COPY INTO and error handling" rather than "Build the entire pipeline."
- When the Dynamic Table initially used `CURRENT_TIMESTAMP()` (forcing FULL refresh), I iterated with Cortex Code to identify and remove the non-deterministic function to enable INCREMENTAL mode.

**How I iterated on data quality**:
- First pass: Added basic system DMFs (NULL_COUNT, ROW_COUNT, FRESHNESS).
- Second pass: Added custom business-rule DMFs (INVALID_ELECTRIC_RANGE, NEGATIVE_MSRP).
- Third pass: Added cross-layer validation DMFs (ROW_COUNT_DRIFT, GOLD_VEHICLE_COUNT_DRIFT, GOLD_MAKE_COVERAGE).
- Fourth pass: Built the error quarantine system with event-driven detection and email notifications.

**How I iterated on the semantic model**:
- Started with basic dimensions and measures.
- Added verified queries one at a time, testing each against Cortex Analyst to confirm correct SQL generation.
- Refined measure definitions based on Cortex Analyst's responses — for example, changing `market_share_pct` to use a window function after Analyst initially generated incorrect SQL.

**Key principle**: AI assistance accelerates development but does not replace understanding. Every object in this pipeline exists because of a specific architectural decision, not because the AI suggested it.

---

## 10. Data Quality

### Comprehensive Validation Strategy

The pipeline implements seven categories of data quality checks across all three layers:

| Category | DMF / Mechanism | Layer | What It Catches |
|----------|----------------|-------|-----------------|
| **Completeness** | SNOWFLAKE.CORE.NULL_COUNT | Bronze, Silver, Gold | Missing values in VIN, MAKE, MODEL, SOURCE_FILE |
| **Uniqueness** | SNOWFLAKE.CORE.DUPLICATE_COUNT | Silver | Duplicate VINs or DOL_VEHICLE_IDs |
| **Freshness** | SNOWFLAKE.CORE.FRESHNESS | Bronze, Gold | Stale data indicating pipeline failures |
| **Business rules** | INVALID_ELECTRIC_RANGE (custom) | Silver | Electric range <= 0 or NULL |
| **Business rules** | NEGATIVE_MSRP (custom) | Silver | Negative retail price |
| **Referential integrity** | ORPHAN_MAKE_CHECK (custom, multi-table) | Silver | MAKEs not in DIM_MANUFACTURERS_GOLD |
| **Statistical monitoring** | AVG, MIN, MAX (system) | Gold | Sudden changes in metric distributions |
| **Cross-layer consistency** | ROW_COUNT_DRIFT (custom) | Silver, Gold | Data loss or duplication between layers |
| **Coverage** | GOLD_MAKE_COVERAGE (custom) | Silver | Manufacturers missing from gold aggregation |

### Monitoring Architecture

```
DMFs (automated, continuous)
    ↓ results persisted to
SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
    ↓ surfaced by
V_DQ_AUDIT (historical trend analysis)

Error Detection (event-driven, per-ingestion)
    ↓ writes to
ERROR_ROWS + DUPLICATE_ROWS (quarantine tables)
    ↓ streams capture new entries
ERROR_ROWS_STREAM + DUPLICATE_ROWS_STREAM
    ↓ trigger
SP_NOTIFY_ERRORS → email alert

Dashboard Views (on-demand, analyst-facing)
    V_DQ_DASHBOARD — summary with reconciliation
    V_ERROR_TREND — hourly time-series
    V_TOP_OFFENDERS — manufacturer ranking by issues
    V_ROW_COUNT_RECONCILIATION — cross-layer consistency
```

### Scheduling Strategy Rationale

| Layer | Schedule | Why |
|-------|----------|-----|
| Bronze | Every 30 min | Stable after ingestion; periodic sanity check |
| Silver | TRIGGER_ON_CHANGES | Runs only when DT refreshes — efficient |
| Gold | TRIGGER_ON_CHANGES | Runs only when SP updates Iceberg table |
| Error detection | AFTER ingestion task | Zero-latency; runs in same execution cycle as the data that caused errors |

---

## 11. Communication

### Explaining Trade-Offs to Different Audiences

**To a business stakeholder** — "Why should I trust this data?"
> Every time new data arrives, the pipeline automatically checks for missing values, duplicates, impossible numbers, and cross-layer consistency. If anything fails, I get an email within seconds. You can see the health status at any time through the DQ dashboard, and we even share quality metrics with external consumers so they can judge fitness for their use case.

**To a data engineer** — "Why Dynamic Tables instead of dbt?"
> The silver layer is a single Dynamic Table with incremental refresh and sub-minute lag. It replaces a Snowpark SP with a MERGE statement. The DT handles scheduling, incremental tracking, and retry automatically. Streams on the DT feed the gold task reactively. dbt would add an external scheduler, require Jinja templates for incremental logic, and lose sub-minute latency — with no compensating benefit for a three-layer, single-domain pipeline.

**To a solutions architect** — "How does this handle multi-engine access?"
> The gold layer has two tables. The aggregated metrics table is Iceberg on GCS with Snowflake-managed catalog — Catalog Sync publishes metadata to Open Catalog so Spark/Trino/BigQuery can read it via the Iceberg REST protocol. The row-level registrations table is a traditional Snowflake table because it's consumed exclusively within Snowflake and benefits from full platform support (Fail-safe, cloning, streams). We chose Iceberg only where interoperability justifies the trade-offs.

**To a cost-conscious manager** — "Is this efficient?"
> Every task has a `WHEN SYSTEM$STREAM_HAS_DATA()` guard — if no new data arrives, zero compute is consumed. The Dynamic Table uses incremental refresh (only new rows processed). DMFs trigger only on data changes, not fixed schedules. The Iceberg table stores data on your GCS bucket at cloud-native rates, not Snowflake storage rates. A single shared warehouse handles all workloads.

### Key Decision Points to Articulate

| Decision | Trade-Off | Why This Direction |
|----------|-----------|-------------------|
| Iceberg vs. Traditional | Portability vs. full Snowflake features | Iceberg only for the cross-engine table; traditional for everything else |
| Dynamic Table vs. SP | Simplicity vs. procedural control | DT for silver (zero code); SP for gold (Iceberg write requirement) |
| DMFs vs. dbt tests | Continuous monitoring vs. batch assertions | DMFs for production observability; dbt tests would only run during builds |
| Stream+Task vs. Airflow | Native simplicity vs. multi-system orchestration | Stream+Task for Snowflake-only pipeline; Airflow if we add external systems |
| Truncate-reload vs. MERGE for gold | Simplicity vs. incremental efficiency | Gold is a full re-aggregation — MERGE adds complexity with no benefit |
| Reader Account vs. Marketplace listing | Simplicity vs. discoverability | Reader Account for known partners; Marketplace if we wanted public distribution |
| Secure Views vs. direct table sharing | Security vs. simplicity | Secure views prevent pushdown attacks and hide internal metadata |
