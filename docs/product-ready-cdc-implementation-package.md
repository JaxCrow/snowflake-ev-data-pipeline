# Product-Ready Implementation Package

## Snowflake EV Data Pipeline

Date: 2026-07-22  
Version: 1.0  
Scope: External CDC runtime package (Airbyte OSS -> Snowflake landing/reference -> SCD2/effective-date)

---

## 1. Continuity Baseline (Mandatory)

This package is produced under the continuity baseline defined in:
- 00_documentation/speckit-continuity-context.md
- 00_documentation/speckit-startup-prompt.md

Closed decisions are preserved and not reopened:
- Architecture naming remains core/reference/consumption.
- AI behavior remains read-only and consumption-only.
- CDC transport remains externalized via Airbyte OSS in Docker.
- Snowflake trial constraint remains: no direct runtime External Access Integration path.

---

## 2. Objective

Deliver a Product-ready operational package that defines how to run and validate external CDC from NeonDB PostgreSQL into Snowflake, including:
- runtime operating design
- operational runbook
- validation model
- failure handling and rollback
- evidence checklist with measurable acceptance criteria

---

## 3. Runtime Operating Design

### 3.1 Topology

- Source: NeonDB PostgreSQL (CDC-enabled).
- CDC Engine: Airbyte OSS in Docker (external runtime).
- Destination Zone 1: Snowflake landing objects for raw CDC deltas.
- Destination Zone 2: Snowflake reference objects for SCD Type 2 historical catalog.
- Downstream consumption: materialized outputs consumed by AI and users.

### 3.2 End-to-End Flow

1. CDC extracts insert/update/delete changes from NeonDB.
2. Airbyte sync writes incremental payloads into Snowflake landing.
3. Controlled apply process transforms landing deltas into reference SCD2 history.
4. Consumption reads effective-dated state from core + reference logic.
5. AI reads only consumption outputs.

### 3.3 Cadence and Retry Policy

- Product baseline cadence: every 15 minutes incremental sync.
- Retry strategy: exponential backoff with capped attempts.
- Recommended retry profile: 5 attempts at 1m, 2m, 4m, 8m, and 15m.
- Failed batches are marked reprocessable and cannot proceed to SCD2 apply until recovered.

### 3.4 Integrity and Idempotency Controls

- Event-level technical key: source business key + operation timestamp + CDC offset/LSN.
- Landing dedup before apply.
- Ordered apply per business key to preserve SCD2 correctness.
- Transactional apply boundary for deterministic recovery.

### 3.5 Security and Governance

- Least-privilege users for source and destination connectors.
- Secrets stored only in runtime secret stores/environment variables.
- No secrets in repository files.
- Audit logs required for syncs, apply runs, and exception handling.

### 3.6 Observability

Mandatory metrics:
- CDC lag
- extracted row count
- landed row count
- merged SCD2 row count
- rejected/failed row count

Mandatory alerts:
- sync failure
- lag threshold breach
- schema drift
- SCD2 merge anomaly

---

## 4. Operational Runbook (Step-by-Step)

### 4.1 Pre-Run Readiness

- Validate NeonDB CDC prerequisites and replication permissions.
- Validate Airbyte OSS Docker runtime is up with persistent state.
- Validate network connectivity NeonDB -> Airbyte and Airbyte -> Snowflake.
- Validate landing and reference objects exist in Snowflake.
- Validate credentials are present through secure runtime injection.

### 4.2 Controlled Startup

1. Configure Source connector (PostgreSQL CDC incremental).
2. Configure Destination connector (Snowflake landing schema).
3. Run initial controlled sync in bounded window.
4. Record first evidence set: start/end times, row counts, status, errors.

### 4.3 Recurring Operation

1. Execute incremental sync at 15-minute cadence.
2. Trigger landing -> reference SCD2 apply after successful sync.
3. Enforce ordering and idempotency controls.
4. Publish cycle-level monitoring metrics and status.

### 4.4 Per-Cycle Validation

- Extraction vs landing row-count reconciliation.
- Landing duplicate check after dedup.
- SCD2 active-row uniqueness per business key.
- Freshness and lag compliance.
- Effective-date join correctness sampling.

### 4.5 Failure Handling

Failure type A: CDC extraction failure
- apply retries by policy
- if retries exhausted, raise incident and hold downstream apply

Failure type B: landing write failure
- mark batch failed
- block SCD2 apply
- reprocess batch after destination remediation

Failure type C: SCD2 apply failure
- rollback current apply transaction
- preserve previous consistent state
- re-run apply idempotently on the same recovered batch

### 4.6 Rollback Procedure

Trigger conditions:
- critical data-quality breach
- SCD2 integrity violation
- unreconciled end-to-end count mismatch

Rollback steps:
1. freeze new apply executions
2. identify last confirmed good batch
3. revert failed batch effects (transactional rollback or validated restoration mechanism)
4. re-run from last consistent CDC offset
5. execute full validation gate before reopening normal operation

### 4.7 Daily Closeout

Produce daily operations report with:
- run availability
- average and max lag
- merge success rates
- incidents and remediation
- effective-date propagation evidence

---

## 5. Formal Evidence Checklist (Acceptance Gate)

### 5.1 Cadence and Continuity

Required evidence:
- Airbyte run history (last 72 hours)
- start/end timestamps and status per run
- retry records

Acceptance criteria:
- successful runs >= 99% over 72 hours
- average execution interval within 15 min +/- 3 min
- no untracked execution gap > 30 min

### 5.2 End-to-End Lineage

Required evidence:
- source -> landing -> reference -> consumption mapping
- batch/sync identifier propagated across layers
- apply transformation log

Acceptance criteria:
- 100% traceability for critical datasets across four hops
- each consumption batch traceable to one Airbyte sync
- zero orphan records in reference without landing lineage

### 5.3 SCD2 Integrity

Required evidence:
- active row uniqueness checks per business key
- temporal continuity and overlap checks
- versioned change counts by batch

Acceptance criteria:
- zero keys with more than one active row
- zero temporal overlap violations
- 100% CDC changes correctly versioned when applicable

### 5.4 Effective-Date Propagation

Required evidence:
- test scenarios with catalog changes before/after event timestamps
- effective-dated join validation outputs in consumption

Acceptance criteria:
- events before effective date use prior version
- events after effective date use new version
- zero latest-value overwrite defects in test scenarios

### 5.5 Quality and Freshness for AI Consumption

Required evidence:
- freshness and lag metrics
- quality rule outcomes
- exclusions/filters audit log

Acceptance criteria:
- lag within agreed threshold (recommended baseline: < 30 min)
- critical quality rules all pass
- all impactful exclusions are auditable

### 5.6 Failure and Rollback Readiness

Required evidence:
- one simulated extraction failure
- one simulated SCD2 apply failure
- one successful rollback/reprocess exercise

Acceptance criteria:
- recovery without data loss or duplicate side effects
- recovery time objective is met
- post-recovery state passes SCD2 and count reconciliation

### 5.7 Security and Operational Compliance

Required evidence:
- least-privilege role mapping
- secret rotation proof
- access and execution audit records

Acceptance criteria:
- zero secrets committed to repository artifacts
- least-privilege validated
- auditability of critical access and execution events

---

## 6. Final Product-Ready Exit Criteria

The package is approved for operational execution when all conditions are true:
- all checklist categories are pass
- open critical incidents = 0
- evidence is consolidated and reviewed by operations and data engineering owners

---

## 7. Non-Negotiable Guardrails

- Do not introduce direct Snowflake runtime external access path while trial constraints remain.
- Do not bypass consumption-only rule for AI.
- Do not execute runtime or infrastructure commands without explicit user approval.
- Keep one-question-at-a-time confirmation protocol for stage transitions.

---

## 8. Recommended Execution Sequence

1. Validate feature artifacts remain aligned with this package baseline.
2. Implement Airbyte runtime topology and connector hardening.
3. Implement landing-to-reference SCD2 apply contract.
4. Implement monitoring and alerting.
5. Execute evidence checklist and close readiness gate.

---

## 9. Execution Artifacts

- Evidence matrix template for live execution tracking: docs/cdc-evidence-matrix.md
- Mock run example (1 day) for guided completion: docs/cdc-evidence-matrix-mock-run-1day.md
