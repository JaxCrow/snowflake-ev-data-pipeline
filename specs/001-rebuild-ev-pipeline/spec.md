# Feature Specification: Rebuild Snowflake EV Pipeline

**Feature Branch**: `001-rebuild-ev-pipeline`

**Created**: 2026-07-15

**Status**: Draft

**Input**: User description: "Create the official feature specification using docs/clarification-deployment.md and docs/deployment-specification.md as source of truth. Keep NeonDB CDC mandatory, Dev-only environment, manual setup, 12-hour CDC cadence, and completion gate requiring SQL stages + dbt + DQ + Streamlit metric validation."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Rebuild Full Dev Pipeline (Priority: P1)

As a data engineer, I need to rebuild the EV analytics pipeline end-to-end in a single Dev environment so that raw source data flows through ingestion, transformation, quality controls, and analytics without manual data fixes.

**Why this priority**: This delivers the core business value and validates the full pipeline lifecycle.

**Independent Test**: Can be fully tested by triggering a source data load and verifying records appear in downstream curated analytics outputs with expected metrics.

**Acceptance Scenarios**:

1. **Given** source EV records and catalogue records are available, **When** the full rebuild process runs in Dev, **Then** all required pipeline stages complete successfully in sequence.
2. **Given** the rebuild completes, **When** downstream curated outputs are queried, **Then** expected registration and market metrics are present and consistent.

---

### User Story 2 - Keep Catalogue Enrichment Current via CDC (Priority: P2)

As a data engineer, I need catalogue data changes from the external PostgreSQL catalogue to be synchronized on a fixed cadence so that curated analytics remain enriched with current make/model/category attributes.

**Why this priority**: Analytics quality depends on continuously enriched dimensions; stale catalogue data reduces trust.

**Independent Test**: Can be tested by changing a catalogue record and verifying synchronized updates appear in the enriched layer within the expected cadence window.

**Acceptance Scenarios**:

1. **Given** a catalogue record changes externally, **When** the next synchronization cycle executes, **Then** the updated value appears in the synchronized catalogue and enriched analytics tables.

---

### User Story 3 - Validate Operational Readiness in Dev (Priority: P3)

As an analyst stakeholder, I need quality checks and conversational analytics to be validated so that I can trust dashboard/chat answers from curated data.

**Why this priority**: A successful technical rebuild is incomplete without validated data quality and user-facing analytics behavior.

**Independent Test**: Can be tested by running quality checks and asking representative business questions in the analytics app, then confirming answers match expected curated metrics.

**Acceptance Scenarios**:

1. **Given** the rebuilt pipeline is operational, **When** data quality checks are executed, **Then** check outcomes and alerts are observable.
2. **Given** curated metrics are available, **When** an analyst asks expected business questions through the chat interface, **Then** responses match expected curated metrics.

---

### Edge Cases

- Source data arrives with malformed or missing fields.
- Catalogue synchronization window runs while no catalogue changes exist.
- Synchronization or enrichment is delayed and curated outputs risk staleness.
- Quality checks detect mismatches between transformed and curated counts.
- Analytics queries return no results due to filter combinations or missing dimensions.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support rebuilding the EV pipeline in a single Dev environment from source ingestion through analytics outputs.
- **FR-002**: The rebuild MUST execute through all defined stages in one end-to-end pass, including ingestion, transformation, enrichment, quality, sharing/open-format outputs, and analyst-facing analytics.
- **FR-003**: Catalogue enrichment via external PostgreSQL CDC MUST be included as a mandatory stage of the rebuild.
- **FR-004**: Catalogue synchronization MUST run on a 12-hour cadence in Dev.
- **FR-005**: The rebuilt pipeline MUST produce curated metrics for registrations and market indicators that are queryable by downstream consumers.
- **FR-006**: The system MUST run data quality validations and expose outcomes for operational verification.
- **FR-007**: The system MUST provide an analyst chat experience that answers business questions from curated metrics.
- **FR-008**: Rebuild completion MUST require successful stage execution plus successful validation of dbt checks, data quality behavior, and analyst chat metric correctness.
- **FR-009**: The rebuild process MUST remain manual-step executable for the first Dev deployment.
- **FR-010**: The rebuild MUST preserve traceability from source records to curated analytics outputs.

### Key Entities *(include if feature involves data)*

- **EV Registration Record**: Vehicle registration event data captured from source files and transformed through curated outputs.
- **Catalogue Vehicle Record**: External reference attributes (make, model, year, category) synchronized via CDC.
- **Curated Metric**: Business-facing aggregated measure derived from transformed and enriched records.
- **Data Quality Result**: Validation outcome and alertability state for each quality rule execution.
- **Analytics Query Session**: Analyst interaction and resulting answer mapped to curated metrics.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of required rebuild stages complete successfully in the Dev execution run.
- **SC-002**: Catalogue changes are reflected in enriched analytics within one 12-hour synchronization cycle.
- **SC-003**: 100% of required dbt checks pass for the rebuilt Dev pipeline.
- **SC-004**: Data quality checks execute successfully and produce observable pass/fail outcomes for each required rule.
- **SC-005**: For a predefined validation question set, analyst chat responses match expected curated metrics in at least 95% of cases.
- **SC-006**: End-to-end traceability is demonstrable from source ingestion to curated metric output for all validation samples.

## Assumptions

- Dev-only deployment is the target for this first rebuild.
- The first rebuild is executed manually step by step rather than via full infrastructure automation.
- External PostgreSQL catalogue access is available and permitted for synchronization.
- A representative validation question set for analyst chat is defined before final sign-off.
- Cost optimization remains a guiding constraint for cadence and resource usage decisions.

## Operating Security & Access Constraints

- Current-run Snowflake authentication method is interactive terminal password entry.
- Target steady-state authentication method is key pair auth.
- SSO externalbrowser remains deferred until IdP/SAML account-parameter issues are resolved.
- Secrets are prohibited in repository files (SQL, YAML, markdown, or committed config).
- Active scope for the current run is limited to readiness closure plus Stage 2 maximum unless explicitly re-approved.

## Decision Traceability

- Clarified authentication, role, secrets policy, and run scope are documented in `specs/001-rebuild-ev-pipeline/research.md`.
- Pre-execution readiness controls are documented in `specs/001-rebuild-ev-pipeline/quickstart.md`.
