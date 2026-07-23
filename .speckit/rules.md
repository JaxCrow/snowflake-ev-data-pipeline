# SpecKit Rules & Guidelines

## Quality Gate Rules

### Specification Quality Gate
A spec is ready for planning if it meets ALL of these criteria:

✅ **Required Fields Completed**:
- [ ] Title & description are clear and specific
- [ ] Acceptance criteria are testable and measurable
- [ ] Cost impact is analyzed
- [ ] Data quality considerations documented
- [ ] Scalability notes provided

✅ **Principle Alignment**:
- [ ] Addresses cost optimization (justifies any costs)
- [ ] Includes data quality strategy
- [ ] Design is scalable
- [ ] Compliance & audit considerations noted
- [ ] Reproducible and deterministic
- [ ] Observable & monitorable

✅ **Completeness**:
- [ ] No critical unknowns remain
- [ ] Dependencies identified
- [ ] Risks assessed & mitigated
- [ ] Success metrics defined

### Plan Quality Gate
A plan is ready for implementation if:

✅ **Traceability**:
- [ ] Every acceptance criterion mapped to tasks
- [ ] Every task has clear definition of done
- [ ] Dependencies between tasks are explicit

✅ **Completeness**:
- [ ] No missing work identified
- [ ] Effort estimates provided
- [ ] Resource requirements clear
- [ ] Test strategy defined

### Implementation Review Gate
Code is ready for merge if:

✅ **Code Quality**:
- [ ] SQL is efficient and well-commented
- [ ] Follows project style guide
- [ ] No security vulnerabilities
- [ ] Proper error handling

✅ **Testing**:
- [ ] All tests pass
- [ ] Test coverage meets minimum (80%)
- [ ] Data quality checks validated
- [ ] Integration tested

✅ **Documentation**:
- [ ] Code comments explain business logic
- [ ] dbt YAML documented (if applicable)
- [ ] Runbook updated
- [ ] Team trained if applicable

---

## Specification Writing Guidelines

### 1. Be Specific
- ❌ "Improve performance" → ✅ "Reduce Silver layer latency from 5min to 1min"
- ❌ "Add validation" → ✅ "Add row-count reconciliation between Bronze and Silver"

### 2. Quantify When Possible
- Always include numbers: row counts, latency targets, cost impact
- Use the `[Estimate X]` pattern when exact values unknown at spec time

### 3. Align with Constitution
Every spec must address ALL 7 principles:
1. **Cost** - Justify new costs, show savings where applicable
2. **Quality** - Define quality checks for new data
3. **Scale** - Address expected growth & bottlenecks
4. **Audit** - Explain lineage & compliance
5. **Reproduce** - Ensure deterministic, versioned design
6. **Observe** - Define monitoring & alerts
7. **Document** - Include data dictionary, dbt YAML, runbooks

### 4. Three-Layer Thinking
Design every transformation with Bronze/Silver/Gold in mind:
- **Bronze**: Raw data acceptance + error handling
- **Silver**: Validation + cleansing + freshness
- **Gold**: Business logic + consumption optimization

### 5. Cost Awareness
Always include:
- Compute cost (warehouse size × runtime)
- Storage impact (GB added, retention needed)
- Data transfer (inter-cloud, region)
- Total monthly estimate

### 6. Quality First
Every new dataset must have:
- Schema validation
- Freshness monitoring  
- Completeness threshold (e.g., 99%)
- Accuracy validation method
- Unique key definition

---

## Code & Implementation Standards

### SQL Standards
```sql
-- Use consistent naming
-- Bronze tables: RAW_[SOURCE]_[OBJECT]
-- Silver tables: STG_[DOMAIN]_[OBJECT]
-- Gold tables: FACT_[METRIC] or DIM_[ENTITY]

-- Always include business logic comments
-- Explain the "why", not just the "what"

-- Use streams & tasks for orchestration, not scheduled tasks
-- Event-driven when possible

-- Include error handling
-- Quarantine bad records, don't drop silently
```

### Snowpark Python Standards
```python
# Include docstrings
# Explain parameters and return values
# Log transformations for observability
# Handle edge cases explicitly
```

### dbt Standards
```yaml
# Documented sources and exposures
sources:
  - name: [source_name]
    tables:
      - name: [table_name]
        description: [Clear description]
        columns:
          - name: [column]
            description: [What it is]
            tests:
              - unique
              - not_null
```

### Testing Standards
- Minimum 80% code coverage
- Test happy path + edge cases
- Include data quality tests
- Document test assumptions

---

## Workflow Checklist

## Interaction Protocol

This project uses a strict guided-confirmation workflow for all SpecKit and implementation stages.

### Mandatory collaboration behavior

- After each meaningful stage or execution step, explain what was produced, changed, or validated before proposing the next step.
- Ask confirmation questions one at a time.
- Do not advance to the next major stage until the current stage outcome has been explained and user confirmation has been obtained.
- Do not rely on a single generic confirmation such as "is this okay?". Questions must be specific to the result that was just produced.
- Questions should verify correctness, scope alignment, tradeoff acceptance, or expected behavior, not only superficial satisfaction.
- If a stage executes validations, summarize what each validation checked and why it matters before asking for confirmation.
- If ambiguity remains, continue clarification one question at a time instead of batching multiple unresolved decisions together.

### Mandatory stage checkpoints

- `speckit.specify`: explain scope, constraints, assumptions, and closed decisions captured in the spec; then ask for focused confirmation.
- `speckit.plan`: explain architecture, phases, artifacts, technical decisions, and validation flow; then ask for focused confirmation.
- `speckit.tasks`: explain task grouping, dependencies, priority order, and testing/validation coverage; then ask for focused confirmation.
- `speckit.implement`: explain what changed, how it was validated, what remains open, and any risks; then ask for focused confirmation.

### Strictness policy

- Treat this protocol as mandatory unless the user explicitly overrides it.
- Prefer under-advancing over over-advancing: stop and confirm rather than assuming approval.

### For Specs
- [ ] Use provided templates
- [ ] Address all 7 principles
- [ ] Include cost & quality analysis
- [ ] Identify dependencies & risks
- [ ] Define success metrics
- [ ] Get specification quality gate sign-off

### For Plans
- [ ] Break spec into discrete tasks
- [ ] Map tasks to acceptance criteria
- [ ] Estimate effort for each task
- [ ] Identify dependencies
- [ ] Get plan quality gate sign-off

### For Implementation
- [ ] Follow code standards
- [ ] Include comprehensive tests
- [ ] Update documentation
- [ ] Validate data quality
- [ ] Get implementation review sign-off

### For Deployment
- [ ] Runbook created/updated
- [ ] Monitoring configured
- [ ] Alerts tested
- [ ] Team trained
- [ ] Rollback plan documented
- [ ] Post-deployment validation done

---

## Tools & References

**Specification Templates**: `.speckit/templates/`
- `feature-spec.md` - For new features/changes
- `pipeline-spec.md` - For new data pipelines
- `transformation-spec.md` - For transformations
- `bug-report.md` - For bug fixes

**Project Constitution**: `.github/constitution.md`
- Core principles & non-negotiables
- Review before every spec

**Local Prompts**: `.github/prompts/`
- Use with Copilot Chat for structured guidance
- `specify.prompt.md` - Write better specs
- `plan.prompt.md` - Create implementation plans
- `implement.prompt.md` - Follow implementation workflow

---

## FAQ

**Q: When do I use the Feature Spec vs Pipeline Spec vs Transformation Spec?**
A:
- **Feature Spec**: New analytics feature, new capability in Streamlit app
- **Pipeline Spec**: New ingestion pipeline, new stage in medallion
- **Transformation Spec**: Individual SQL transformation, dbt model, Snowpark SP

**Q: Can I skip the cost analysis?**
A: No. Every spec must include cost impact. Even "zero cost" needs to be justified.

**Q: What if I don't know the exact numbers?**
A: Use estimates with `[Estimate X]` notation. Specifying "unknown" is NOT acceptable.

**Q: How detailed should my spec be?**
A: Detailed enough that another engineer could implement from it with 10% clarifying questions.

**Q: Who approves specs?**
A: Follow your team's review process. Typically: author → peer review → tech lead → merge.
