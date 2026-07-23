# Tasks: AI EV Insights Normalized Pipeline Complete Description

**Input**: Design documents from `/specs/002-ai-ev-insights-normalized-pipeline-complete-description/`

**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Validation tasks are included because this feature defines measurable acceptance criteria and mandatory capability checks.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare architecture mapping, standards, and baseline objects used by all stories.

- [ ] T001 Create architecture mapping notes from physical folders to logical layers in `00_documentation/pipeline_documentation.md`
- [ ] T002 Update stage mapping guidance for `core`/`reference`/`consumption` in `FILE_MAPPING.md`
- [ ] T003 [P] Define/verify shared naming conventions for `mv_` outputs in `04_gold/01_gold.sql`
- [ ] T004 [P] Define/verify shared freshness and quality marker conventions in `05_data_quality/01_data_quality.sql`
- [ ] T005 [P] Align dbt source references with logical-layer naming in `10_dbt_project/models/staging/sources.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core and reference foundations that must exist before user stories execute.

**CRITICAL**: No user story work should begin until this phase is complete.

- [ ] T006 Create or align normalized historical core entity structures in `03_silver/01_silver.sql`
- [ ] T007 Create or align core entity history version logic and effective windows in `03_silver/01_silver.sql`
- [ ] T008 [P] Enforce no-overlap validation rules for core history windows in `05_data_quality/01_data_quality.sql`
- [ ] T009 Create or align reference SCD2 structures from external CDC in `04b_external_data_integration/01_postgresql_cdc.sql`
- [ ] T010 [P] Enforce no-overlap validation rules for reference SCD2 windows in `05_data_quality/01_data_quality.sql`
- [ ] T011 Implement or align effective-date join logic foundation used by consumption models in `04_gold/01_gold.sql`
- [ ] T012 Define access boundary controls so AI/consumers read only approved consumption objects in `07_sharing/01_sharing.sql`

**Checkpoint**: Historical `core`, historical `reference`, and effective-date foundations are ready.

---

## Phase 3: User Story 1 - AI Insights from Governed Consumption Layer (Priority: P1) MVP

**Goal**: AI answers must come only from governed `consumption` materialized outputs and include required explainability context.

**Independent Test**: Run AI validation set and confirm responses are sourced only from `mv_` models with assumptions/freshness/quality/exclusions fields.

### Validation for User Story 1

- [ ] T013 [P] [US1] Build or align primary consumption materialized model with `mv_` prefix in `04_gold/01_gold.sql`
- [ ] T014 [P] [US1] Build or align secondary consumption materialized model with `mv_` prefix in `04_gold/01_gold.sql`
- [ ] T015 [US1] Add freshness marker derivation to consumption outputs in `04_gold/01_gold.sql`
- [ ] T016 [US1] Add quality marker derivation to consumption outputs in `04_gold/01_gold.sql`
- [ ] T017 [US1] Expose assumptions and exclusions/filter metadata fields for AI response contract in `09_analyst_streamlit/01_analyst_streamlit.sql`
- [ ] T018 [US1] Enforce read-only consumption-only query surface for AI role in `09_analyst_streamlit/01_analyst_streamlit.sql`
- [ ] T019 [US1] Add AI contract validation queries for response envelope completeness in `09_analyst_streamlit/01_analyst_streamlit.sql`
- [ ] T020 [US1] Record US1 acceptance evidence for source-surface and explainability compliance in `specs/002-ai-ev-insights-normalized-pipeline-complete-description/quickstart.md`

**Checkpoint**: AI behavior is governed, read-only, and explainable from `consumption` only.

---

## Phase 4: User Story 2 - Historical External Catalog Impact via CDC (Priority: P2)

**Goal**: External PostgreSQL catalog changes must propagate through reference SCD2 and affect consumption by effective date.

**Independent Test**: Apply controlled catalog change and verify pre-change vs post-change outputs differ correctly while history remains queryable.

### Validation for User Story 2

- [ ] T021 [US2] Define Airbyte OSS Docker deployment contract and operator run steps in `00_documentation/pipeline_documentation.md`
- [ ] T022 [US2] Implement or align CDC landing structures consumed by external transport in `04b_external_data_integration/01_postgresql_cdc.sql`
- [ ] T023 [US2] Implement or align SCD2 versioning logic with `effective_start_at`, `effective_end_at`, and `is_current` in `04b_external_data_integration/01_postgresql_cdc.sql`
- [ ] T024 [US2] Implement deterministic handling for out-of-order CDC events in `04b_external_data_integration/01_postgresql_cdc.sql`
- [ ] T025 [US2] Wire consumption effective-date joins to reference SCD2 windows in `04_gold/01_gold.sql`
- [ ] T026 [P] [US2] Add CDC/SCD2 validation checks for version continuity and historical queryability in `05_data_quality/01_data_quality.sql`
- [ ] T027 [US2] Add pre-change/post-change comparison validation queries in `04_gold/01_gold.sql`
- [ ] T028 [US2] Record US2 acceptance evidence for external CDC transport, propagation, and effective-date behavior in `specs/002-ai-ev-insights-normalized-pipeline-complete-description/quickstart.md`

**Checkpoint**: CDC-driven reference history and effective-date consumption behavior are verified.

---

## Phase 5: User Story 3 - End-to-End Platform Capability Demo (Priority: P3)

**Goal**: Preserve full mandatory platform capabilities (dbt, Iceberg, sharing, export) with strict demo/product separation.

**Independent Test**: Execute demo validation flow and verify all mandatory surfaces pass with evidence.

### Validation for User Story 3

- [ ] T029 [US3] Validate and align event-driven Blob ingestion path behavior in `02_bronze/01_bronze.sql`
- [ ] T030 [US3] Configure and verify demo-mode 24-hour refresh cadence for consumption outputs in `08_cost_governance/01_cost_governance.sql`
- [ ] T031 [US3] Add/align dbt consumption model for EV registrations in `10_dbt_project/models/gold/fact_ev_registrations.sql`
- [ ] T032 [US3] Add/align dbt consumption model for market metrics in `10_dbt_project/models/gold/fact_ev_market_metrics.sql`
- [ ] T033 [P] [US3] Add/align dbt schema tests and lineage metadata in `10_dbt_project/models/schema.yml`
- [ ] T034 [US3] Validate and align Iceberg capability outputs and queryability in `06_iceberg/01_iceberg.sql`
- [ ] T035 [P] [US3] Validate and align governed sharing outputs in `07_sharing/01_sharing.sql`
- [ ] T036 [P] [US3] Validate and align governed export outputs in `07_sharing/01_sharing.sql`
- [ ] T037 [US3] Separate demo-mode and product-mode operational instructions explicitly in `00_documentation/pipeline_documentation.md`
- [ ] T038 [US3] Record US3 acceptance evidence for dbt, Iceberg, sharing, export, and cadence in `specs/002-ai-ev-insights-normalized-pipeline-complete-description/quickstart.md`

**Checkpoint**: Mandatory platform capability surface is complete and validated.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, governance, and evidence hardening across all stories.

- [ ] T039 [P] Run cross-layer terminology consistency cleanup (`core`/`reference`/`consumption`) in `README.md`
- [ ] T040 [P] Update continuity traceability and closed decision references in `00_documentation/speckit-continuity-context.md`
- [ ] T041 Reconcile contract examples with final SQL object names in `specs/002-ai-ev-insights-normalized-pipeline-complete-description/contracts/data-interfaces.md`
- [ ] T042 Run end-to-end quickstart validation and capture final signoff evidence in `specs/002-ai-ev-insights-normalized-pipeline-complete-description/quickstart.md`
- [ ] T043 Produce final implementation readiness summary for feature 002 in `specs/002-ai-ev-insights-normalized-pipeline-complete-description/plan.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 (Setup): starts immediately.
- Phase 2 (Foundational): depends on Phase 1 and blocks all user stories.
- Phase 3 (US1): depends on Phase 2 completion.
- Phase 4 (US2): depends on Phase 2 and integration outputs created in US1 consumption modeling.
- Phase 5 (US3): depends on Phase 2 and can progress with US1/US2 outputs as they stabilize.
- Phase 6 (Polish): depends on selected story completions and final validation readiness.

### User Story Dependencies

- US1 (P1): first delivery target (MVP).
- US2 (P2): depends on foundational CDC/SCD2 and effective-date wiring.
- US3 (P3): depends on foundational readiness plus stabilized outputs from earlier stories.

### Task-Level Critical Dependencies

- T007 depends on T006
- T011 depends on T009 and T010
- T015, T016 depend on T013/T014
- T018 depends on T012, T013, T014
- T020 depends on T019
- T024 depends on T022 and T011
- T026 depends on T024
- T027 depends on T025 and T026
- T030 depends on T013/T014 availability
- T038 depends on T031 through T037
- T042 depends on T020, T028, and T038
- T043 depends on T042

---

## Parallel Opportunities

- Phase 1: T003, T004, and T005 can run in parallel.
- Phase 2: T008 and T010 can run in parallel with CDC/core structure tasks after base objects exist.
- US1: T013 and T014 can run in parallel.
- US2: T025 can run in parallel after SCD2 structure is established.
- US3: T033, T035, and T036 can run in parallel.
- Polish: T039 and T040 can run in parallel.

---

## Parallel Example: User Story 1

- Task: T013 Build or align primary consumption materialized model in `04_gold/01_gold.sql`
- Task: T014 Build or align secondary consumption materialized model in `04_gold/01_gold.sql`

Then continue with:

- Task: T015 Add freshness marker derivation in `04_gold/01_gold.sql`
- Task: T016 Add quality marker derivation in `04_gold/01_gold.sql`

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational).
3. Complete Phase 3 (US1).
4. Validate AI consumption-only and explainability contract.
5. Demo MVP behavior.

### Incremental Delivery

1. Foundation complete.
2. Deliver US1 and validate.
3. Deliver US2 and validate temporal correctness.
4. Deliver US3 and validate capability completeness.
5. Run final cross-cutting validation/signoff.

### Parallel Team Strategy

1. Shared workstream completes Phase 1 and Phase 2.
2. Stream A owns US1.
3. Stream B owns US2 once CDC foundation is available.
4. Stream C owns US3 capability checks and documentation split.
5. Final convergence in Phase 6.

---

## Notes

- All tasks keep architecture naming as `core`/`reference`/`consumption`.
- No task reopens closed decisions from continuity context.
- AI remains read-only and consumption-only throughout execution.
