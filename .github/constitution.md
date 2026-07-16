# Snowflake EV Data Pipeline Constitution

## Project Mode

**Mode**: UPGRADE

**Justification**: This is an existing, functional data pipeline. We evolve it through incremental improvements while preserving operational integrity and git history.

---

## Core Principles

### I. Cost Optimization & Free-First Principle
Every design decision must demonstrate cost awareness. Storage footprint, compute cycles, data transfer, and Snowflake resource consumption must be justified. Use Iceberg on Azure Blob Storage for cold data, Dynamic Tables for near-real-time efficiency, and stream-triggered tasks to avoid wasted compute.

**Free-First Rule**: When solving a problem, prefer free or open-source solutions. Paid solutions are only considered after deep analysis against all 9 core principles, and only when they deliver significant convenience gains that justify the cost differential.

**Non-negotiable**: 
- Cost impact analysis for any new transformation, table, or pipeline stage
- Cost-benefit analysis required for any paid tool or service adoption
- Default to free/open-source tools unless proven insufficient

### II. Data Quality as First-Class Citizen
Data quality is not an afterthought; it is enforced at every layer. Bronze accepts raw data; Silver validates schema and freshness; Gold enforces business rules. All transformations include automated quality checks with quarantine for failing records.

**Non-negotiable**: DQ checks must exist for every new dataset before it reaches consumption layers.

### III. Scalability by Design
The pipeline must handle data volume growth gracefully. Iceberg enables partition pruning; Dynamic Tables scale incrementally; Snowpark Python exploits parallel execution. Avoid hard-coded row limits or single-threaded designs.

**Non-negotiable**: New transformations must include documentation of expected scale and bottleneck mitigation.

### IV. Compliance & Auditability
All data movements, transformations, and access are auditable. Secure Views track data sharing; Snowflake audit logs capture all DDL/DML; dbt tests validate contract compliance. Sensitive data (PII) is masked or excluded at appropriate layers.

**Non-negotiable**: Every transformation must have a clear lineage trail and (if applicable) masking strategy documented.

### V. Reproducibility & Versioning
Every pipeline run produces identical results given identical inputs. SQL is deterministic; seed data is versioned; dbt models are reproducible across environments. Code history is preserved; commits explain the "why" of changes.

**Non-negotiable**: No hard-coded dates, random seeds, or environment-specific logic without documentation.

### VI. Observability & Monitoring
Pipeline health is visible in real-time. Snowflake resource monitors alert on cost/quota drift; data quality dashboards surface anomalies; task DAG execution is logged with SLA tracking. Failures trigger notifications, not silent degradation.

**Non-negotiable**: Every transformation pipeline must have associated monitoring and alert rules.

### VII. Documentation as Code
Documentation lives alongside code. dbt YAML schemas document data contracts; SQL comments explain business logic; README files guide new contributors. Diagrams are updated when architecture changes.

**Non-negotiable**: No undocumented transformations; schema.yml and pipeline_documentation.md are the source of truth.

### VIII. Security & Data Governance
Data access is role-based and minimal. Secrets (API keys, connection strings) are managed via Snowflake secrets, never hardcoded. Shared data uses Secure Data Sharing with role-level granularity. External data integrations are validated.

**Non-negotiable**: No credentials in code; all external integrations reviewed for security posture before merging.

### IX. Portability & Open Formats
Core data lives in open formats (Iceberg on Azure Blob Storage) to enable multi-tool consumption. Avoid lock-in to Snowflake-only features for critical tables. dbt models remain portable to other SQL dialects where possible.

**Non-negotiable**: Gold-layer critical fact/dimension tables must be available in Iceberg format.

---

## Development Workflow

### Spec-Driven Development
Every feature or significant change begins with a specification:
1. **Clarify requirement** with user, including acceptance criteria and impact analysis
2. **Write specification** documenting feature scope, data contract, and quality rules
3. **Create plan and tasks** with clear ownership and dependencies
4. **Implement** against approved plan with continuous validation

### Agent Behavior & Approval Gates
- **Single Question Only**: I ask one clear question at a time; no compound questions.
- **User Approval Required**: Before implementing any change, I will present options with clear analysis tied to our principles and request explicit approval.
- **Principle-Based Analysis**: When multiple paths exist, I analyze each against our 9 core principles (cost, DQ, scalability, compliance, reproducibility, observability, documentation, security, portability) and recommend based on this framework.
- **No Unilateral Changes**: Implementation only proceeds after user confirms the specification and plan.

### Code Organization
- **Bronze** (02_bronze/): Raw ingestion, schema validation
- **Silver** (03_silver/): Cleansed, deduplicated, Dynamic Tables
- **Gold** (04_gold/): Business-ready fact/dimension tables via Snowpark + dbt
- **Quality** (05_data_quality/): Validation rules, quarantine, monitoring
- **Iceberg** (06_iceberg/): Open-format exports for portability
- **Sharing** (07_sharing/): Secure views for external consumers
- **Cost Governance** (08_cost_governance/): Resource monitors and quota tracking
- **Analytics** (09_analyst_streamlit/ + 10_dbt_project/): User-facing tools and testable SQL models

### Testing & Validation
- **dbt Tests**: 10+ tests across staging and gold models; all must pass before merge
- **DQ Validations**: 5 validation types (row count, schema, freshness, uniqueness, business rules)
- **Manual Smoke Tests**: New pipelines verified in dev environment before production deployment

---

## Governance

**Amendment Process**:
1. Changes to this constitution require documented rationale tied to lessons learned or new constraints.
2. Version bumps follow semantic versioning: MAJOR (principle removal/redefinition), MINOR (new principle), PATCH (clarification).
3. All amendments logged with effective date and authored by project lead or consensus.

**Compliance Review**:
- All PRs verified against constitution principles before merge.
- Code review checklist includes: DQ validations present, cost impact documented, audit trail viable, documentation complete.
- Quarterly review of pipeline metrics (cost, data freshness, error rate) against constitution commitments.

**Escalation**:
- Constitution violations (e.g., undocumented transformations, missing DQ checks, credentials in code) block merge until resolved.
- Exemptions require explicit justification and signed-off by project lead with sunset date.

---

**Version**: 1.0.0 | **Ratified**: 2026-07-09 | **Last Amended**: 2026-07-09
