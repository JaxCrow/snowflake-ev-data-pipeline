# CDC Evidence Matrix

Date: 2026-07-22  
Version: 1.0  
Scope: Operational evidence tracking for Airbyte OSS -> Snowflake landing/reference -> SCD2/effective-date

## Instructions

- Use one row per executed validation evidence item.
- Do not mark Pass until evidence link is attached and reviewed.
- Keep all timestamps in UTC.
- Use Incident ID when Result = Fail or Warning.

## Result Legend

- Pass: evidence meets acceptance criteria.
- Warning: evidence available but outside threshold, requires follow-up.
- Fail: acceptance criteria not met.
- Blocked: not executable due to dependency or outage.

## Evidence Tracking Table

| Evidence ID | Category | Validation Item | Acceptance Criteria | Owner | Environment | Timestamp UTC | Result | Evidence Link | Incident ID | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| CDC-001 | Cadence | 72h run history completeness | >= 99% successful runs in last 72h | | Product | | | | | |
| CDC-002 | Cadence | Sync interval stability | 15 min +/- 3 min average interval | | Product | | | | | |
| CDC-003 | Cadence | Gap detection | No untracked gap > 30 min | | Product | | | | | |
| CDC-004 | Lineage | 4-hop lineage mapping completeness | 100% of critical datasets mapped source->landing->reference->consumption | | Product | | | | | |
| CDC-005 | Lineage | Batch ID propagation | Each consumption batch traceable to one Airbyte sync | | Product | | | | | |
| CDC-006 | Lineage | Orphan detection in reference | Zero orphan records in reference | | Product | | | | | |
| CDC-007 | SCD2 | Active row uniqueness | Zero keys with more than one active row | | Product | | | | | |
| CDC-008 | SCD2 | Temporal overlap check | Zero overlap violations per business key | | Product | | | | | |
| CDC-009 | SCD2 | Versioning correctness | 100% applicable CDC changes versioned correctly | | Product | | | | | |
| CDC-010 | Effective Date | Before/after change scenario A | Events before effective date use previous version | | Product | | | | | |
| CDC-011 | Effective Date | Before/after change scenario B | Events after effective date use new version | | Product | | | | | |
| CDC-012 | Effective Date | Latest-value overwrite check | Zero latest-value overwrite defects | | Product | | | | | |
| CDC-013 | Freshness | Ingestion lag threshold | Lag under agreed threshold (recommended < 30 min) | | Product | | | | | |
| CDC-014 | Quality | Critical quality rules | 100% critical quality rules pass | | Product | | | | | |
| CDC-015 | Quality | Exclusions auditability | All impactful exclusions auditable | | Product | | | | | |
| CDC-016 | Failure Handling | Extraction failure simulation | Recovery completed without data loss/duplication | | Product | | | | | |
| CDC-017 | Failure Handling | SCD2 apply failure simulation | Recovery completed and SCD2 integrity preserved | | Product | | | | | |
| CDC-018 | Rollback | Rollback and reprocess drill | RTO met and post-recovery validations pass | | Product | | | | | |
| CDC-019 | Security | Secret exposure check | Zero secrets in repository artifacts | | Product | | | | | |
| CDC-020 | Security | Least-privilege role validation | Role mapping approved and validated | | Product | | | | | |
| CDC-021 | Security | Audit trail verification | Critical access and execution events traceable | | Product | | | | | |
| CDC-022 | Exit Gate | Critical incident status | Open critical incidents = 0 | | Product | | | | | |
| CDC-023 | Exit Gate | Final readiness sign-off | Ops + Data Engineering sign-off complete | | Product | | | | | |

## Optional Summary Block (Daily)

| Date UTC | Total Items | Pass | Warning | Fail | Blocked | Reviewer | Summary |
|---|---|---|---|---|---|---|---|
| | | | | | | | |
