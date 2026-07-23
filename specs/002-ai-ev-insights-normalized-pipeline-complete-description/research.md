# Research Decisions: AI EV Insights Normalized Pipeline Complete Description

Date: 2026-07-21
Spec: specs/002-ai-ev-insights-normalized-pipeline-complete-description/spec.md

## Decision 1: Architecture Naming Model

- Decision: Use logical architecture layers named `core`, `reference`, and `consumption` in all redesign documentation.
- Rationale: Replaces ambiguous legacy medallion naming with purpose-driven architecture boundaries.
- Alternatives considered:
  - Keep Bronze/Silver/Gold naming: rejected due to mismatch with closed architecture intent.
  - Hybrid naming: rejected due to confusion risk.

## Decision 2: AI Query Surface Restriction

- Decision: AI agent can read only from `consumption` (`mv_` materialized views).
- Rationale: Enforces governance, performance predictability, and simple trust model.
- Alternatives considered:
  - AI can query core/reference directly: rejected due to governance and complexity concerns.
  - AI with write triggers: rejected for safety and scope control.

## Decision 3: Reference Layer CDC + SCD2

- Decision: Build `reference` from external PostgreSQL CDC with historical SCD Type 2.
- Rationale: Demonstrates external catalog control and effective-dated business impact over time.
- Alternatives considered:
  - Latest-value overwrite only: rejected; cannot support effective-date semantics.
  - Internal-only reference table: rejected; does not demonstrate external CDC capability.

## Decision 4: Effective-Date Impact Rule

- Decision: Consumption results must apply catalog values by effective event date.
- Rationale: Ensures historically correct answers before/after reference changes.
- Alternatives considered:
  - Apply by query-time latest value: rejected; breaks temporal correctness.

## Decision 5: Consumption Materialization Strategy

- Decision: Use materialized views in `consumption` with `mv_` prefix and automatic 24-hour refresh in demo mode.
- Rationale: Minimizes repeated computation cost and keeps response behavior deterministic.
- Alternatives considered:
  - Standard views only: rejected due to re-execution cost on frequent AI queries.
  - Manual-only refresh: rejected for demo objective of automatic capability.

## Decision 6: Demo vs Product Separation

- Decision: Document demo and product as distinct flows.
- Rationale: Avoids ambiguity and preserves strict communication of operating mode differences.
- Alternatives considered:
  - Single merged flow with notes: rejected due to clarity risk.

## Decision 7: Platform Capability Scope

- Decision: Keep dbt, Iceberg, sharing, and export as mandatory in scope.
- Rationale: Demo objective explicitly requires broad platform capability demonstration.
- Alternatives considered:
  - Focus only on AI: rejected as incomplete for stakeholder goals.

## Decision 8: Bronze Role in Redesign

- Decision: Maintain Bronze as minimal operational landing, while allowing historical raw representation in Iceberg.
- Rationale: Preserves operational control and replay paths while avoiding uncontrolled raw growth in operational layer.
- Alternatives considered:
  - Remove Bronze entirely: rejected; weakens operational ingestion boundary.
  - Keep Bronze as full historical archive: rejected due to cost growth.

## Decision 9: Core Layer Persistence Model

- Decision: `core` remains normalized, persistent, and historical for business entities; includes selected derived business dimensions when needed.
- Rationale: Balances normalized design purity with practical modeling usability while preserving business-entity traceability over time.
- Alternatives considered:
  - Base entities only: rejected as too raw for reusable modeling.
  - Current-state-only core: rejected because it would lose historical context that the redesign explicitly keeps in the main business domain.
  - Fully denormalized core: rejected; violates architecture principles.

## Decision 10: Clarification Closure

- Decision: No remaining NEEDS CLARIFICATION items for plan phase.
- Rationale: Continuity baseline plus closed Q&A decisions fully define architecture and scope constraints.
- Alternatives considered:
  - Defer unresolved questions to implementation: rejected; would violate strict planning discipline.

## Decision 11: CDC Execution Model

- Decision: Use an external CDC engine (Airbyte OSS in Docker baseline) to transport NeonDB changes into Snowflake landing/reference.
- Rationale: Snowflake trial accounts do not support External Access Integration; external CDC transport preserves architecture goals without violating constraints.
- Alternatives considered:
  - Direct Snowflake runtime external access to NeonDB: rejected for trial incompatibility.
  - Paid managed replication as default: rejected due to Free-First cost principle for baseline.
