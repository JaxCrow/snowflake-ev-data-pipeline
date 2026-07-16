# Deployment Clarification Document

Date: 2026-07-15
Objective: Rebuild and deploy the full Snowflake EV data pipeline using official SpecKit workflow

## Clarification Decisions

| Decision | Selection |
|---|---|
| Target environment | Dev only |
| Setup style | Manual step-by-step setup |
| NeonDB CDC sync frequency | Every 12 hours |
| Deployment scope for first rebuild | Full end-to-end in one pass |
| Completion gate | End-to-end success: SQL stages + dbt + DQ + Streamlit answers expected metrics |

## Confirmed Context

- Snowflake account is available.
- NeonDB account is available, but PostgreSQL schema/data must be created during deployment.
- Azure setup starts from scratch.
- Budget priority is cost-optimized / free-tier aware.
- Timeline is urgent.

## Scope for Rebuild

Stage 0 to Stage 10 are in scope for the first pass:

0. NeonDB PostgreSQL schema + CDC readiness
1. Infrastructure
2. Bronze
3. Silver
4. Gold
4b. PostgreSQL CDC integration (mandatory)
5. Data quality
6. Iceberg
7. Sharing
8. Cost governance
9. Analyst Streamlit
10. dbt project validation

## Quality Gate for "Done"

Rebuild is complete in Dev only when all of the following are true:

- All required SQL stages execute successfully.
- CDC from NeonDB is operational on the selected schedule.
- dbt tests pass.
- Data quality checks run and alerts are validated.
- Streamlit chat returns expected metrics sourced from Gold/Iceberg.

## Next Step

Proceed to SpecKit Specify and Plan using this clarification baseline.
