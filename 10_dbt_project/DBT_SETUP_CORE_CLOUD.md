# dbt Setup (Core + Cloud)

This file leaves the project technically ready without storing secrets in the repo.

## 0) Demo account reference

Shared non-secret reference values for this demo:

- Account name: jaimeland
- Account ID: 70506183151209
- User display name: Jaime Rivas Verdugo
- User email: jaimerivas.dbt@gmail.com

Note:
- For dbt connection, keep using Snowflake account identifier `jzfcdcp-vn23603`.
- `DBT_SNOWFLAKE_USER` must be the Snowflake login username (for this setup: `JRIVASVERDUGO`), not the display name.

## 1) dbt Core (Local) - Required

### 1.1 Required environment variables (PowerShell)

Set these in your terminal before running dbt:

```powershell
$env:DBT_SNOWFLAKE_ACCOUNT='jzfcdcp-vn23603'
$env:DBT_SNOWFLAKE_USER='JRIVASVERDUGO'
$env:DBT_SNOWFLAKE_ROLE='ACCOUNTADMIN'
$env:DBT_SNOWFLAKE_DATABASE='EV_PROJECT_DB'
$env:DBT_SNOWFLAKE_WAREHOUSE='COMPUTE_WH'
$env:DBT_SNOWFLAKE_SCHEMA='DBT_GOLD'
$env:DBT_SNOWFLAKE_PASSWORD='<YOUR_PASSWORD>'
```

### 1.2 Run dbt validation

```powershell
Set-Location C:/GitHub/snowflake-ev-data-pipeline/10_dbt_project

# Ensure dbt sees this profiles.yml
$env:DBT_PROFILES_DIR=(Get-Location).Path

dbt debug --profiles-dir .
dbt parse --profiles-dir .
dbt run --profiles-dir .
dbt test --profiles-dir .
```

Expected:
- `dbt debug` passes connection checks
- `dbt run` builds staging/gold models
- `dbt test` runs schema tests from `models/schema.yml`

## 2) dbt Cloud (Optional but Ready)

Use the same project folder (`10_dbt_project`) in dbt Cloud git integration.

### 2.1 Create Environment in dbt Cloud

Set these connection fields in dbt Cloud Snowflake credentials:
- Account: `jzfcdcp-vn23603`
- User: `JRIVASVERDUGO`
- Role: `ACCOUNTADMIN` (or a least-privileged dbt role)
- Database: `EV_PROJECT_DB`
- Warehouse: `COMPUTE_WH`
- Schema: `DBT_GOLD`
- Auth: password

### 2.2 dbt Cloud job suggestion

Create one job with commands:
1. `dbt deps`
2. `dbt run`
3. `dbt test`

Schedule only after pipeline readiness if cost control is required.

## 3) Secrets Placement Rules

- Do not commit passwords/tokens in repo files.
- Keep secrets only in:
  - local environment variables, or
  - dbt Cloud environment credentials.

## 4) Troubleshooting

- If `dbt debug` fails with auth errors:
  - verify `DBT_SNOWFLAKE_ACCOUNT` is `jzfcdcp-vn23603`
  - verify user/role/warehouse permissions
  - verify `DBT_SNOWFLAKE_PASSWORD` is set in the current terminal

- If relation not found:
  - confirm schemas/tables were created in Snowflake stages 1-9
  - check model SQL references under `models/staging` and `models/gold`
