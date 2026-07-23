# Data Interfaces and Contracts

Date: 2026-07-21
Spec: specs/002-ai-ev-insights-normalized-pipeline-complete-description/spec.md

## Contract 1: Event-Driven Ingestion Interface

- Producer: Blob Storage file landing events
- Consumer: Snowflake ingestion workflow
- Contract:
  - File landing event triggers ingestion workflow automatically.
  - Ingestion preserves source lineage fields required for downstream traceability.
  - Operational landing behavior remains deterministic and auditable.
- Verification:
  - New file arrival produces a corresponding ingestion run.
  - Lineage metadata exists for ingested records.

## Contract 2: External Catalog CDC Interface

- Producer: PostgreSQL (NeonDB) external catalog
- Transport: External CDC engine (Airbyte OSS baseline running in Docker)
- Consumer: Snowflake `reference` landing and SCD2 merge pipeline
- Contract:
  - External changes are synchronized via CDC through the external transport engine.
  - Reference layer stores SCD2 versions with validity windows.
  - No historical versions are lost during updates.
- Verification:
  - Transport run logs show successful extraction and load into Snowflake landing tables.
  - Catalog update creates a new SCD2 version row.
  - Prior version remains queryable with closed validity window.

## Contract 3: Core and Reference Integration Interface

- Producer: `core` entities and `reference` SCD2 entities
- Consumer: `consumption` materialized models
- Contract:
  - Consumption derivation uses effective-date semantics for reference attributes.
  - Denormalized outputs are materialized with `mv_` prefix.
  - Consumption includes freshness and quality context fields required by AI.
- Verification:
  - Pre-change and post-change events resolve distinct reference versions correctly.
  - Output objects follow naming and source-surface constraints.

## Contract 4: AI Consumption Interface

- Producer: `consumption` materialized outputs
- Consumer: AI agent (read-only)
- Contract:
  - Agent can read only approved consumption outputs.
  - Responses include assumptions, freshness status, quality status, and exclusions/filters.
  - Agent cannot trigger write operations.
- Verification:
  - Access control blocks non-consumption sources.
  - Response envelope fields are always present in validation set.

## Contract 5: Demo and Product Behavioral Split

- Producer: Architecture runtime configuration
- Consumer: Operators and stakeholders
- Contract:
  - Demo and product flows are documented as separate behavior profiles.
  - Demo enforces 24-hour automatic refresh cadence for consumption.
  - Product retains event-driven ingestion and equivalent governance constraints.
- Verification:
  - Separate runbook sections exist and are executable.
  - Demo cadence evidence is observable.

## Contract 6: Capability Preservation Interface

- Producer: Platform build outputs
- Consumer: Demo evaluators
- Contract:
  - dbt remains active for modeling/tests/lineage.
  - Iceberg remains active for open-format capability.
  - Sharing and export remain active as governed outputs.
- Verification:
  - Required capability artifacts exist and pass acceptance checks.
