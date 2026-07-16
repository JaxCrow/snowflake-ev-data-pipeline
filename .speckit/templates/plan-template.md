# Implementation Plan Template

**Plan Name**: [Name of the feature/pipeline being implemented]

**Author**: [Your name]

**Date**: [YYYY-MM-DD]

**Related Spec**: [Link to specification document]

---

## 1. Overview

[Brief summary of what will be implemented and why]

---

## 2. Acceptance Criteria Mapping

Link each acceptance criterion from the spec to implementation tasks:

| Acceptance Criterion | Implementation Tasks | Owner | Status |
|---------------------|---------------------|-------|--------|
| [AC 1] | Task 1, Task 2 | [Person] | TBD |
| [AC 2] | Task 3 | [Person] | TBD |

---

## 3. Task Breakdown

### Task 1: [Clear Task Title]
**Description**: [What needs to be done?]

**Dependencies**: [What must be done first?]

**Acceptance Criteria**: 
- [ ] Criteria 1
- [ ] Criteria 2

**Estimated Effort**: [X hours/days]

**Owner**: [Person]

**Status**: [ ] Not Started [ ] In Progress [ ] Complete

---

### Task 2: [Clear Task Title]
**Description**: [What needs to be done?]

**Dependencies**: [What must be done first?]

**Acceptance Criteria**: 
- [ ] Criteria 1
- [ ] Criteria 2

**Estimated Effort**: [X hours/days]

**Owner**: [Person]

**Status**: [ ] Not Started [ ] In Progress [ ] Complete

---

### Task N: [Final Task]
**Description**: [What needs to be done?]

**Dependencies**: [What must be done first?]

**Acceptance Criteria**: 
- [ ] Criteria 1
- [ ] Criteria 2

**Estimated Effort**: [X hours/days]

**Owner**: [Person]

**Status**: [ ] Not Started [ ] In Progress [ ] Complete

---

## 4. Dependency Graph

```
Task 1 ──┐
         ├──→ Task 3 ──→ Task 5
Task 2 ──┤
         └──→ Task 4

Task 6 (parallel, independent)
```

---

## 5. Effort Estimation

| Task | Hours | Days | Owner |
|------|-------|------|-------|
| Task 1 | 4 | 0.5 | [Person] |
| Task 2 | 8 | 1 | [Person] |
| Task 3 | 6 | 0.75 | [Person] |
| **Total** | **18** | **2.25** | - |

**Buffer**: +25% = ~23 hours total (3 days)

---

## 6. Testing Strategy

### Unit Tests
- [ ] Test 1: [Description]
- [ ] Test 2: [Description]

### Integration Tests
- [ ] Test 1: [Description]
- [ ] Test 2: [Description]

### Data Quality Tests
- [ ] Row count validation
- [ ] Accuracy verification
- [ ] Freshness validation

### Acceptance Testing
- [ ] All acceptance criteria verified
- [ ] Edge cases tested
- [ ] Performance validated

---

## 7. Implementation Sequence

1. **Phase 1: Foundation** [X days]
   - Task 1: [Description]
   - Task 2: [Description]
   - Validation checkpoint

2. **Phase 2: Core Implementation** [X days]
   - Task 3: [Description]
   - Task 4: [Description]
   - Testing checkpoint

3. **Phase 3: Integration & Optimization** [X days]
   - Task 5: [Description]
   - Task 6: [Description]
   - Final validation

---

## 8. Risk & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|-----------|
| [Risk 1] | High | Medium | [Mitigation plan] |
| [Risk 2] | Medium | Low | [Mitigation plan] |

---

## 9. Code Review Checklist

- [ ] Code follows style guide (`.speckit/rules.md`)
- [ ] Tests pass (≥80% coverage)
- [ ] No security vulnerabilities
- [ ] Documentation updated
- [ ] Performance acceptable
- [ ] Cost impact verified
- [ ] Data quality validated

---

## 10. Deployment Plan

### Pre-Deployment
- [ ] Code reviewed & approved
- [ ] All tests passing
- [ ] Runbook created/updated
- [ ] Monitoring configured
- [ ] Alerts tested
- [ ] Rollback procedure documented

### Deployment Steps
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Post-Deployment Validation
- [ ] Application starts successfully
- [ ] Data flows correctly
- [ ] Monitoring metrics normal
- [ ] No error alerts

### Rollback Plan
[Describe how to revert if issues occur]

---

## 11. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| [Metric 1] | [Value] | [How measured] |
| [Metric 2] | [Value] | [How measured] |

---

## 12. Sign-Off

- [ ] Plan created and documented
- [ ] Tasks estimated and assigned
- [ ] Dependencies identified
- [ ] Testing strategy defined
- [ ] Risk mitigation planned
- [ ] Ready to implement

**Approvals**:
- Tech Lead: _________________ Date: _______
- Product: _________________ Date: _______
