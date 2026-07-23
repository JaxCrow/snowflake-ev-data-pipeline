# SpecKit Startup Prompt

Resume this session using as the primary source:
00_documentation/speckit-continuity-context.md

Mandatory instructions:
1. Read first the sections "Session Update 2026-07-22 (Handoff Baseline)" and "Next Conversation Start Point (Do This First)".
2. Confirm in your first response that you loaded that continuity.
3. Do not reopen closed decisions:
   - core/reference/consumption architecture
   - AI read-only and consumption-only
   - external CDC with Airbyte OSS in Docker (without External Access Integration in Snowflake trial)
4. Maintain strict protocol:
   - one confirmation question at a time
   - do not execute commands/changes without explicit approval
5. Immediate objective:
   prepare the Product-ready implementation package for external CDC (Airbyte OSS -> Snowflake landing/reference -> SCD2/effective-date), including:
   - operational design
   - step-by-step runbook
   - validations
   - failure handling and rollback
   - evidence checklist

Start with:
- a brief summary of the current state (3-6 bullets),
- and a single question to confirm whether we start with the Airbyte OSS runtime design.
