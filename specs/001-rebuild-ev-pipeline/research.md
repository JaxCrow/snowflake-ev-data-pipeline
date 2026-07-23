# Research Decisions: Rebuild Snowflake EV Pipeline

Date: 2026-07-15
Spec: specs/001-rebuild-ev-pipeline/spec.md

## Decision 1: Environment Scope

- Decision: Use Dev-only environment for the first rebuild.
- Rationale: Fastest path to validate end-to-end architecture and reduce coordination overhead.
- Alternatives considered:
  - Dev + Prod: rejected for first pass due to slower rollout and additional governance steps.
  - Dev + Test + Prod: rejected as out of scope for urgent rebuild.

## Decision 2: Execution Mode

- Decision: Use manual step-by-step setup for this pass.
- Rationale: Reduces upfront automation work and aligns with urgent timeline.
- Alternatives considered:
  - Full IaC now: rejected as higher initial setup cost and longer lead time.
  - Hybrid: deferred to post-rebuild hardening phase.

## Decision 3: Catalogue Enrichment

- Decision: NeonDB PostgreSQL CDC is mandatory.
- Rationale: Curated metrics require catalogue attributes for complete analytics outputs.
- Alternatives considered:
  - Optional CDC: rejected because it weakens metric completeness.
  - Batch snapshot only: rejected due to lower freshness and weaker change tracking.

## Decision 4: CDC Cadence

- Decision: 12-hour synchronization cadence.
- Rationale: Matches repository architecture and cost-optimized operating model.
- Alternatives considered:
  - Hourly sync: rejected due to higher compute and operational cost for current use case.
  - Near-real-time CDC: rejected for complexity/cost mismatch in initial Dev rebuild.

## Decision 5: Completion Gate

- Decision: Rebuild is complete only when SQL stages + dbt + DQ + Streamlit metric validation all pass.
- Rationale: Ensures technical execution and analyst-facing value are both verified.
- Alternatives considered:
  - SQL-only completion: rejected as insufficient for analytical confidence.
  - SQL + dbt only: rejected because DQ and analyst output accuracy would remain unproven.

## Decision 6: Cost and Governance

- Decision: Keep cost controls active during rebuild (auto-suspend, resource monitors, staged execution).
- Rationale: Aligns with constitution free-first and cost optimization principles.
- Alternatives considered:
  - Unconstrained execution: rejected as governance violation and budget risk.

## Decision 7: Snowflake Authentication (Current Run)

- Decision: Use interactive password entry in terminal for this run.
- Rationale: SSO external browser is currently blocked by IdP/SAML account-parameter errors.
- Alternatives considered:
  - SSO externalbrowser: deferred until IdP/SAML integration is fixed.
  - Key pair auth: selected as target steady-state method, not required to unblock today.

## Decision 8: Execution Role (Current Run)

- Decision: Use ACCOUNTADMIN temporarily for Dev readiness and early-stage execution.
- Rationale: Reduces setup friction for first-pass validation and object creation.
- Alternatives considered:
  - Dedicated least-privilege role now: deferred to hardening phase after baseline validation.

## Decision 9: Secrets Handling Policy

- Decision: Secrets are entered interactively in terminal or supplied as local environment variables only.
- Rationale: Aligns with constitution security rules and prevents credential leakage.
- Non-negotiable constraints:
  - No secrets in repository files (SQL, YAML, markdown, or config committed to git).

## Decision 10: Scope for Today

- Decision: Limit active execution scope to readiness closure plus Stage 2 maximum.
- Rationale: Keep risk low while validating governance and ingestion baseline.
- Scope boundary:
  - Included: readiness evidence, Stage 1/2 validation.
  - Excluded: Stage 3+ execution until explicit approval.
