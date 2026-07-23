# CDC Evidence Matrix - Mock Run (1 Day)

Date: 2026-07-22  
Version: 1.0  
Type: Synthetic example for guidance only (not production evidence)

## Usage Notes

- This file demonstrates how to populate the operational matrix during a real run.
- Replace all owner names, timestamps, links, and outcomes with real execution records.
- Keep UTC timestamps and attach auditable links to logs, dashboards, and query outputs.

## Mock Scenario

- Environment: Product
- Observation window: 24h
- Cadence baseline: 15-minute incremental sync
- Simulated incidents:
  - one temporary extraction timeout recovered by retry
  - one warning-level lag breach during network jitter

## Filled Example Table

| Evidence ID | Category | Validation Item | Acceptance Criteria | Owner | Environment | Timestamp UTC | Result | Evidence Link | Incident ID | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| CDC-001 | Cadence | 72h run history completeness | >= 99% successful runs in last 72h | DataOps Lead | Product | 2026-07-22T06:05:00Z | Pass | https://internal-observability/airbyte/runs/summary-72h | | Success rate 99.4% including auto-retry recoveries |
| CDC-002 | Cadence | Sync interval stability | 15 min +/- 3 min average interval | DataOps Lead | Product | 2026-07-22T06:07:00Z | Pass | https://internal-observability/airbyte/intervals/day-2026-07-22 | | Average 15m42s |
| CDC-003 | Cadence | Gap detection | No untracked gap > 30 min | DataOps Lead | Product | 2026-07-22T06:08:00Z | Warning | https://internal-observability/airbyte/gaps/day-2026-07-22 | INC-2026-0712 | One 31m gap tied to network incident; tracked and resolved |
| CDC-004 | Lineage | 4-hop lineage mapping completeness | 100% of critical datasets mapped source->landing->reference->consumption | Analytics Engineer | Product | 2026-07-22T06:20:00Z | Pass | https://internal-catalog/lineage/ev-critical-datasets | | All critical datasets mapped |
| CDC-005 | Lineage | Batch ID propagation | Each consumption batch traceable to one Airbyte sync | Analytics Engineer | Product | 2026-07-22T06:24:00Z | Pass | https://internal-observability/lineage/batch-propagation | | 100 sampled batches matched one-to-one |
| CDC-006 | Lineage | Orphan detection in reference | Zero orphan records in reference | Data Engineer | Product | 2026-07-22T06:27:00Z | Pass | https://internal-sql-results/reference-orphan-check-20260722 | | Orphan count = 0 |
| CDC-007 | SCD2 | Active row uniqueness | Zero keys with more than one active row | Data Engineer | Product | 2026-07-22T06:40:00Z | Pass | https://internal-sql-results/scd2-active-uniqueness-20260722 | | Violations = 0 |
| CDC-008 | SCD2 | Temporal overlap check | Zero overlap violations per business key | Data Engineer | Product | 2026-07-22T06:42:00Z | Pass | https://internal-sql-results/scd2-overlap-check-20260722 | | Overlaps = 0 |
| CDC-009 | SCD2 | Versioning correctness | 100% applicable CDC changes versioned correctly | Data Engineer | Product | 2026-07-22T06:45:00Z | Pass | https://internal-sql-results/scd2-versioning-accuracy-20260722 | | 250/250 applicable changes correct |
| CDC-010 | Effective Date | Before/after change scenario A | Events before effective date use previous version | QA Data Analyst | Product | 2026-07-22T07:00:00Z | Pass | https://internal-test-evidence/effective-date/scenario-a-before | | Historical mapping preserved |
| CDC-011 | Effective Date | Before/after change scenario B | Events after effective date use new version | QA Data Analyst | Product | 2026-07-22T07:03:00Z | Pass | https://internal-test-evidence/effective-date/scenario-b-after | | New version applied post-effective date |
| CDC-012 | Effective Date | Latest-value overwrite check | Zero latest-value overwrite defects | QA Data Analyst | Product | 2026-07-22T07:05:00Z | Pass | https://internal-test-evidence/effective-date/latest-value-guard | | Defects = 0 |
| CDC-013 | Freshness | Ingestion lag threshold | Lag under agreed threshold (recommended < 30 min) | SRE Data Platform | Product | 2026-07-22T07:20:00Z | Warning | https://internal-observability/lag/day-2026-07-22 | INC-2026-0712 | Peak lag 33 min during transient network degradation |
| CDC-014 | Quality | Critical quality rules | 100% critical quality rules pass | DQ Owner | Product | 2026-07-22T07:24:00Z | Pass | https://internal-dq/rules/critical/day-2026-07-22 | | All critical checks pass |
| CDC-015 | Quality | Exclusions auditability | All impactful exclusions auditable | DQ Owner | Product | 2026-07-22T07:27:00Z | Pass | https://internal-dq/exclusions/audit/day-2026-07-22 | | All exclusions linked to rule IDs |
| CDC-016 | Failure Handling | Extraction failure simulation | Recovery completed without data loss/duplication | SRE Data Platform | Product | 2026-07-22T08:00:00Z | Pass | https://internal-chaos-tests/cdc-extraction-recovery-20260722 | | Recovered on retry #2, no duplicate impact |
| CDC-017 | Failure Handling | SCD2 apply failure simulation | Recovery completed and SCD2 integrity preserved | SRE Data Platform | Product | 2026-07-22T08:15:00Z | Pass | https://internal-chaos-tests/scd2-apply-recovery-20260722 | | Transaction rollback + reapply successful |
| CDC-018 | Rollback | Rollback and reprocess drill | RTO met and post-recovery validations pass | Incident Manager | Product | 2026-07-22T08:30:00Z | Pass | https://internal-drills/rollback-reprocess-20260722 | | RTO 18 min, all post-checks pass |
| CDC-019 | Security | Secret exposure check | Zero secrets in repository artifacts | Security Engineer | Product | 2026-07-22T09:00:00Z | Pass | https://internal-security/scans/secret-detection-20260722 | | No secrets detected |
| CDC-020 | Security | Least-privilege role validation | Role mapping approved and validated | Security Engineer | Product | 2026-07-22T09:07:00Z | Pass | https://internal-security/reviews/least-privilege-20260722 | | Access matrix approved |
| CDC-021 | Security | Audit trail verification | Critical access and execution events traceable | Security Engineer | Product | 2026-07-22T09:10:00Z | Pass | https://internal-security/audit-trace/day-2026-07-22 | | 100% sampled events traceable |
| CDC-022 | Exit Gate | Critical incident status | Open critical incidents = 0 | Incident Manager | Product | 2026-07-22T10:00:00Z | Pass | https://internal-incident/board/day-2026-07-22 | | All critical incidents closed |
| CDC-023 | Exit Gate | Final readiness sign-off | Ops + Data Engineering sign-off complete | Program Owner | Product | 2026-07-22T10:30:00Z | Pass | https://internal-approvals/cdc-readiness-signoff-20260722 | | Joint sign-off complete |

## Mock Daily Summary

| Date UTC | Total Items | Pass | Warning | Fail | Blocked | Reviewer | Summary |
|---|---|---|---|---|---|---|---|
| 2026-07-22 | 23 | 21 | 2 | 0 | 0 | Program Owner | Ready with follow-up action for lag hardening and gap prevention |

## Follow-Up Actions from Mock

1. Add proactive network jitter alert before 30-minute lag threshold.
2. Add auto-notification for cadence gap when interval exceeds 25 minutes.
3. Re-run cadence validation after alert tuning to close warning items.
