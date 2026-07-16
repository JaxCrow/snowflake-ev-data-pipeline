# Snowflake EV Data Pipeline — Deployment Specification

**Project**: Snowflake EV Data Pipeline (Full Deployment)  
**Date**: 2026-07-14  
**Version**: 1.0  
**Timeline**: Urgent (this week)  
**Budget**: Free tier ($0-20/month)  
**Related Clarification**: `docs/clarification-deployment.md`  

---

## 1. Executive Summary

Deploy a **production-ready end-to-end data pipeline** on Snowflake that ingests electric vehicle registration data from Azure Blob Storage, transforms it through a medallion architecture (Bronze → Silver → Gold), and surfaces insights via Cortex Analyst + Streamlit chat interface.

**Data Domain**: ~22,000 EV registration records, ~4,986 unique vehicles  
**Architecture**: Medallion + 3 transformation engines (Dynamic Tables, Snowpark, dbt)  
**Deployment Time**: 1-2 days (guided walkthrough)  
**Cost Impact**: ~$5-15/month on Azure, Snowflake free trial (~$400 credits = 200 hrs X-Small compute)

---

## Clarification Baseline (2026-07-15)

- Environment: Dev only
- Execution style: Manual setup
- NeonDB CDC cadence: Every 12 hours
- Rollout scope: Full end-to-end in one pass
- Completion gate: SQL + dbt + DQ + Streamlit expected metrics

---

## 2. Business Objectives

✅ **Objective 1**: Ingest EV registration data from Azure in real-time (~1-min latency)  
✅ **Objective 2**: Validate data quality (5 validation types) + quarantine failures  
✅ **Objective 3**: Transform raw data into business-ready analytics (market metrics, trends, models)  
✅ **Objective 4**: Enable conversational analytics (ask questions in plain English → SQL queries)  
✅ **Objective 5**: Cost-optimize pipeline (event-driven, zero idle compute, free-tier resources)  

---

## 3. Acceptance Criteria

- [ ] **AC1**: Data from Azure Blob → Snowflake Bronze within 30 seconds of upload
- [ ] **AC2**: Silver layer (CLEAN_EV_DATA_DT) refreshes within 1 minute (incremental)
- [ ] **AC3**: Gold layer has ≥2 fact tables + market metrics calculated
- [ ] **AC4**: Data quality checks fire on every data load; failing records quarantined
- [ ] **AC5**: 10+ dbt tests pass (all models tested)
- [ ] **AC6**: Cortex Analyst semantic model deployed; Streamlit app running
- [ ] **AC7**: Iceberg tables exported for open-format interoperability
- [ ] **AC8**: Cost monitoring active (resource monitors alert if spend exceeds $5/day)
- [ ] **AC9**: 100% traceability: data lineage documented from source to consumer
- [ ] **AC10**: All 9 constitution principles addressed (cost, DQ, scale, compliance, reproducibility, observability, documentation, security, portability)

---

## 4. Architecture & Data Flow

### Medallion Layers

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EXTERNAL DATA SOURCES                           │
│          Azure Blob Storage (EV Data) + Event Grid Notifications       │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                        ┌──────────▼──────────┐
                        │     Snowpipe       │
                        │  (COPY INTO)       │
                        └──────────┬──────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
      ┌───────▼────────┐   ┌──────▼────────┐   ┌──────▼─────────┐
      │    BRONZE      │   │    SILVER     │   │     GOLD       │
      │  (RAW_EV_DATA) │──>│   (DT: Clean) │──>│ (Snowpark +    │
      │                │   │                │   │  dbt Models)   │
      │ • Raw JSON     │   │ • Validated   │   │                │
      │ • Audit trail  │   │ • Deduplicated│   │ • FACT_EV_REG   │
      │ • Stream       │   │ • 1-min lag   │   │ • FACT_METRICS  │
      │ • 3 Tasks      │   │ • Stream      │   │ • dbt tests     │
      └────────────────┘   └───────────────┘   └──────┬─────────┘
                                                       │
                        ┌──────────────────────────────┼──────────────────┐
                        │                              │                  │
              ┌─────────▼──────┐     ┌────────────────▼──┐   ┌──────────▼──┐
              │   ICEBERG      │     │   DATA_QUALITY    │   │  SHARING   │
              │  (Open Format) │     │   (Monitoring)    │   │ (Secure    │
              │                │     │                   │   │  Views)    │
              │ • Azure Blob location │ │ • 5 validation  │   │            │
              │ • Parquet      │     │ • Error quarantine│   │ • Shared   │
              │ • Interop      │     │ • 8 monitoring    │   │   views    │
              │                │     │ • Email alerts    │   │            │
              └────────────────┘     └───────────────────┘   └────────────┘
                        │
                        │
              ┌─────────▼────────────────────┐
              │  ANALYTICS LAYER            │
              │  (Cortex Analyst + Streamlit) │
              │                              │
              │ • Semantic model YAML        │
              │ • Chat interface             │
              │ • Business insights          │
              └──────────────────────────────┘
```

### Data Flow with Latency Profile

| Stage | Source | Target | Mechanism | Latency | Cost |
|-------|--------|--------|-----------|---------|------|
| **1** | Azure Blob | Bronze (RAW_EV_DATA) | Snowpipe + Stream + Task | ~30 sec | $0.25/10M files |
| **2** | Bronze | Silver (CLEAN_EV_DATA_DT) | Dynamic Table (incremental) | ~1 min | 1-2 credits/day |
| **3** | Silver | Gold (FACT tables) | Stream-triggered task + Snowpark | ~30 sec | 0.5-1 credit/task |
| **4** | Gold | Iceberg | Manual INSERT INTO | Batch | 0.25 credit/sync |
| **5** | Iceberg | Analytics | Cortex queries | ~2-5 sec | 0.1 credit/query |

---

## 5. Deployment Stages (11 SQL Stages + 2 App Deployments)

### Stage 0: PostgreSQL Setup on Neon DB (Pre-Infrastructure)

**Deliverables**:
- Neon DB connection established
- PostgreSQL schema created: `catalogue` (or custom name)
- Tables: `vehicles` (vehicle_id, make, model, year, category, subcategory)
- CDC (Change Data Capture) enabled on all tables
- Neon DB connection string + credentials ready for Snowflake connector

**Effort**: 20 minutes (create tables, enable CDC, verify connectivity)  
**Success Criteria**: 
- [ ] Connect to Neon DB via psql or client
- [ ] Schema + tables created
- [ ] Sample data loaded (or ready to load)
- [ ] CDC enabled
- [ ] Connection string documented

**Data Source Options**:
- Load from EV Population JSON file (extract unique vehicles)
- Or create sample catalogue manually
- Or load from external CSV if available

---

### Stage 1: Infrastructure (01_infrastructure.sql)

**Deliverables**:
- Warehouse: COMPUTE_WH (X-Small, auto-suspend 300s)
- Storage Integration: AZURE_EV_STORAGE_INT (Azure Blob Storage)
- Notification Integrations: AZURE_EV_EVENTGRID_INT (Event Grid), EV_DQ_EMAIL_INT (Email)
- External Volume: AZURE_ICEBERG_VOLUME (for Iceberg tables)
- Database: EV_PROJECT_DB
- Schemas: BRONZE, SILVER, GOLD, ICEBERG, DBT_GOLD, DATA_QUALITY, SHARING

**Effort**: 15 minutes (copy/paste SQL)  
**Success Criteria**: Warehouse running, all schemas created, integrations connected

---

### Stage 2: Bronze Layer (02_bronze.sql)

**Deliverables**:
- External Stage: AZURE_EV_STAGE (points to Azure Blob)
- File Format: JSON_FORMAT
- Table: RAW_EV_DATA (VARIANT schema)
- Stream: AZURE_FILES_STREAM (detects new files)
- Stored Procedure: SP_INGEST_RAW_EV_DATA (Snowpark Python)
- Task DAG: 3 tasks (ingest → error_detect → notify)

**Effort**: 20 minutes (execute SQL, test data load)  
**Success Criteria**: First JSON file loads into RAW_EV_DATA via Snowpipe

---

### Stage 3: Silver Layer (03_silver.sql)

**Deliverables**:
- Dynamic Table: CLEAN_EV_DATA_DT (incremental, 1-min lag)
- Transformations: Deduplicate, validate schema, flatten JSON
- Stream: On Dynamic Table for downstream triggers

**Effort**: 10 minutes (create dynamic table, validate incremental refresh)  
**Success Criteria**: CLEAN_EV_DATA_DT auto-refreshes within 1 minute

---

### Stage 4: Gold Layer (04_gold.sql)

**Deliverables**:
- Stored Procedure: SP_AGGREGATE_GOLD_TABLES (Snowpark Python)
- Fact Tables: FACT_EV_REGISTRATIONS, FACT_EV_MARKET_METRICS
- Task: Stream-triggered aggregation (Silver → Gold)

**Effort**: 15 minutes (execute SQL, validate fact table calculations)  
**Success Criteria**: Fact tables populated, aggregations correct

---

### Stage 4b: External Data Integration (04b_postgresql_cdc.sql) — NOW MANDATORY

**Deliverables**:
- PostgreSQL CDC Connector (connects to Neon DB)
- Catalog dimension replication (12-hour sync schedule)
- VEHICLES_DIM table in SILVER schema (CDC replicated)
- Enrichment of Gold tables with catalog data (make, model, category)

**Effort**: 20 minutes (execute SQL, configure connector)  
**Success Criteria**: 
- [ ] Snowflake PostgreSQL connector created
- [ ] Initial CDC sync completes
- [ ] VEHICLES_DIM populated from Neon DB
- [ ] 12-hour sync task running

---

### Stage 5: Data Quality (05_data_quality.sql)

**Deliverables**:
- Stored Procedure: SP_DETECT_ERRORS (5 validation types)
  - Row count validation
  - Schema validation
  - Freshness check
  - Uniqueness validation
  - Business rule validation
- Stored Procedure: SP_NOTIFY_ERRORS (email alerts)
- Error Quarantine Table: ERROR_RECORDS (captures failures)
- Monitoring Views: 8 views (completeness, freshness, accuracy dashboards)

**Effort**: 25 minutes (create views, test alerts)  
**Success Criteria**: DQ failures trigger quarantine + email alerts

---

### Stage 6: Iceberg (06_iceberg.sql)

**Deliverables**:
- 3 Iceberg tables on Azure Blob Storage (open-format Parquet)
- INSERT INTO triggers post-Gold transformations
- Schema: [model, registrations, metrics] from Gold

**Effort**: 15 minutes (create Iceberg tables, populate via INSERT)  
**Success Criteria**: Iceberg tables queryable via Spark/Trino/Flink

---

### Stage 7: Sharing (07_sharing.sql)

**Deliverables**:
- 3 Secure Views (filtered/masked versions of Gold tables)
- Outbound Snowflake Data Sharing account
- Access control (role-based)

**Effort**: 15 minutes (create views, configure sharing)  
**Success Criteria**: External consumer can query shared views

---

### Stage 8: Cost Governance (08_cost_governance.sql)

**Deliverables**:
- Resource Monitor: Warehouse level (alert $3/day, suspend $5/day)
- Resource Monitor: Account level (alert $10/day, suspend $15/day)
- Monitoring task: Log daily spend to audit table

**Effort**: 10 minutes (create monitors, set thresholds)  
**Success Criteria**: Alerts trigger when thresholds approached

---

### Stage 9: Analyst & Streamlit (09_analyst_streamlit/)

**Deliverables**:
- dbt Project: 3 models (stg_ev_registrations, fact_ev_registrations, fact_ev_market_metrics)
- dbt Tests: 10+ tests (unique, not_null, relationships, custom)
- Semantic Model YAML: Cortex Analyst configuration
- Streamlit App: Chat interface (`ev_chat_app.py`)

**Effort**: 30 minutes (install dbt, run tests, deploy Streamlit)  
**Success Criteria**: dbt test suite passes (100%), Streamlit app running locally

---

### Stage 10: dbt Project (10_dbt_project/)

**Deliverables** (already in Stage 9, repeated for clarity):
- dbt profiles.yml: Connection to Snowflake
- dbt_project.yml: Project configuration
- Staging Models: stg_ev_registrations (test: unique, not_null, freshness)
- Gold Models: FACT_EV_REGISTRATIONS, FACT_EV_MARKET_METRICS (tested)

**Effort**: Included in Stage 9  
**Success Criteria**: All dbt tests pass

---

## 6. Cost Impact Analysis

### Azure Infrastructure (Free Tier Eligible)

| Resource | Usage | Cost |
|----------|-------|------|
| Storage Account | 1 account | ~$0 (first month free tier, then ~$1/month) |
| Blob Storage | 1 container, 100MB data | ~$0.024/GB/month = ~$2.40/month |
| Event Grid | 1 million ops/month | ~$0.60/month |
| Data Transfer | Inbound: free, Outbound: minimal | ~$0/month (local Snowflake queries) |
| **Azure Total** | | **~$3/month** |

### Snowflake (Free Trial Available)

| Resource | Usage | Cost |
|----------|-------|------|
| Warehouse (X-Small) | 1 cluster, 1 credit/hour, 8 hrs/day average | ~$2-3/day (standard edition $2/credit) = $60-90/month |
| Storage | 500MB raw + transformations | ~$0 (included in trial) |
| **Snowflake Trial** | ~$400 credits available | **~200 hours of compute** |
| **Snowflake Post-Trial** | | **~$60-90/month** |

### Free-Tier Optimizations Implemented ✅

1. **Cost-Optimized Warehouse**
   - X-Small (1 credit/hour, smallest size)
   - Auto-suspend: 300 seconds (stops after 5 min idle)
   - Auto-resume: ON (only resumes when tasks trigger)

2. **Event-Driven Orchestration**
   - Tasks only run when data arrives (Snowpipe triggers)
   - No scheduled polling
   - Estimated run time: 10-30 seconds per data load

3. **Dynamic Tables for Efficiency**
   - Incremental refresh (only new/changed data processed)
   - 1-minute target lag (vs. full refresh every hour)
   - Automatic optimization by Snowflake

4. **dbt for Portability**
   - Run locally (no compute cost)
   - Tests run in Snowflake (1 credit per test suite)
   - Estimated: 1-2 credits/day

5. **Streamlit on Free Tier**
   - Deploy to Streamlit Community Cloud (free tier available)
   - No serverless costs

**Total Estimated Cost After Trial**:
- Azure: ~$3/month
- Snowflake: ~$60-90/month (can reduce with scheduled tasks vs. continuous)
- **Total: ~$65-95/month** ← **Aligned with free-tier budget**

---

## 7. Security & Compliance

### Constitution Principles Addressed

✅ **Cost Optimization**: X-Small warehouse, event-driven, incremental refresh, free-tier tools  
✅ **Data Quality**: 5 validation types, error quarantine, monitoring views, email alerts  
✅ **Scalability**: Dynamic tables (incremental), Snowpark (parallel), Iceberg (partition pruning)  
✅ **Compliance**: Data lineage documented, secure views, role-based access, audit logs  
✅ **Reproducibility**: Deterministic SQL, dbt versioning, seed data immutable in Bronze  
✅ **Observability**: Resource monitors, DQ dashboards, task execution logs, 8 monitoring views  
✅ **Documentation**: SQL comments, dbt YAML, README files, pipeline_documentation.md  
✅ **Security**: Secrets via Snowflake secrets (not hardcoded), role-based access, encryption at rest  
✅ **Portability**: Iceberg tables on Azure Blob Storage (open format), dbt models portable to other dialects  

### Credential Management

- ✅ NO credentials in code (repo contains placeholders for tenant, queue URI, and storage/container identifiers)
- ✅ Snowflake credentials stored in environment variables or `.dbt/profiles.yml` (gitignored)
- ✅ Azure credentials in Azure CLI / Service Principal (not in code)
- ✅ Secrets managed via Snowflake Secrets for any integrations

### Access Control

- User role: ACCOUNTADMIN (for deployment); post-deployment: ANALYST role for consumers
- Data access: Role-based via Secure Views
- External sharing: Via Snowflake Data Sharing (secure, governed, audit-logged)

---

## 8. Data Quality & Monitoring

### 5 Validation Types

1. **Row Count Validation**: Verify 100% of source rows loaded (Bronze → Silver)
2. **Schema Validation**: Verify all expected columns present + correct types
3. **Freshness Check**: Verify data ≤1 hour old (max latency)
4. **Uniqueness Validation**: No duplicate keys in fact tables
5. **Business Rule Validation**: Market share % sums to 100%, no negative counts

### Monitoring Views (8 Total)

1. VW_DQ_COMPLETENESS — % rows passing all checks
2. VW_DQ_FRESHNESS — Time since last successful load
3. VW_DQ_ACCURACY — Row count reconciliation
4. VW_ERROR_SUMMARY — Daily error rates
5. VW_LOAD_PERFORMANCE — Load times by stage
6. VW_COST_TRACKING — Daily spend by warehouse
7. VW_TASK_EXECUTION — Task run history + duration
8. VW_ALERT_HISTORY — DQ alerts triggered

### Alerting

- Email alerts on DQ failures (via EV_DQ_EMAIL_INT)
- Slack integration (optional, Stage 5 enhancement)
- Dashboard in Cortex Analyst for business users

---

## 9. Implementation Approach

### Prerequisites

**Software**:
- [ ] Azure CLI (for Azure setup)
- [ ] Snowflake SQL IDE or SnowSQL
- [ ] PostgreSQL client (psql) or Neon DB UI
- [ ] Python 3.11+ (for Streamlit)
- [ ] dbt Core (via `pip install dbt-snowflake`)
- [ ] Streamlit (via `pip install streamlit`)
- [ ] Git (to clone repo)

**Accounts**:
- [ ] Neon DB account + login (already have)
- [ ] Snowflake account + login credentials
- [ ] Azure subscription (free tier eligible, ~$200 free credits)
- [ ] Azure Blob container for Iceberg external volume (free tier available)

**Data**:
- [ ] EV Population JSON file (`ElectricVehiclePopulationData.json`) in repo
- [ ] Vehicle catalogue data (for Neon DB)
2. Create Azure Resource Group
3. Create Storage Account + Container
4. Create Event Grid Topic + Subscription
5. Configure authentication (service principal)
6. Upload EV data JSON to Blob Storage

**Day 1 (Snowflake Setup): ~2 hours**
1. Execute Stage 1 (Infrastructure): warehouse, integrations, schemas
2. Execute Stage 2 (Bronze): ingestion pipeline, stream, task DAG
3. Verify first data load succeeds

**Day 2 (Transformations): ~4 hours**
1. Execute Stage 3 (Silver): dynamic table, incremental refresh
2. Execute Stage 4 (Gold): aggregations, fact tables
3. **Execute Stage 4b** (PostgreSQL CDC): connector + dimension replication
4. Execute Stage 5 (Data Quality): validations, monitoring, alerts
5. Execute Stage 6 (Iceberg): open-format tables

**Day 2 (Analytics): ~2 hours**
1. Execute Stage 7 (Sharing): secure views
2. Execute Stage 8 (Cost Governance): resource monitors
3. Deploy Stage 9 (dbt + Streamlit): run tests, launch app

**Total Estimated Time**: 11-12eamlit): run tests, launch app

**Optional (Stage 4b): ~1 hour**
- PostgreSQL CDC setup (if source available)

**Total Estimated Time**: 10 hours (can be done in 1-2 days with parallel work)

---

## 10. Tes0 Validation: PostgreSQL
- [ ] Connect to Neon DB via psql: `psql [connection_string]`
- [ ] Verify schema exists: `\dt` (list tables)
- [ ] Verify CDC enabled: Check pg_logical_replication_slot status
- [ ] Sample data present: `SELECT COUNT(*) FROM vehicles`

### Stage ting & Validation Strategy

### Stage 1 Validation: Infrastructure
- [ ] Warehouse online (check status in Snowflake UI)
- [ ] All schemas created (`SHOW SCHEMAS`)
- [ ] Storage integration authenticated (test via `LS` command)

### Stage 2 Validation: Bronze
- [ ] Manually upload small JSON file to Azure Blob
- [ ] Verify Snowpipe detects + loads (check TASK_INGEST_EV_DATA in Task History)
- [ ] Query RAW_EV_DATA: `SELECT COUNT(*) FROM RAW_EV_DATA` (should match file)

### Stage 3 Validation: Silver
- [ ] Dynamic table refreshes automatically
- [ ] Query CLEAN_EV_DATA_DT: verify deduplicated, no nulls in key columns
- [ ] Check latency: timestamp difference between RAW and CLEAN

### Stage 4 Validation: Gold
- [ ] Fact tables populated
- [ ] Aggregations correct (verify count, market share %)
- [ ] Stream-triggered task fires automatically

### Stage 5 Validation: Data Quality
- [ ] DQ checks run (query ERROR_RECORDS)
- [ ] Email alert received when errors detected
- [ ] Monitoring views populate

### Stage 6-10: End-to-End Smoke Test
- [ ] Upload full EV data file to Azure
- [ ] Data flows through all layers (Bronze → Silver → Gold → Iceberg)
- [ ] dbt tests pass (100% pass rate)
- [ ] Streamlit app queries return results
- [ ] Cost tracking active (check resource monitors)

**Sign-Off**: All 10 acceptance criteria met + no errors in Task History

---

## 11. Dependencies & Risks

##Neon DB CDC configuration complex | Medium | Medium | Provide step-by-step SQL scripts + docs |
| Snowflake PostgreSQL connector authentication fails | Medium | Medium | Pre-validate Neon DB connection string |
| Azure setup learning curve | Medium | High | Provide step-by-step guided walkthrough |
| Snowflake free trial expires mid-deployment | High | Medium | Use trial wisely; cost monitoring active |
| Event Grid → Snowpipe latency > 30s | Low | Low | Fallback to scheduled task (5-min polling)

### Risks & Mitigation

| Risk | Severity | Probability | Mitigation |
|------|----------|-------------|-----------|
| Azure setup learning curve | Medium | High | Provide step-by-step guided walkthrough |
| Snowflake free trial expires mid-deployment | High | Medium | Use trial wisely; cost monitoring active |
| Event Grid → Snowpipe latency > 30s | Low | Low | Fallback to scheduled task (5-min polling) |
| PostgreSQL CDC unavailable | Low | Medium | Stage 4b optional; skip if no source |
| dbt test failures | Medium | Medium | Provide test coverage targets (80%+) |
| Streamlit deployment issues | Low | Low | Local dev option; Community Cloud backup |

### Rollback Strategy

Each stage is **atomic** and independent:
- Revert Stage N: DROP SCHEMA EV_PROJECT_DB.[STAGE_SCHEMA], re-execute Stage N SQL
- No upstream dependencies affected (schemas are isolated)

---

## 12. Success Metrics

- [ ] **AC1**: Data latency Bronze → Silver < 1 minute
- [ ] **AC2**: Data latency Silver → Gold < 1 minute
- [ ] **AC3**: DQ check completion rate ≥ 99%
- [ ] **AC4**: Monthly cost ≤ $20 (free tier goal) after trial
- [ ] **AC5**: dbt test pass rate = 100%
- [ ] **AC6**: Streamlit app response time < 5 seconds
- [ ] **AC7**: Zero unshipped credentials in code (security scan passes)
- [ ] **AC8**: 100% lineage traced from source to consumer
- [ ] **AC9**: All 9 constitution principles addressed in sign-off checklist
- [ ] **AC10**: Team trained + runbook documented
Neon DB account ready + connection string documented
- [ ] Azure account ready + subscription active
- [ ] Snowflake account ready + login credentials secured
- [ ] dbt/Python/Streamlit tools installable on your machine
- [ ] You can allocate 11-12 hours over next 2 days
- [ ] PostgreSQL CDC (Stage 4b) is now MANDATORY in deployment

Before proceeding to Implementation Plan phase, confirm:

- [ ] Azure account ready + subscription active
- [ ] Snowflake account ready + login credentials secured
- [ ] dbt/Python/Streamlit tools installable on your machine
- [ ] You can allocate 10-15 hours over next 2 days
- [ ] All 9 constitution principles understood + accepted
- [ ] Specification above is accurate + complete
- [ ] Ready to move to **Implementation Plan** phase

---

**Status**: ⏳ Awaiting specification approval  
**Next Phase**: Create Implementation Plan (break into 20-30 implementation tasks)  
**Timeline**: Approval → Plan (1 hour) → Implementation (10-15 hours) → Deployment (validation)

