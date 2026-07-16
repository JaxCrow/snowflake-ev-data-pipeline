# Transformation Specification Template

**Transformation Name**: [Name of the transformation]

**Author**: [Your name]

**Date**: [YYYY-MM-DD]

**Type**: [SQL | Snowpark Python | dbt | Stored Procedure]

---

## 1. Business Context

[Why is this transformation needed? What business problem does it solve?]

---

## 2. Source & Target

**Source Tables**:
| Table | Layer | Rows | Columns | Update Frequency |
|-------|-------|------|---------|-----------------|
| [Table] | [Layer] | [Est.] | [Count] | [Frequency] |

**Target Table**:
- Name: [Name]
- Layer: [Layer]
- Expected rows: [Count]
- Update frequency: [Frequency]

---

## 3. Transformation Logic

**Business Rules**:
- Rule 1: [Description with logic]
- Rule 2: [Description with logic]
- Rule 3: [Description with logic]

**Aggregations** (if applicable):
- Aggregation 1: [Description]
- Aggregation 2: [Description]

**Filtering/Exclusions**:
- Filter 1: [Condition]
- Filter 2: [Condition]

---

## 4. Data Quality

**Input Validation**:
- [ ] Null checks: [Fields]
- [ ] Format validation: [Fields]
- [ ] Range validation: [Fields]

**Output Validation**:
- [ ] Complete rows: [Target %]
- [ ] Accurate calculations: [Validation method]
- [ ] Uniqueness: [Unique key]

**Data Lineage**:
```
[Source] → [Transformation] → [Target]
           ↓
        [Quality Checks]
           ↓
        [Monitoring]
```

---

## 5. Performance Considerations

**Expected Runtime**: [Minutes/hours]

**Parallelization Strategy**: [How will it scale?]

**Optimization Techniques**: [Indexes, clustering, etc.]

**Performance Testing**: [Baseline metrics]

---

## 6. Implementation Details

**Technology Stack**: [SQL | Snowpark | dbt]

**Key Algorithms**: [Any complex logic?]

**Error Handling**: [Error handling strategy]

**Idempotency**: [Is it safe to re-run?]

---

## 7. Testing Strategy

**Unit Tests**:
- [ ] Test 1: [Description]
- [ ] Test 2: [Description]

**Integration Tests**:
- [ ] Test 1: [Description]
- [ ] Test 2: [Description]

**Data Validation Tests**:
- [ ] Row count verification
- [ ] Sample record validation
- [ ] Aggregate verification

---

## 8. Code Artifacts

**SQL/Python File**: [Path to implementation]

**dbt Model** (if applicable): [Path to model]

**Test File** (if applicable): [Path to tests]

---

## 9. Deployment & Rollback

**Deployment Steps**:
1. Step 1
2. Step 2
3. Step 3

**Validation Post-Deployment**: [How to verify success]

**Rollback Procedure**: [How to revert if issues arise]

---

## 10. Monitoring & SLA

**Metrics to Track**:
- [ ] Row count delta
- [ ] Execution time
- [ ] Error rate
- [ ] Data freshness

**Alert Thresholds**:
| Metric | Warning | Critical |
|--------|---------|----------|
| [Metric] | [Value] | [Value] |

**SLA**: [Target execution time & availability]

---

## 11. Cost Impact

**Compute Cost**: [Estimated cost per run]

**Storage Impact**: [Estimated GB added]

**Data Transfer**: [Estimated GB]

**Monthly Cost**: [Total estimate]

---

## 12. Sign-Off

- [ ] Specification reviewed by data engineer
- [ ] Specification reviewed by data architect
- [ ] Cost impact approved
- [ ] SLA requirements confirmed
- [ ] Ready to implement

**Reviewers**:
- Engineer: ________________
- Architect: ________________
