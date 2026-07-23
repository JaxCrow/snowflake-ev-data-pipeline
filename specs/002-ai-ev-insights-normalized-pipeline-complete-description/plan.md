# Implementation Plan: AI EV Insights Normalized Pipeline Complete Description

**Branch**: `002-ai-ev-insights-normalized-pipeline-complete-description` | **Date**: 2026-07-21 | **Spec**: specs/002-ai-ev-insights-normalized-pipeline-complete-description/spec.md

**Input**: Feature specification from `/specs/002-ai-ev-insights-normalized-pipeline-complete-description/spec.md`

## Summary

Implement a strict `core`/`reference`/`consumption` architecture where:
- `core` is normalized, persistent, and historical,
- `reference` is external PostgreSQL CDC with historical SCD2,
- `consumption` is the only consumer surface via `mv_` materialized views,
- AI is read-only over `consumption` and always returns freshness/quality/exclusion context,
- demo and product flows are explicitly separated,
- dbt, Iceberg, sharing, and export remain mandatory capabilities.

## Technical Context

**Language/Version**: Snowflake SQL, Snowpark Python 3.11 (minimal/exception-only), dbt Core

**Primary Dependencies**: Snowflake (tasks/streams/materialized views), Azure Blob Storage + Event Grid path, NeonDB PostgreSQL CDC source, Airbyte OSS (Docker) for external CDC transport, dbt-snowflake, Cortex Analyst + Streamlit

**Storage**:
- Snowflake persistent layers: `core` (historical normalized business entities), `reference` (historical CDC catalog)
- Snowflake output layer: `consumption` (`mv_` materialized views)
- External source: PostgreSQL catalog in NeonDB
- Historical open format: Iceberg tables on external volume
- Raw landing source of truth: Blob Storage

**Testing**:
- dbt tests for consumption models
- SQL validation for core historical behavior and CDC effective-dated behavior
- data quality checks in core and consumption
- AI response validation set with explainability checks

**Target Platform**: Snowflake + Azure + NeonDB

**Project Type**: Data platform and analytics pipeline with AI consumption interface

**Performance Goals**:
- Event-driven ingestion on file landing
- Consumption answers served from precomputed `mv_` outputs
- Demo refresh cadence: automatic every 24 hours for consumption layer

**Constraints**:
- AI must be read-only
- AI can only query `consumption`
- `reference` must remain separate from `core`
- `core` historical preservation is mandatory
- Effective-date semantics are required for catalog-impact behavior
- CDC transport must run through an external engine in trial-constrained Snowflake environments (no dependency on External Access Integration)
- Mandatory capabilities cannot be removed from scope: dbt, Iceberg, sharing, export

**Scale/Scope**:
- Full demo capability surface with strict architecture rules
- Explicit dual-mode documentation (demo vs product)
- Single source of truth in SpecKit artifacts for this feature

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Applied project principles (from `.speckit/speckit.yml` and closed decisions baseline):

- Cost optimization: PASS
  - Precomputed `mv_` consumption and scheduled refresh avoid repeated expensive ad hoc query execution.
- Data quality first: PASS
  - Quality is mandatory in both `core` and `consumption`.
- Scalability by design: PASS
  - Event-driven ingestion and layered separation preserve scale boundaries.
- Compliance and auditability: PASS
  - Historical core, SCD2 historical reference, explainable AI responses, and explicit decision traceability.
- Reproducibility and versioning: PASS
  - Closed decisions documented; SpecKit feature is authoritative baseline.
- Observability and monitoring: PASS
  - Refresh cadence, CDC propagation, and quality/freshness signals are required output context.
- Documentation as code: PASS
  - All architecture decisions are captured in versioned markdown artifacts.

Pre-Design Gate Result: PASS

Post-Design Gate Result: PASS (no unresolved clarifications remain).

## Project Structure

### Documentation (this feature)

```text
specs/002-ai-ev-insights-normalized-pipeline-complete-description/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── data-interfaces.md
└── tasks.md                # Created by /speckit.tasks
```

### Source Code (repository root)

```text
00_documentation/
01_infrastructure/
02_bronze/
03_silver/
04_gold/
04b_external_data_integration/
05_data_quality/
06_iceberg/
07_sharing/
08_cost_governance/
09_analyst_streamlit/
10_dbt_project/
```

**Structure Decision**:
- Existing physical folders are retained for implementation continuity.
- Architectural documentation model is replaced by logical layers:
  - `core`: normalized persistent business entities with historical preservation and selected derived dimensions
  - `reference`: external CDC historical catalog (SCD2)
  - `consumption`: `mv_` materialized output surface for AI/consumers

## Phase Plan

### Phase 0: Research & Decision Lock

Outputs: `research.md`

1. Resolve implementation choices needed to realize closed architecture decisions without reopening scope.
2. Confirm external CDC execution model (Airbyte OSS in Docker baseline) and ownership boundaries.
3. Confirm effective-dated join pattern from `reference` to `consumption`.
4. Confirm historical persistence strategy for `core` entities.
5. Confirm cadence and operational behavior split between demo and product.
6. Confirm governance contract for read-only AI over consumption-only surface.

### Phase 1: Design & Contracts

Outputs: `data-model.md`, `contracts/data-interfaces.md`, `quickstart.md`

1. Define entities, historical behavior, and relationships for `core`, `reference`, and `consumption`.
2. Define interface contracts for:
   - event-driven ingestion,
   - CDC synchronization and SCD2 history,
   - consumption materialized outputs,
   - AI explainability output envelope.
3. Define runnable validation scenarios for demo and product-mode behavior.

### Phase 2: Build Preparation (for /speckit.tasks)

1. Decompose work into implementation tasks aligned to priorities:
   - P1 AI consumption behavior,
   - P2 CDC historical catalog impact,
   - P3 platform capability completeness.
2. Include dependencies, quality gates, and acceptance checks.
3. Include migration tasks to align existing docs/artifacts to new architecture naming.

## Complexity Tracking

No constitution violations require exception approval at planning time.

## Execution Guardrails

- No destructive cleanup outside approved scope without explicit user approval.
- No documentation references may contradict closed decisions in continuity baseline.
- `consumption` remains the only AI query surface.
- `core` historical behavior must remain consistent with the closed decisions baseline.
- Any proposed change that reopens closed architecture decisions must be explicitly rejected unless approved by user.

## Decision Traceability

- Closed decision baseline: `00_documentation/speckit-continuity-context.md`
- Feature specification baseline: `specs/002-ai-ev-insights-normalized-pipeline-complete-description/spec.md`
- This plan is authoritative for subsequent `/speckit.tasks` generation for feature `002`.
