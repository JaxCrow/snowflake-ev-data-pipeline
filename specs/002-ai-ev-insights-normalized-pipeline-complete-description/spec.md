# Feature Specification: AI EV Insights Normalized Pipeline Complete Description

**Feature Branch**: `002-ai-ev-insights-normalized-pipeline-complete-description`

**Created**: 2026-07-21

**Status**: Draft

**Input**: User description: "Create the official feature specification from 00_documentation/speckit-continuity-context.md as the only source of truth. Preserve all closed decisions: architecture core/reference/consumption, reference with CDC + historical SCD2, consumption as materialized views with mv_ prefix, AI agent read-only over consumption, strict demo vs product separation, and mandatory dbt/Iceberg/sharing/export capabilities."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - AI Insights from Governed Consumption Layer (Priority: P1)

As an analyst, I need an AI agent that answers EV business questions using only precomputed consumption outputs so that responses are fast, consistent, and auditable.

**Why this priority**: This is the primary business objective and top priority of the redesign.

**Independent Test**: Can be tested by querying the AI agent for predefined questions and verifying results come only from materialized consumption outputs with quality/freshness context.

**Acceptance Scenarios**:

1. **Given** refreshed consumption materialized views are available, **When** the AI agent receives business questions, **Then** it returns answers based only on `mv_` consumption outputs.
2. **Given** an AI response is generated, **When** explanation metadata is requested, **Then** the response includes assumptions, freshness status, quality status, and any applied exclusions/filters.
3. **Given** AI access rules are enforced, **When** an attempt is made to query persistent implementation layers, **Then** access is denied and only consumption-layer access is allowed.

---

### User Story 2 - Historical External Catalog Impact via CDC (Priority: P2)

As a data engineer, I need PostgreSQL catalog changes to flow into Snowflake historical reference data so that consumption reflects effective-dated catalog values after changes occur.

**Why this priority**: Demonstrating external catalog control and CDC is a core objective of the demo.

**Independent Test**: Can be tested by changing a catalog value in PostgreSQL and verifying post-change consumption results differ according to effective dates while pre-change history remains intact.

**Acceptance Scenarios**:

1. **Given** a catalog attribute changes in PostgreSQL, **When** the external CDC engine synchronization runs, **Then** Snowflake reference history captures a new SCD2 version while preserving prior versions.
2. **Given** consumption is rebuilt, **When** metrics are resolved by event-effective date, **Then** values before the change use prior catalog version and values after the change use the updated version.
3. **Given** catalog history is queried, **When** point-in-time checks are performed, **Then** complete historical versions are available.

---

### User Story 3 - End-to-End Platform Capability Demo (Priority: P3)

As a platform stakeholder, I need the demo to preserve ingestion, transformation, quality, open format, sharing, and export capabilities so that architecture breadth is demonstrated, not only AI chat.

**Why this priority**: The demo must prove full platform capability while keeping a strict architecture.

**Independent Test**: Can be tested by executing the full demo flow and validating event-driven ingestion, dbt outputs/tests, Iceberg availability, sharing/export outputs, and AI consumption behavior.

**Acceptance Scenarios**:

1. **Given** a file lands in Blob Storage, **When** event-driven ingestion runs, **Then** operational landing and downstream processing are triggered per architecture.
2. **Given** core/reference updates are complete, **When** consumption refresh executes, **Then** materialized outputs are refreshed on fixed cadence.
3. **Given** sharing and export artifacts are configured, **When** consumers access published outputs, **Then** governed access works against approved surfaces.

---

### Demo Mode vs Product Mode *(explicit separation required)*

#### Demo Mode

- Event-driven ingestion pattern is demonstrated with representative file arrivals.
- Consumption materialized views refresh automatically every 24 hours.
- AI agent is read-only and restricted to consumption outputs.
- dbt, Iceberg, sharing, and export are mandatory scope.

#### Product Mode

- Ingestion remains event-driven per file landing in Blob Storage.
- Cadence and operational controls may be tuned for SLA/cost.
- Same governance model applies: AI consumption surface remains controlled.
- Architecture decisions are preserved unless formally changed by decision log.

---

### Edge Cases

- File arrives but required catalog keys are missing in reference history.
- CDC run captures updates out of expected temporal order.
- Consumption refresh runs while reference sync is delayed.
- AI query asks for unsupported metrics outside consumption models.
- Quality checks pass in core but fail at consumption derivation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST implement architecture layers named `core`, `reference`, and `consumption` in documentation and design.
- **FR-002**: The `consumption` layer MUST be the only output surface for the AI agent and downstream consumers.
- **FR-003**: The `consumption` layer MUST use materialized views with `mv_` naming prefix.
- **FR-004**: The AI agent MUST be read-only and MUST NOT write or execute direct reprocessing actions.
- **FR-005**: AI responses MUST include assumptions, freshness status, quality status, and applied exclusions/filters.
- **FR-006**: The `reference` layer MUST synchronize external PostgreSQL catalog data through CDC.
- **FR-007**: The `reference` layer MUST store historical SCD Type 2 versions.
- **FR-008**: Catalog changes MUST affect consumption results by effective event date.
- **FR-008a**: CDC transport from PostgreSQL to Snowflake MUST be executed by an external CDC engine (Airbyte OSS baseline), not by direct Snowflake runtime external access in trial-constrained environments.
- **FR-009**: The `core` layer MUST be normalized, persistent, and retain historical changes for core business entities.
- **FR-010**: The `core` layer MUST support historical versions for core entities and MAY include selected derived business dimensions.
- **FR-011**: Demo and product behaviors MUST be documented as explicit, separate flows.
- **FR-012**: Blob ingestion MUST be event-driven on file landing.
- **FR-013**: Consumption materialized views MUST refresh automatically every 24 hours in demo mode.
- **FR-014**: dbt capability MUST remain in scope for consumption modeling, testing, and lineage documentation.
- **FR-015**: Iceberg capability MUST remain in mandatory scope.
- **FR-016**: Sharing and export capabilities MUST remain in mandatory scope.
- **FR-017**: Bronze operational landing MAY remain as a minimal operational layer, but the documented architecture model MUST remain core/reference/consumption.
- **FR-018**: Historical raw data MAY be represented in Iceberg for open-format/historical analysis.
- **FR-019**: Decision rationale MUST be captured in a closed, explicit decision log.
- **FR-020**: All project documentation aligned to this feature MUST treat this specification as the authoritative baseline.

### Key Entities *(include if feature involves data)*

- **Core Entity**: Normalized persistent business entity representing EV domain records over time.
- **Core Entity History Version**: Historical version state of a normalized core business entity retained for traceability.
- **Reference Catalog Entity**: External PostgreSQL-derived historical catalog entity tracked with SCD2.
- **Consumption Model**: Materialized denormalized output (`mv_*`) built from core + reference for AI and consumers.
- **CDC Change Version**: Effective-dated catalog version created by CDC synchronization.
- **AI Insight Response**: Governed read-only response including metric result plus freshness/quality/exclusion context.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of AI responses for the validation set are served from `mv_` consumption outputs only.
- **SC-002**: 100% of validated AI responses include freshness/quality/exclusion context and assumptions.
- **SC-003**: PostgreSQL catalog updates are reflected in reference SCD2 history and propagate to consumption by effective date in the next scheduled processing window.
- **SC-003a**: Historical changes in core entities remain queryable and attributable over time for validation samples.
- **SC-004**: Demo consumption materialized views refresh automatically at 24-hour cadence with successful run evidence.
- **SC-005**: dbt models/tests/lineage for consumption scope execute successfully for required demo artifacts.
- **SC-006**: Iceberg, sharing, and export demo capabilities execute successfully against governed outputs.
- **SC-007**: Demo and product flows are clearly separated in documentation with no ambiguity in behavior.

## Assumptions

- External PostgreSQL (NeonDB) remains available as the catalog reference source for demo.
- External CDC runtime (Airbyte OSS in Docker baseline) is available to deliver NeonDB changes into Snowflake reference landing.
- Blob Storage event-driven ingestion remains available for demo and product flows.
- Consumption refresh cadence in demo remains fixed at 24 hours unless formally revised.
- Governance requirements require read-only AI behavior in initial release.

## Non-Goals

- Enabling direct AI access to persistent implementation layers.
- Depending on direct Snowflake runtime external access to NeonDB in trial-constrained environments.
- Replacing external PostgreSQL catalog source with internal-only catalog.
- Removing mandatory platform capabilities (dbt, Iceberg, sharing, export) from demo scope.

## Closed Decisions *(do not reopen without explicit exception)*

- Architecture naming is `core`/`reference`/`consumption`.
- `core` preserves history for core business entities.
- `consumption` is the only query surface for AI and consumers.
- `consumption` uses materialized views with `mv_` prefix.
- AI is read-only and responses include explainability context.
- `reference` is external CDC + SCD2 historical catalog.
- External CDC transport is executed by Airbyte OSS (Docker baseline).
- Catalog change impact is effective-date based.
- Demo vs product is explicitly separated in documentation.
- dbt, Iceberg, sharing, and export remain mandatory demo capabilities.

## Decision Traceability

- Source of truth for closed decisions: `00_documentation/speckit-continuity-context.md`.
- This specification supersedes prior architecture framing for the redesign track.
