# Snowflake EV Data Pipeline

End-to-end data engineering pipeline built on Snowflake demonstrating medallion architecture, multiple transformation engines, open table formats, external data integration via PostgreSQL CDC, and conversational analytics on Azure.

Current official CDC path: external CDC engine (Airbyte OSS in Docker) replicates NeonDB changes into Snowflake staging/reference, then Snowflake applies SCD2 and effective-dated consumption logic.

## Current Status (2026-07-23)

- End-to-end dev pipeline is deployed in Snowflake through Stage 10 (Infrastructure, Bronze, Silver, Gold, CDC, DQ, Iceberg, Sharing, Cost, Analyst, dbt).
- dbt validation is green (`dbt debug`, `dbt parse`, `dbt run`, `dbt test` succeeded in this project workflow).
- Streamlit app `EV_PROJECT_DB.GOLD.EV_MARKET_CHAT` is deployed and pointing to `@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS`.
- Cortex Analyst semantic model is published with county lookup support:
    - `fact_ev_registrations` includes `county_code` and `county_name` semantics.
    - `dim_county` points to `EV_PROJECT_DB.GOLD.DIM_COUNTY_GOLD`.
- `EV_PROJECT_DB.GOLD.DIM_COUNTY_GOLD` is populated for county code/name lookup, and `FACT_EV_REGISTRATIONS.COUNTY_NAME` is backfilled in the live environment.

### Demo-Ready Focus

- Conversational analytics path is operational for county-oriented prompts (`county`, `counties`, `county code`, `county name`).
- Cost governance is active with account/warehouse monitors and observability assets under `08_cost_governance/`.
- Azure ingestion path remains the primary landing path for EV source data.

## Architecture

```
Azure Blob Storage (EV Data) + PostgreSQL (Catalog)
         ↓
 Event Grid + Snowpipe / Airbyte OSS CDC (12h)
         ↓
[BRONZE] Raw JSON → [SILVER] Dynamic Table → [GOLD] Snowpark + dbt
         ↓
     Normalized Core + Catalog Enrichment
         ↓
    ├── Iceberg (Open Format on Azure Blob)
    ├── dbt Gold (Testable SQL)
     ├── Secure Sharing (Consumption Views)
    └── Cortex Analyst + Streamlit (Chat UI)
```

## Data Modeling Strategy

- Normalized-first design: core entities and relationships are maintained in normalized base tables.
- Catalog-driven enrichment: reference attributes are managed through catalog dimensions synchronized from PostgreSQL CDC.
- Controlled denormalization: denormalized projections are created only as consumption views for analytics, sharing, and conversational workloads.
- Canonical storage stays normalized: business logic for joins and flattening belongs to curated views, not base persistence.

## Project Structure

| Folder | Description |
|--------|-------------|
| `01_infrastructure/` | Warehouse, storage integration, notification integrations, external volume, schemas |
| `02_bronze/` | External stage, directory stream, ingestion SP (Snowpark Python), task DAG |
| `03_silver/` | Dynamic Table (INCREMENTAL, 1-min lag), stream |
| `04_gold/` | Normalized Gold core entities, transformation SPs, stream-triggered task, and curated consumption views |
| `04b_external_data_integration/` | External CDC ingestion contracts (Airbyte OSS -> Snowflake staging), SCD2 merge logic, and reference-data enrichment for consumption views |
| `05_data_quality/` | Snowpark Python DQ SP (5 validation types), error quarantine, 8 monitoring views |
| `06_iceberg/` | 3 Iceberg tables on Azure Blob Storage external volume for open-format interoperability |
| `07_sharing/` | 3 secure views + outbound share |
| `08_cost_governance/` | Resource monitors (warehouse + account level) |
| `09_analyst_streamlit/` | Streamlit chat app + Cortex Analyst semantic model YAML |
| `10_dbt_project/` | dbt project with 3 models and 10 passing tests |
| `docs/` | Data flow diagram, object catalog, presentation speech |
| `scripts/` | Interview reset protocol |

## Key Features

- **3 Transformation Engines**: Dynamic Tables (near real-time), Snowpark Python (DataFrame API), dbt (testable SQL)
- **External Data Integration**: PostgreSQL CDC for vehicle catalog using Airbyte OSS (Docker) with 12-hour sync schedule (cost-optimized, trial-compatible)
- **Event-Driven Orchestration**: Streams + Tasks with WHEN guards (zero cost when idle)
- **Comprehensive DQ**: 5 validation types, cross-layer reconciliation, freshness monitoring, email alerts
- **Open Table Formats**: Iceberg tables on Azure Blob Storage (Parquet), queryable by Spark/Trino/Flink
- **Data Sharing**: Outbound share with secure views over Iceberg tables
- **Conversational Analytics**: Cortex Analyst semantic model + Streamlit chat interface
- **Cost Governance**: 2 resource monitors with tiered alerts (notify → suspend → force)

## Deployment Order

Run SQL files in numbered order (01 through 10). Each file is self-contained.

**Note:** `04b_postgresql_cdc.sql` (external data integration) is mandatory for the full catalog-enrichment design and runs after external CDC landing is configured.

## Tech Stack

- Snowflake (warehouse, Dynamic Tables, Streams, Tasks, Iceberg, Sharing)
- Snowpark Python (stored procedures)
- dbt Core (transformation + testing)
- Cortex Analyst (text-to-SQL)
- Streamlit (chat UI)
- Azure Blob Storage (object storage)
- Azure Event Grid (event notifications)
