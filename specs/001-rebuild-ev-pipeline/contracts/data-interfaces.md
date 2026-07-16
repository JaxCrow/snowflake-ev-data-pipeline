# Data Interfaces and Contracts

Date: 2026-07-15
Spec: specs/001-rebuild-ev-pipeline/spec.md

## Contract 1: Source Ingestion Interface

- Producer: EV source file landing process
- Consumer: Bronze ingestion stage
- Contract:
  - Source records must be available in landing storage path expected by the ingestion stage.
  - Records must include fields needed to derive registration identity and analysis dimensions.
  - Ingestion must preserve source lineage metadata for traceability.
- Verification:
  - Bronze load count is non-zero for test input.
  - Source metadata fields are persisted.

## Contract 2: CDC Catalogue Interface

- Producer: NeonDB PostgreSQL catalogue
- Consumer: Snowflake CDC synchronization stage
- Contract:
  - Catalogue source exposes identity and reference attributes for join enrichment.
  - Synchronization cadence is 12 hours.
  - CDC changes are propagated without losing record identity.
- Verification:
  - Change in source appears in synchronized target within one cadence window.
  - Joined enrichment fields are populated in downstream layers.

## Contract 3: Silver-to-Gold Transformation Interface

- Producer: Silver standardized data
- Consumer: Gold and dbt models
- Contract:
  - Silver outputs include normalized business fields required for aggregation.
  - Gold transformations generate curated metrics with deterministic logic.
  - Curated outputs remain compatible with dbt validations.
- Verification:
  - Gold metrics produced for required grains.
  - dbt validations pass for required models.

## Contract 4: Data Quality and Alerting Interface

- Producer: DQ checks
- Consumer: Operators and completion gate
- Contract:
  - Required DQ checks execute and produce observable status.
  - Failures are queryable and trigger expected alert behavior.
- Verification:
  - DQ result records exist for each required check type.
  - Alert path is validated for a representative failure case.

## Contract 5: Analyst Metrics Interface

- Producer: Curated analytics outputs
- Consumer: Streamlit analyst chat
- Contract:
  - Analyst queries resolve to curated metrics from validated outputs.
  - Response values match expected metrics for the validation question set.
- Verification:
  - Validation question set returns expected values with at least 95% match.
