# Quickstart Validation Guide

Date: 2026-07-15
Feature: specs/001-rebuild-ev-pipeline/spec.md

## Purpose

Run a complete Dev rebuild validation using manual stage execution and verify completion gates.

## Prerequisites

- Access to Snowflake Dev account
- Access to Azure source storage
- Access to NeonDB PostgreSQL catalogue
- Local ability to run dbt and Streamlit workflow used by this repository
- Required credentials configured outside repository files

### Clarified Operating Rules (Current Run)

- Snowflake authentication for this run is interactive terminal password entry.
- ACCOUNTADMIN is allowed temporarily for Dev readiness and early-stage validation.
- Secrets must never be stored in repository files.
- Execution scope for today is limited to readiness closure plus Stage 2 maximum unless explicitly re-approved.

## Validation Flow

### 1) Confirm external sources

- Confirm source EV data is present in landing storage.
- Confirm NeonDB catalogue is reachable and contains test records.

Expected outcome:
- Both source systems are accessible and ready.

### 2) Execute stage sequence in Dev

Run stages in order:

1. Stage 0: NeonDB schema/data + CDC readiness
2. Stage 1: Infrastructure
3. Stage 2: Bronze
4. Stage 3: Silver
5. Stage 4: Gold
6. Stage 4b: CDC integration (mandatory)
7. Stage 5: Data Quality
8. Stage 6: Iceberg
9. Stage 7: Sharing
10. Stage 8: Cost Governance
11. Stage 9/10: Analyst + dbt validation path

Expected outcome:
- All stage executions complete without blocking errors.

### 3) Validate CDC cadence behavior

- Apply a controlled catalogue change in NeonDB.
- Verify synchronized update appears in Snowflake within one 12-hour cycle.

Expected outcome:
- CDC propagation is confirmed within the agreed cadence window.

### 4) Validate dbt and DQ gates

- Execute required dbt checks.
- Verify DQ checks run and outcomes are observable.

Expected outcome:
- dbt checks pass.
- DQ outcomes are visible and usable for sign-off.

### 5) Validate analyst metrics via Streamlit

- Run predefined validation question set.
- Compare returned values against expected curated metrics.

Expected outcome:
- At least 95% of validation questions match expected metrics.

## Completion Criteria

The rebuild is complete only when all of the following are true:

- Stage sequence completed successfully.
- CDC mandatory stage operational on 12-hour cadence.
- dbt checks pass.
- DQ checks and outcomes are verified.
- Streamlit responses meet metric validation threshold.

## Readiness Gate (Pre-Execution)

Before running any new stage command, confirm all items:

- Azure storage, queue, and Event Grid routing are operational.
- Snowflake access is verified with current run credentials.
- Required permissions for current stage are validated.
- External CDC access prerequisites are available for later stages.
- Evidence logging target is prepared for stage acceptance checks.

### Gate Evidence Log (Phase 2.5)

Date: 2026-07-15

Gate checks:

1. Azure storage, queue, and Event Grid routing operational: PASS
2. Snowflake access and role privileges for Stage 1/2: PASS
3. Required permissions for current stage validated: PASS (ACCOUNTADMIN for current Dev run)
4. External CDC access prerequisites available for later stages: CONDITIONAL PASS (credentials/connectivity still required before Stage 4b execution)
5. Evidence logging prepared for stage acceptance checks: PASS

Tooling notes:

- `snow` available in PATH.
- `dbt` and `streamlit` available in local virtualenv (`C:\GitHub\.venv\Scripts`).
- `psql` not installed locally (optional for direct NeonDB checks).

Formal Go/No-Go Decision:

- GO (Scoped): Authorized to proceed only within approved boundary (readiness closure + Stage 2 maximum).
- Any execution beyond Stage 2 requires explicit re-approval.

## Stage Execution Evidence Log

### Stage 2 (Bronze) - T015/T016

Date: 2026-07-22

Execution summary:

- `02_bronze/01_bronze.sql` executed successfully after Azure integration consent + RBAC fixes.
- Created objects in `EV_PROJECT_DB.BRONZE`:
	- Stage: `AZURE_EV_STAGE` (1)
	- Table: `RAW_EV_DATA` (1)
	- Stream: `AZURE_FILES_STREAM` (1)
	- Tasks: `TSK_INGEST_EV_DATA`, `TSK_ERROR_DETECTION`, `TSK_ERROR_NOTIFICATION` (3)
- Current raw row count: `0` (expected before first Azure file-drop).
- Task states: all `suspended` by cost-control decision; resume deferred until final cutover approval.

Acceptance result (T016):

- `PASS (Provisioning)` for Stage 2 object creation and event-trigger wiring.
- `PENDING (Data Arrival)` for "raw table populated" until first file lands in Azure Blob.

### Stage 3 (Silver) - T017/T018

Date: 2026-07-22

Execution summary:

- `03_silver/01_silver.sql` executed successfully.
- Created objects in `EV_PROJECT_DB.SILVER`:
	- Dynamic table: `CLEAN_EV_DATA_DT`
	- Stream: `CLEAN_EV_DATA_DT_STREAM`
- Current silver row count: `0` (expected while Bronze has no ingested rows yet).

Acceptance result (T018):

- `PASS (Provisioning)` for Stage 3 object creation and incremental dynamic-table wiring.
- `PENDING (Data Arrival)` for latency/refresh validation until first Azure file-drop populates Bronze.

### Stage 4 (Gold) - T019/T020

Date: 2026-07-22

Execution summary:

- `04_gold/01_gold.sql` executed successfully.
- Created objects in `EV_PROJECT_DB.GOLD`:
	- Tables: `FACT_EV_REGISTRATIONS`, `FACT_EV_MARKET_METRICS`, `DIM_MANUFACTURERS_GOLD`
	- Procedure: `SP_TRANSFORM_SILVER_TO_GOLD()`
	- Task: `TASK_SILVER_TO_GOLD`
	- Stage: `SEMANTIC_MODELS`
- Current Gold row counts:
	- `FACT_EV_REGISTRATIONS`: `0`
	- `FACT_EV_MARKET_METRICS`: `0`
- Gold task state: `suspended` (cost-control policy).

Acceptance result (T020):

- `PASS (Provisioning)` for Stage 4 object creation and stream-trigger wiring.
- `PENDING (Data Arrival)` for populated aggregate validation until Bronze/Silver receive first ingested file.

### Stage 5 (Data Quality) - T021/T022

Date: 2026-07-22

Execution summary:

- `05_data_quality/01_data_quality.sql` executed successfully.
- Created DQ objects in `EV_PROJECT_DB.DATA_QUALITY`:
	- Tables: `ERROR_ROWS`, `DUPLICATE_ROWS`
	- Streams: `ERROR_ROWS_STREAM`, `DUPLICATE_ROWS_STREAM`
	- Procedures: `SP_DETECT_ERRORS()`, `SP_NOTIFY_ERRORS()`
	- Views (monitoring): includes `V_ROW_COUNT_RECONCILIATION`, `V_DATA_FRESHNESS`, `V_DQ_DASHBOARD`
- Current DQ table counts:
	- `ERROR_ROWS`: `0`
	- `DUPLICATE_ROWS`: `0`

Acceptance result (T022):

- `PASS (Provisioning)` for Stage 5 object creation and DQ workflow wiring.
- `PENDING (Runtime Validation)` for detection/notification behavior until ingestion events are triggered.

### Stage 6 (Iceberg) - T023/T024

Date: 2026-07-22

Execution summary:

- `06_iceberg/01_iceberg.sql` executed; one compatibility issue was identified and corrected.
- Initial blocker: Iceberg rejected `TIMESTAMP_LTZ(9)` scale for `FACT_EV_MARKET_METRICS.LOAD_TIMESTAMP`.
- Applied runtime-safe correction during creation: cast `LOAD_TIMESTAMP` to `TIMESTAMP_NTZ(6)` for Iceberg compatibility.
- Final created tables in `EV_PROJECT_DB.ICEBERG`:
	- `FACT_EV_REGISTRATIONS`
	- `FACT_EV_MARKET_METRICS`
	- `DIM_MANUFACTURERS_GOLD`
- Verification query result: `ICEBERG_TABLES = 3`.

Acceptance result (T024):

- `PASS` for Stage 6 table creation and queryability.
- Note: keep `TIMESTAMP_NTZ(6)` compatibility approach for Iceberg materializations with timestamp columns.

### Stage 7 (Sharing) - T025/T026

Date: 2026-07-22

Execution summary:

- `07_sharing/01_sharing.sql` executed successfully.
- Created governed sharing objects in `EV_PROJECT_DB.SHARING`:
	- Secure views: `SV_FACT_EV_MARKET_METRICS`, `SV_DIM_MANUFACTURERS`, `SV_DATA_QUALITY_SUMMARY`
	- Outbound share: `EV_MARKET_DATA_SHARE`
- Required grants to share were applied successfully.

Acceptance result (T026):

- `PASS` for Stage 7 object creation and governed share configuration.

### Stage 8 (Cost Governance) - T027/T028

Date: 2026-07-22

Execution summary:

- `08_cost_governance/01_cost_governance.sql` executed successfully.
- Resource monitors created:
	- `EV_PIPELINE_MONITOR`
	- `EV_ACCOUNT_MONITOR`
- Warehouse monitor assignment verified:
	- `COMPUTE_WH` -> `EV_PIPELINE_MONITOR`

Acceptance result (T028):

- `PASS` for Stage 8 monitor creation and warehouse-level monitor binding.

### Stage 9 (Analyst Streamlit) - T029/T030

Date: 2026-07-22

Execution summary:

- `09_analyst_streamlit/01_analyst_streamlit.sql` executed successfully.
- Streamlit object created: `EV_PROJECT_DB.GOLD.EV_MARKET_CHAT`.
- Streamlit metadata validated (`SHOW`/`DESCRIBE` successful).
- Runtime assets uploaded to `@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS`:
	- `ev_semantic_model.yaml`
	- `ev_chat_app.py`
	- `environment.yml`
- Stage listing check (`LS @EV_PROJECT_DB.GOLD.SEMANTIC_MODELS`) confirms all 3 files present.
- Streamlit app recreated successfully with:
	- `ROOT_LOCATION='@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS'`
	- `MAIN_FILE='ev_chat_app.py'`
	- `QUERY_WAREHOUSE='COMPUTE_WH'`

Acceptance result (T030):

- `PASS` for Stage 9 provisioning and runtime asset deployment.

### Stage 10 (dbt Validation) - T031/T032

Date: 2026-07-22

Execution summary:

- dbt toolchain validated from `10_dbt_project` using local `profiles.yml` and password-based auth.
- Commands executed successfully:
	- `dbt debug --profiles-dir .`
	- `dbt parse --profiles-dir .`
	- `dbt run --profiles-dir .`
	- `dbt test --profiles-dir .`
- Connection details validated by dbt:
	- Account: `jzfcdcp-vn23603`
	- User: `JRIVASVERDUGO`
	- Role: `ACCOUNTADMIN`
	- Database: `EV_PROJECT_DB`
	- Warehouse: `COMPUTE_WH`
	- Schema: `DBT_GOLD`
- Build results:
	- Models built: `3/3` success (`stg_ev_registrations`, `fact_ev_registrations`, `fact_ev_market_metrics`).
- Test results:
	- Data tests: `10/10` pass, `0` warnings, `0` errors.

Acceptance result (T032):

- `PASS` for dbt connection, parsing, model execution, and data quality tests.

### Stage 9b (Analyst County Lookup Stabilization)

Date: 2026-07-23

Execution summary:

- Analyst returned semantic-model validation error for missing table reference `EV_PROJECT_DB.GOLD.DIM_COUNTY_GOLD`.
- Root cause validated in Snowflake: semantic YAML referenced county lookup table that was not present in the live schema at validation time.
- Corrective actions executed in Snowflake:
	- Created `EV_PROJECT_DB.GOLD.DIM_COUNTY_GOLD`.
	- Added `COUNTY_NAME` column to `EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS` when absent.
	- Backfilled `FACT_EV_REGISTRATIONS.COUNTY_NAME` from flattened Bronze source rows.
	- Populated `DIM_COUNTY_GOLD` from flattened Bronze source county code/name pairs.
	- Re-uploaded `ev_semantic_model.yaml` and `ev_chat_app.py` to `@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS`.
- Validation evidence recorded in-session:
	- `FACT_EV_REGISTRATIONS` county-name rows filled: `4986`.
	- `DIM_COUNTY_GOLD` rows populated: `115`.

Acceptance result:

- `PASS` for county lookup object availability and county semantics readiness in Analyst runtime.
