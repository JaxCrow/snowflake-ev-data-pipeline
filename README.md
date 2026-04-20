# Snowflake EV Data Pipeline

End-to-end data engineering pipeline built on Snowflake demonstrating medallion architecture, multiple transformation engines, open table formats, and conversational analytics.

## Architecture

```
GCS (JSON) --> Bronze (Raw) --> Silver (Dynamic Table) --> Gold (Snowpark Python)
                                                            |
                                                            +--> Iceberg (Open Format on GCS)
                                                            +--> dbt Gold (Testable SQL)
                                                            +--> Sharing (Secure Views)
                                                            +--> Cortex Analyst + Streamlit
```

## Project Structure

| Folder | Description |
|--------|-------------|
| `01_infrastructure/` | Warehouse, storage integration, notification integrations, external volume, schemas |
| `02_bronze/` | External stage, directory stream, ingestion SP (Snowpark Python), task DAG |
| `03_silver/` | Dynamic Table (INCREMENTAL, 1-min lag), stream |
| `04_gold/` | Snowpark Python transformation SP, fact/dimension tables, stream-triggered task |
| `05_data_quality/` | Snowpark Python DQ SP (5 validation types), error quarantine, 8 monitoring views |
| `06_iceberg/` | 3 Iceberg tables on GCS external volume for open-format interoperability |
| `07_sharing/` | 3 secure views + outbound share |
| `08_cost_governance/` | Resource monitors (warehouse + account level) |
| `09_analyst_streamlit/` | Streamlit chat app + Cortex Analyst semantic model YAML |
| `09_dbt_project/` | dbt project with 3 models and 10 passing tests |
| `docs/` | Data flow diagram, object catalog, presentation speech |
| `scripts/` | Interview reset protocol |

## Key Features

- **3 Transformation Engines**: Dynamic Tables (near real-time), Snowpark Python (DataFrame API), dbt (testable SQL)
- **Event-Driven Orchestration**: Streams + Tasks with WHEN guards (zero cost when idle)
- **Comprehensive DQ**: 5 validation types, cross-layer reconciliation, freshness monitoring, email alerts
- **Open Table Formats**: Iceberg tables on GCS (Parquet), queryable by Spark/Trino/Flink
- **Data Sharing**: Outbound share with secure views over Iceberg tables
- **Conversational Analytics**: Cortex Analyst semantic model + Streamlit chat interface
- **Cost Governance**: 2 resource monitors with tiered alerts (notify → suspend → force)

## Deployment Order

Run SQL files in numbered order (01 through 09). Each file is self-contained.

## Tech Stack

- Snowflake (warehouse, Dynamic Tables, Streams, Tasks, Iceberg, Sharing)
- Snowpark Python (stored procedures)
- dbt Core (transformation + testing)
- Cortex Analyst (text-to-SQL)
- Streamlit (chat UI)
- GCS (object storage)
- GCP Pub/Sub (event notifications)
