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
