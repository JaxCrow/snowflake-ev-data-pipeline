# Tasks: Rebuild Snowflake EV Pipeline

**Input**: Design documents from `specs/001-rebuild-ev-pipeline/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/data-interfaces.md, quickstart.md

**Organization**: Tasks are grouped by user story and include stage-level acceptance checks.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete task)
- **[Story]**: User story label (`[US1]`, `[US2]`, `[US3]`)
- All tasks include explicit file paths

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare execution context, credentials, and baseline docs before stage execution.

- [ ] T001 Validate active feature context in `specs/001-rebuild-ev-pipeline/spec.md` and `specs/001-rebuild-ev-pipeline/plan.md`
- [ ] T002 [P] Confirm Snowflake access and role requirements in `01_infrastructure/01_infrastructure.sql`
- [ ] T003 [P] Confirm Azure storage landing path expectations documented in `00_documentation/pipeline_documentation.md`
- [ ] T004 [P] Confirm NeonDB access requirements for CDC in `04b_external_data_integration/01_postgresql_cdc.sql`
- [ ] T005 Create deployment run log template in `specs/001-rebuild-ev-pipeline/quickstart.md` (execution timestamps, outcomes, evidence links)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish blockers that must be complete before user story stage work begins.

**CRITICAL**: No user story implementation tasks begin until this phase is done.

- [ ] T006 Configure non-repo credential handling approach and annotate usage constraints in `specs/001-rebuild-ev-pipeline/research.md`
- [ ] T007 [P] Finalize environment constants and object naming alignment across `01_infrastructure/01_infrastructure.sql`, `02_bronze/01_bronze.sql`, `03_silver/01_silver.sql`, `04_gold/01_gold.sql`
- [ ] T008 [P] Validate CDC object naming alignment between `04b_external_data_integration/01_postgresql_cdc.sql` and `04_gold/01_gold.sql`
- [ ] T009 [P] Validate DQ object dependencies between `05_data_quality/01_data_quality.sql` and `02_bronze/01_bronze.sql`
- [ ] T010 Confirm stage execution order and rollback notes in `specs/001-rebuild-ev-pipeline/quickstart.md`

**Checkpoint**: Foundation complete, stage execution can start.

---

## Phase 3: User Story 1 - Rebuild Full Dev Pipeline (Priority: P1) MVP

**Goal**: Execute full Dev rebuild across all stages and prove curated metrics are produced end-to-end.

**Independent Test**: Execute stages in order and verify expected artifacts at each layer through acceptance checks.

### Implementation for User Story 1

- [ ] T011 [US1] Execute Stage 0 NeonDB schema/data preparation guided by `04b_external_data_integration/01_postgresql_cdc.sql`
- [ ] T012 [US1] Run Stage 0 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (catalogue schema exists, seed rows queryable)
- [ ] T013 [US1] Execute Stage 1 infrastructure SQL in `01_infrastructure/01_infrastructure.sql`
- [ ] T014 [US1] Run Stage 1 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (warehouse/database/schemas/integrations created)
- [ ] T015 [US1] Execute Stage 2 Bronze SQL in `02_bronze/01_bronze.sql`
- [ ] T016 [US1] Run Stage 2 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (raw table populated, stream/task chain active)
- [ ] T017 [US1] Execute Stage 3 Silver SQL in `03_silver/01_silver.sql`
- [ ] T018 [US1] Run Stage 3 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (dynamic table refreshes with expected latency)
- [ ] T019 [US1] Execute Stage 4 Gold SQL in `04_gold/01_gold.sql`
- [ ] T020 [US1] Run Stage 4 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (fact tables populated with expected aggregates)
- [ ] T021 [US1] Execute Stage 5 Data Quality SQL in `05_data_quality/01_data_quality.sql`
- [ ] T022 [US1] Run Stage 5 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (DQ procedures and monitoring views operational)
- [ ] T023 [US1] Execute Stage 6 Iceberg SQL in `06_iceberg/01_iceberg.sql`
- [ ] T024 [US1] Run Stage 6 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (Iceberg tables created and queryable)
- [ ] T025 [US1] Execute Stage 7 Sharing SQL in `07_sharing/01_sharing.sql`
- [ ] T026 [US1] Run Stage 7 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (secure views/share objects created)
- [ ] T027 [US1] Execute Stage 8 Cost Governance SQL in `08_cost_governance/01_cost_governance.sql`
- [ ] T028 [US1] Run Stage 8 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (resource monitors configured)
- [ ] T029 [US1] Execute Stage 9 analyst setup SQL in `09_analyst_streamlit/01_analyst_streamlit.sql`
- [ ] T030 [US1] Run Stage 9 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (semantic model objects prepared)
- [ ] T031 [US1] Validate Stage 10 dbt project configuration in `10_dbt_project/dbt_project.yml`, `10_dbt_project/profiles.yml`, `10_dbt_project/models/schema.yml`
- [ ] T032 [US1] Run Stage 10 acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (dbt models compile and are executable)

**Checkpoint**: Full staged rebuild completed in Dev with stage-level evidence.

---

## Phase 4: User Story 2 - Keep Catalogue Enrichment Current via CDC (Priority: P2)

**Goal**: Ensure NeonDB catalogue enrichment is mandatory and synchronized on 12-hour cadence.

**Independent Test**: Modify a catalogue record in NeonDB and verify propagation to enriched Snowflake outputs within the synchronization window.

### Implementation for User Story 2

- [ ] T033 [US2] Execute mandatory Stage 4b CDC SQL in `04b_external_data_integration/01_postgresql_cdc.sql`
- [ ] T034 [US2] Configure 12-hour CDC schedule settings in `04b_external_data_integration/01_postgresql_cdc.sql`
- [ ] T035 [US2] Verify CDC initial load completeness and record counts against source expectations in `specs/001-rebuild-ev-pipeline/quickstart.md`
- [ ] T036 [US2] Execute CDC acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (catalogue attributes present in Snowflake)
- [ ] T037 [US2] Execute enrichment join validation between CDC catalogue outputs and Gold facts in `04_gold/01_gold.sql`
- [ ] T038 [US2] Run enrichment acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (make/model/category reflected in curated outputs)
- [ ] T039 [US2] Run cadence acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (change appears within one 12-hour sync cycle)

**Checkpoint**: CDC mandatory stage operational and cadence verified.

---

## Phase 5: User Story 3 - Validate Operational Readiness in Dev (Priority: P3)

**Goal**: Validate dbt, DQ, and Streamlit metric correctness for deployment completion gate.

**Independent Test**: Execute validation gates and confirm metric answers align with expected curated values.

### Implementation for User Story 3

- [ ] T040 [US3] Execute dbt run and test workflow using `10_dbt_project/dbt_project.yml`, `10_dbt_project/profiles.yml`, `10_dbt_project/models/`
- [ ] T041 [US3] Run dbt acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (all required dbt tests pass)
- [ ] T042 [US3] Execute DQ validation workflow via `05_data_quality/01_data_quality.sql`
- [ ] T043 [US3] Run DQ acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (check outcomes observable, alert path validated)
- [ ] T044 [US3] Prepare analyst validation question set and expected answers in `09_analyst_streamlit/`
- [ ] T045 [US3] Validate Streamlit analytics responses against curated metrics using assets in `09_analyst_streamlit/`
- [ ] T046 [US3] Run Streamlit acceptance check and log result in `specs/001-rebuild-ev-pipeline/quickstart.md` (>=95% expected metric match)
- [ ] T047 [US3] Execute end-to-end completion gate review and record outcome in `specs/001-rebuild-ev-pipeline/quickstart.md`

**Checkpoint**: Completion gate satisfied (SQL + CDC + dbt + DQ + Streamlit).

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final readiness polish across all stories.

- [ ] T048 [P] Consolidate run evidence and stage outcomes in `specs/001-rebuild-ev-pipeline/quickstart.md`
- [ ] T049 [P] Update operations notes and known limitations in `specs/001-rebuild-ev-pipeline/research.md`
- [ ] T050 Finalize implementation readiness summary in `specs/001-rebuild-ev-pipeline/plan.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 (Setup): starts immediately
- Phase 2 (Foundational): depends on Phase 1 completion
- Phase 3 (US1): depends on Phase 2 completion
- Phase 4 (US2): depends on US1 through Gold stage completion (T020) and then executes Stage 4b
- Phase 5 (US3): depends on US1 and US2 completion
- Phase 6 (Polish): depends on all user stories complete

### User Story Dependencies

- US1 (P1): no dependency on other user stories
- US2 (P2): depends on baseline pipeline outputs from US1
- US3 (P3): depends on pipeline + CDC readiness from US1 and US2

### Stage-Level Acceptance Check Dependencies

- T012 depends on T011
- T014 depends on T013
- T016 depends on T015
- T018 depends on T017
- T020 depends on T019
- T022 depends on T021
- T024 depends on T023
- T026 depends on T025
- T028 depends on T027
- T030 depends on T029
- T032 depends on T031
- T036 depends on T033, T034, T035
- T038 depends on T037
- T039 depends on T036 and observed cycle window
- T041 depends on T040
- T043 depends on T042
- T046 depends on T044, T045
- T047 depends on T041, T043, T046

### Parallel Opportunities

- T002, T003, T004 can run in parallel
- T007, T008, T009 can run in parallel
- T048 and T049 can run in parallel after completion gate success

---

## Parallel Example

```bash
# Setup parallel block
T002 + T003 + T004

# Foundational parallel block
T007 + T008 + T009

# Final polish parallel block
T048 + T049
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Complete Phase 1 and Phase 2.
2. Complete US1 stage execution and acceptance checks through T032.
3. Validate Gold metric availability as interim milestone.

### Incremental Delivery

1. Deliver US1 full staged rebuild baseline.
2. Add US2 mandatory CDC enrichment and cadence validation.
3. Add US3 operational and analyst confidence gates.
4. Finalize with polish and implementation summary.

### Team Parallel Strategy

1. Engineer A: stage execution (US1)
2. Engineer B: CDC enrichment and cadence validation (US2)
3. Engineer C: dbt/DQ/Streamlit validation and completion gate (US3)

---

## Notes

- All tasks are executable without adding new source directories.
- Tasks preserve existing repository stage layout and governance constraints.
- Acceptance checks are explicit and logged in quickstart evidence.
