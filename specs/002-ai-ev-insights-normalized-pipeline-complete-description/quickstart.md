# Quickstart Validation Guide

Date: 2026-07-21
Feature: specs/002-ai-ev-insights-normalized-pipeline-complete-description/spec.md

## Purpose

Validate the redesigned architecture end-to-end with strict `core` / `reference` / `consumption` behavior and AI read-only consumption access.

## Modes

## Demo Mode

- Event-driven ingestion behavior demonstrated through Blob landing workflow.
- `consumption` materialized outputs refresh automatically every 24 hours.
- AI reads only from `mv_` consumption models.
- dbt, Iceberg, sharing, and export capabilities are mandatory in validation scope.

## Product Mode

- Event-driven ingestion remains the operating model.
- Operational cadence and scaling can be tuned, while architecture and governance constraints remain consistent.

## Prerequisites

- Snowflake environment with required privileges for pipeline objects
- Blob source and event path configured
- PostgreSQL (NeonDB) catalog source accessible for CDC
- External CDC runtime available (Airbyte OSS Docker baseline)
- dbt project runnable for required models/tests
- Required Iceberg, sharing, and export configuration available

## Validation Flow

### 1) Validate layer boundaries and naming

- Confirm architecture references and object mappings are aligned to `core`, `reference`, `consumption`.
- Confirm consumption outputs follow `mv_` prefix convention.

Expected outcome:
- No ambiguous layer references.
- Consumption surface clearly separated from persistent implementation layers.

### 2) Validate event-driven ingestion behavior

- Land a representative source file in Blob storage.
- Verify ingestion trigger occurs without manual query-driven ingestion.

Expected outcome:
- Ingestion run executes from event trigger.
- Core ingestion lineage fields are populated.

### 3) Validate reference CDC and SCD2 history

- Apply a controlled catalog change in PostgreSQL (e.g., vehicle price/category update).
- Run external CDC sync and confirm successful transport into Snowflake landing/reference staging.
- Verify CDC synchronization creates a new SCD2 version in `reference`.
- Verify prior version remains historically queryable.

Expected outcome:
- Historical versions are preserved.
- New version includes updated effective window.
- CDC transport run logs show successful extraction/load for the validation cycle.

### 4) Validate effective-date propagation to consumption

- Rebuild/refresh consumption according to demo cadence mechanism.
- Compare pre-change vs post-change event slices.

Expected outcome:
- Events before effective change date resolve previous catalog version.
- Events after effective change date resolve updated catalog version.

### 5) Validate core historical persistence

- Validate that historical versions of core entities remain queryable over time.
- Verify that changes in core business records preserve prior historical states.

Expected outcome:
- Core entity history is queryable for validation samples.
- Historical versions do not overwrite prior business-state records.

### 6) Validate consumption refresh policy (demo)

- Verify automatic 24-hour refresh scheduling and latest successful execution evidence.

Expected outcome:
- Consumption refresh runs on expected cadence.
- Freshness markers are updated.

### 7) Validate AI consumption constraints

- Submit validation question set through AI interface.
- Confirm responses come from `consumption` only.
- Confirm responses include assumptions, freshness, quality, and exclusions/filters.
- Verify read-only behavior (no write/reprocess operations).

Expected outcome:
- 100% of validated responses conform to response contract.
- AI cannot access persistent implementation layers.

### 8) Validate mandatory capability surfaces

- Execute dbt models/tests/lineage checks for required scope.
- Validate Iceberg outputs are available.
- Validate sharing/export outputs are accessible through governed surfaces.

Expected outcome:
- Mandatory capability set passes acceptance checks.

## Completion Criteria

Validation is complete when all are true:

- Layer model and naming are consistent with `core`/`reference`/`consumption`.
- Event-driven ingestion executes successfully.
- Core historical behavior is verified.
- Reference SCD2 history and effective-date behavior are verified.
- Consumption refresh cadence is validated for demo mode.
- AI response contract and read-only constraints are fully validated.
- dbt, Iceberg, sharing, and export capability checks pass.

## Evidence to Capture

- Ingestion trigger run evidence
- Core history validation evidence
- CDC run evidence with before/after SCD2 versions
- External CDC runtime evidence (sync log/run id, source row count, loaded row count)
- Effective-date comparison query evidence
- Consumption refresh schedule/run evidence
- AI validation transcript with response context fields
- dbt/Iceberg/sharing/export validation evidence
