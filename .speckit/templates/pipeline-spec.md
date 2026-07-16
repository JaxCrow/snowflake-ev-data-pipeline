# Data Pipeline Specification Template

**Pipeline Name**: [Name of the pipeline]

**Author**: [Your name]

**Date**: [YYYY-MM-DD]

**Layer**: [Bronze | Silver | Gold | External]

---

## 1. Pipeline Overview

[Brief description of what this pipeline does]

---

## 2. Source Systems

| Source | Type | Frequency | Volume | Format |
|--------|------|-----------|--------|--------|
| [Source 1] | [Type] | [Frequency] | [Est. rows/GB] | [Format] |

---

## 3. Target Systems

| Target | Type | Update Frequency | Access Pattern |
|--------|------|------------------|-----------------|
| [Target 1] | [Type] | [Frequency] | [Usage] |

---

## 4. Data Transformation Logic

**Input Schema**:
```sql
-- Define input schema
```

**Output Schema**:
```sql
-- Define output schema
```

**Transformation Rules**:
- Rule 1: [Description]
- Rule 2: [Description]

---

## 5. Medallion Layer Details

**Bronze**: [Raw data handling]
- Ingestion method: [Method]
- Error handling: [Strategy]

**Silver**: [Data validation & cleansing]
- Validation checks: [List checks]
- Dynamic Table lag: [Target lag]

**Gold**: [Business logic]
- Aggregations: [List aggregations]
- Fact/Dimension tables: [List tables]

---

## 6. Data Quality Framework

**Quality Checks**:
- [ ] Schema validation
- [ ] Completeness: [%]
- [ ] Freshness: [Max age]
- [ ] Accuracy: [Reconciliation method]
- [ ] Uniqueness: [Unique key]

**Quarantine Process**: [How are bad records handled?]

**Monitoring Views**: [List monitoring queries]

---

## 7. SLA & Performance

**Latency SLA**: [Max time from source to availability]

**Availability**: [Uptime target]

**RTO**: [Recovery Time Objective]

**RPO**: [Recovery Point Objective]

---

## 8. Cost Estimate

**Compute**: [Warehouse size & runtime estimate]

**Storage**: [Estimated GB]

**Data Transfer**: [Estimated GB]

**Monthly Cost**: [Total estimate]

---

## 9. Orchestration & Tasks

**Task Name**: [Task name]
- Trigger: [Trigger condition]
- Schedule: [Schedule or event-based]
- Dependencies: [Upstream tasks]
- Retry Policy: [Retry strategy]

---

## 10. Monitoring & Alerts

**Metrics to Monitor**:
- [ ] Row counts
- [ ] Freshness
- [ ] Error rates
- [ ] Cost drift

**Alert Rules**:
| Condition | Threshold | Action |
|-----------|-----------|--------|
| [Condition] | [Threshold] | [Action] |

---

## 11. Documentation & Lineage

**dbt Model**: [Link to dbt model if applicable]

**Data Dictionary**: [Link to documentation]

**Lineage**: [Source → Bronze → Silver → Gold]

---

## 12. Implementation Checklist

- [ ] Source connectivity validated
- [ ] Schema defined and documented
- [ ] Quality checks implemented
- [ ] Monitoring configured
- [ ] SLA requirements verified
- [ ] Cost estimate reviewed
- [ ] Runbooks created
- [ ] Team trained
