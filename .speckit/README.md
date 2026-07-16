# SpecKit Setup & Usage Guide

## Overview

GitHub SpecKit is now installed for the **Snowflake EV Data Pipeline** project. This guide walks you through using it effectively.

---

## 📁 Directory Structure

```
.speckit/
├── speckit.yml              # Main configuration
├── rules.md                 # Quality gates & standards
├── README.md                # This file
└── templates/
    ├── feature-spec.md      # For new features
    ├── pipeline-spec.md     # For new pipelines
    ├── transformation-spec.md # For transformations
    └── bug-report.md        # For bug fixes
```

---

## 🚀 Getting Started

### 1. **Create a Specification**

Choose the right template based on your work:

| Work Type | Template | Use Case |
|-----------|----------|----------|
| New analytics feature | `feature-spec.md` | New data product, new report, new Streamlit feature |
| New data pipeline | `pipeline-spec.md` | New data source, new medallion layer, new ingestion |
| Individual transformation | `transformation-spec.md` | New SQL transformation, dbt model, Snowpark SP |
| Bug fix | `bug-report.md` | Fixing a data pipeline issue, incorrect transformation |

**Example: Create a new feature specification**

```bash
# Copy the template
cp .speckit/templates/feature-spec.md docs/specs/my-feature-spec.md

# Fill it out using the template
# - Title, description, acceptance criteria
# - Cost impact analysis
# - Data quality considerations
# - Scalability notes
```

### 2. **Review Quality Gates**

Before moving to planning, verify your spec meets the **Specification Quality Gate** (see `.speckit/rules.md`):

- [ ] All required fields completed
- [ ] Aligned with 7 project principles
- [ ] No critical unknowns
- [ ] Dependencies & risks identified

### 3. **Create an Implementation Plan**

Once spec is approved:

```bash
# Create plan from spec
cp .speckit/templates/plan-template.md docs/plans/my-plan.md

# Break into tasks
# - Map each task to acceptance criteria
# - Estimate effort
# - Identify dependencies
```

### 4. **Implement & Test**

Follow the implementation workflow:

```bash
# Create feature branch
git checkout -b feature/my-feature

# Implement following code standards in rules.md
# - SQL style guide
# - Snowpark Python standards
# - dbt YAML conventions
# - Testing requirements (80% coverage)

# Commit with clear messages
git commit -m "feat: [REQ-X] Add new transformation"

# Create PR with spec & plan linked
```

### 5. **Deploy & Monitor**

- [ ] Runbook created/updated
- [ ] Monitoring configured
- [ ] Alerts tested
- [ ] Post-deployment validation done

---

## 📋 Templates Reference

### Feature Specification
Use when: New feature, enhancement, new capability

**Key Sections**:
- Objectives & acceptance criteria
- Cost impact analysis
- Data quality strategy
- Scalability notes
- Implementation approach
- Success metrics

**Example Usage**:
```
Title: Add EV Market Insights Dashboard
Acceptance Criteria:
  - Dashboard displays top 10 EV models by registration
  - Data refreshes daily
  - Under 100 query cost/month
Data Quality:
  - 99% completeness check on registration count
  - Daily trend reconciliation
```

### Pipeline Specification
Use when: New data ingestion, new medallion layer, new data source

**Key Sections**:
- Source & target systems
- Data transformation logic
- Medallion layer details
- Quality framework
- SLA & performance targets
- Cost estimate

**Example Usage**:
```
Pipeline: PostgreSQL Catalog CDC to Silver
Source: PostgreSQL vehicles table (CDC enabled)
Target: SILVER.STG_VEHICLES (Dynamic Table)
SLA: 1-hour freshness
Cost: ~$50/month compute + storage
```

### Transformation Specification
Use when: Individual SQL transformation, dbt model, stored procedure

**Key Sections**:
- Business context
- Source & target tables
- Transformation logic & business rules
- Data quality validation
- Performance considerations
- Testing strategy

**Example Usage**:
```
Transformation: Calculate EV Market Share by Model
Source: GOLD.FACT_EV_REGISTRATIONS
Target: GOLD.FACT_EV_MARKET_METRICS
Business Rule: Market share = (model registrations / total registrations) * 100
Quality: Verify market shares sum to 100%
```

### Bug Report
Use when: Data pipeline issue, incorrect output, data quality failure

**Key Sections**:
- Clear description & steps to reproduce
- Expected vs actual behavior
- Root cause analysis
- Impact analysis
- Proposed fix
- Preventive measures

---

## 🎯 Workflow Integration

### Local Copilot Chat Prompts

Use these prompts in VS Code Copilot Chat with `@` mention:

```bash
# Clarify a requirement
@spec-clarify: Should we add a dimension table for vehicle make/model?

# Create a specification
@specify: Draft a spec for a new EV adoption trend metric

# Create an implementation plan
@plan: Break down the EV market metrics dashboard into tasks

# Implement code
@implement: Write the SQL transformation for market share calculation

# Create tasks from plan
@tasks: Generate task list for the market metrics dashboard
```

**Access prompts**: `.github/prompts/`

---

## 📐 Project Principles Checklist

Every specification must address all 7 principles:

- [ ] **Cost Optimization** - Justify costs, show free-first alternatives
- [ ] **Data Quality** - Define quality checks & quarantine strategy
- [ ] **Scalability** - Address growth & bottleneck mitigation
- [ ] **Compliance** - Document lineage & audit trail
- [ ] **Reproducibility** - Ensure deterministic design
- [ ] **Observability** - Define monitoring & alerts
- [ ] **Documentation** - Include data dictionaries & runbooks

---

## 🔍 Examples

### Example 1: Feature Spec
**File**: `docs/specs/ev-adoption-dashboard-spec.md`

```markdown
# Feature: EV Adoption Trend Dashboard

## Acceptance Criteria
- Dashboard shows EV registrations by month for past 5 years
- Includes trend line and growth rate
- Updates daily
- Under $100/month cost

## Cost Impact
- Compute: $30/month (daily aggregation)
- Storage: Minimal (already have raw data)
- Total: $30/month (cost-optimized via Dynamic Table)

## Data Quality
- 99% completeness of registration records
- Daily row-count validation
- Monthly reconciliation with source

## Scalability
- Current: 1M EV records
- Growth: 2x/year projected
- Design: Partition by model year, aggregate at top level
```

### Example 2: Pipeline Spec
**File**: `docs/specs/postgresql-cdc-pipeline-spec.md`

```markdown
# Pipeline: PostgreSQL Vehicle Catalog Replication

## Source
PostgreSQL production database (vehicles table, 100K rows)

## Target
SILVER.STG_VEHICLES (Dynamic Table, incremental)

## SLA
- Freshness: 1 hour max latency
- Availability: 99.5%

## Cost
- Compute: CDC task runs hourly = ~$50/month
- Storage: 100K rows × 1KB = 100MB
- Data transfer: Cross-region → $100/month
- Total: ~$150/month
```

### Example 3: Implementation Plan from Spec
**File**: `docs/plans/market-metrics-plan.md`

```markdown
# Implementation Plan: EV Market Metrics

## Task 1: Create Silver staging table
- Schema: model, registrations, market_share_pct
- Estimated effort: 2 hours

## Task 2: Write transformation SQL
- Aggregate by model
- Calculate percentages
- Estimated effort: 4 hours

## Task 3: Add data quality tests
- Verify sum = 100%
- Check for nulls
- Estimated effort: 2 hours

## Task 4: Create Gold fact table
- Denormalize for consumption
- Add time dimensions
- Estimated effort: 3 hours

Total: 11 hours
```

---

## ✅ Quality Gates

### Specification Quality Gate
✅ PASS if:
- All required sections completed (no `[NEEDS CLARIFICATION]`)
- Addresses all 7 principles
- Cost impact quantified or justified
- Data quality strategy defined
- Success metrics measurable
- No critical dependencies unresolved

### Plan Quality Gate
✅ PASS if:
- Every acceptance criterion mapped to ≥1 task
- Every task has clear definition of done
- Effort estimates provided (±25%)
- Dependencies explicit
- Test strategy defined
- Total effort realistic

### Implementation Review Gate
✅ PASS if:
- Code follows standards (SQL, Python, dbt)
- Tests pass (≥80% coverage)
- Data quality validated
- Documentation updated
- Performance acceptable
- No security issues

---

## 📞 Support & Questions

**How to use SpecKit effectively?**
- Read `.speckit/rules.md` for standards & guidelines
- Use templates in `.speckit/templates/`
- Follow workflow in this README
- Reference `docs/constitution.md` for principles

**Need help writing a spec?**
- Use `@spec-clarify` prompt in Copilot Chat
- Review similar specs in `docs/specs/`
- Ask your tech lead for examples

**Stuck on implementation?**
- Check `.speckit/rules.md` for code standards
- Review similar implementations in codebase
- Use `@implement` prompt for guidance

---

## 🔄 Workflow Summary

```
Clarify (Requirements) 
    ↓
Specify (Write Spec)
    ↓
Review (Quality Gate 1)
    ↓
Plan (Create Tasks)
    ↓
Review (Quality Gate 2)
    ↓
Implement (Write Code)
    ↓
Test (Quality Gate 3)
    ↓
Deploy (Monitoring & Alerts)
    ↓
Done ✅
```

---

**Last Updated**: 2026-07-13
**Version**: 1.0
