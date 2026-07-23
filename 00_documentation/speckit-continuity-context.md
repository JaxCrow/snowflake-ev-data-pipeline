# SpecKit Continuity Context

## Purpose

This document captures the decisions already closed for the redesign of the Snowflake EV data pipeline so a future conversation can continue from the same agreed baseline without reopening prior choices.

## Project Goal

Build a demo-first EV insights platform on Snowflake that demonstrates:
- normalized data management
- CDC-driven external catalog synchronization from PostgreSQL
- materialized consumption for AI and downstream users
- sharing and export capabilities
- open formats such as Iceberg
- a controlled separation between demo behavior and product behavior

The primary AI experience must deliver insights from prepared consumption data, not from raw operational layers.

## SpecKit Direction

The project will be managed in SpecKit as a brand-new feature rather than reusing the previous feature artifact.

### Chosen feature identity

`ai-ev-insights-normalized-pipeline-complete-description`

### Why this choice

- It makes the new architecture explicit in the feature name.
- It avoids confusion with the previous medallion-oriented version of the project.
- It creates a clean source of truth for the redesigned scope.
- It supports a future conversation by giving a single feature name to reference.

## Architecture Principles

### 1. The documentation will use `core`, `reference`, and `consumption` instead of Bronze/Silver/Gold

#### Why

- The previous layer names were too tied to the old implementation pattern.
- The redesign is now centered on purpose-driven layers rather than legacy medallion labels.
- The new naming better reflects how data is actually used.

### 2. `core` is the normalized business layer

#### Definition

- `core` contains normalized base entities.
- `core` can also include some derived business dimensions when they add real analytical value.
- `core` keeps historical changes for those entities.
- `core` is persistent.

#### Why

- A pure base-only core would be too raw and would force repeated reconstruction in every consumption model.
- Allowing a small number of derived business dimensions makes the core more useful without turning it into a consumption layer.
- Preserving history in `core` keeps the main business domain traceable over time.
- This complements, rather than replaces, the separate historical behavior of `reference`.
- This keeps the architecture practical while supporting strict auditability and time-aware analysis.

### 3. `reference` is the CDC-driven historical catalog layer

#### Definition

- `reference` is a separate persistent layer for external catalog data.
- It is built from PostgreSQL CDC.
- It uses SCD Type 2 history.
- It keeps the full history indefinitely.
- It is separated from `core` on purpose.

#### Why

- The project must demonstrate how changes in PostgreSQL affect downstream consumption.
- Keeping the external catalog separate makes that change visible and explicit.
- SCD Type 2 is the right model because it preserves versioned history and supports effective-dated consumption.
- The full history is useful for traceability, debugging, and demonstration of change propagation.
- Keeping `reference` separate from `core` makes the historical evolution of the external catalog clearer.

### 4. `consumption` is the only output layer for AI and consumers

#### Definition

- `consumption` contains only materialized views.
- Those views are precomputed for consumption.
- The AI agent reads only from `consumption`.
- No direct querying of persistent layers is allowed for the agent in the demo design.
- `consumption` is the final surface for business users, sharing, and export.

#### Why

- This minimizes query re-execution cost.
- It keeps the AI layer simple and deterministic.
- It creates a single governed surface for answers.
- It avoids leaking implementation complexity into the AI experience.
- It makes the demo easier to explain and defend.

### 5. Materialized views in `consumption` refresh automatically every 24 hours in demo

#### Definition

- The demo will use automatic refresh with a fixed 24-hour cadence.
- The refresh is part of the demonstration of platform capability.
- The design may still allow manual refresh or other operational patterns in product mode, but the demo baseline is automatic every 24 hours.

#### Why

- It demonstrates that the system can keep consumption current without manual rework.
- It keeps the demo realistic without being too aggressive on cost.
- It provides a clear refresh boundary for explaining data freshness.

### 6. The AI agent is read-only

#### Definition

- The agent only queries prepared consumption data.
- The agent provides comprehensive explainability on freshness, quality, assumptions, and applied filters/exclusions.
- The agent cannot write back or reprocess data directly.
- The agent can mention the layer source used for a response.

#### Why

- Read-only behavior is safer and simpler for the first version.
- It keeps the AI aligned with governed, precomputed outputs.
- It avoids unwanted pipeline side effects.
- It still allows useful explanation and traceability.

### 7. The AI agent can explain data quality and freshness

#### Definition

- The agent must always include freshness and quality context.
- It must mention filters or exclusions if they affect the answer.
- It may provide a short explanation of the layer used.
- It should give full traceability and assumptions in the response style.

#### Why

- This improves trust in the answer.
- It makes the demo more defensible.
- It helps users understand where the data came from and what affected the output.

## Demo vs Product

### 1. The documentation must describe both modes explicitly

#### Definition

- Demo and product are distinct flows.
- The documentation must make the difference between both modes explicit.
- The demo flow is the primary focus.
- Product behavior is documented as the broader operational extension.

#### Why

- The user wants a very strict and explicit documentation style.
- Mixing demo and product into one vague flow would reduce clarity.
- Distinguishing the two prevents confusion later.

### 2. Blob ingestion is event-driven in product and demonstrable in demo

#### Definition

- In product mode, ingestion is triggered whenever a file lands in Blob Storage.
- In demo mode, the same event-driven mechanism is the main story.
- The demo can still document the pattern clearly even if the sample run is only a single load.

#### Why

- This shows the real operational behavior the system is designed for.
- It demonstrates the correct architectural pattern instead of a one-off manual load.
- It makes the product story credible.

### 3. Bronze is kept only as a minimal operational layer

#### Definition

- Bronze is not removed entirely.
- Bronze is kept at a minimal operational level.
- It exists for traceability, landing control, and controlled operational buffering.
- Historical raw storage does not need to live forever in Bronze.

#### Why

- Bronze is still useful for controlled landing and operational replay.
- Keeping it minimal avoids an ever-growing operational cost.
- The design stays closer to a clean architecture instead of an endless raw archive.

### 4. Historical raw data can live in Iceberg

#### Definition

- Blob Storage remains the physical raw landing source.
- Iceberg can be used for historical raw data storage if needed.
- This is useful for analytics and open-format access.
- Iceberg is not treated as a replacement for the raw source itself.

#### Why

- It preserves the historical analytical benefit of open table formats.
- It demonstrates portability and SQL-accessible historical storage.
- It avoids making Bronze the permanent archive.
- It aligns with the demo goal of showing multiple platform capabilities.

### 5. Sharing and export are mandatory demo capabilities

#### Definition

- Sharing and export stay in scope.
- They are part of what the demo must demonstrate.
- They are not treated as optional side features.

#### Why

- The user explicitly wants the demo to show the platform’s broad capabilities.
- Removing them would weaken the value of the demo.

### 6. Iceberg is mandatory in the demo

#### Definition

- Iceberg remains part of the demo.
- It is not a secondary or documentation-only feature.
- It demonstrates open-format capability.

#### Why

- The user wants to show storage, transformation, sharing, and export capabilities.
- Iceberg is one of the clearest ways to prove open-format support.

## Catalog and CDC Design

### 1. NeonDB remains a separate external reference source

#### Definition

- The PostgreSQL catalog is kept outside the main normalized core.
- It is deliberately external, even if that is not the most optimal production architecture.
- It exists to demonstrate external catalog control and Snowflake CDC.

#### Why

- The goal is to demonstrate how Snowflake handles catalog changes coming from an external database.
- The external catalog makes CDC behavior visible in the demo.
- A more optimal production layout is not the priority for this exercise.

### 2. The reference catalog is a CDC-updated table with history

#### Definition

- The external catalog is maintained as a table that stays updated through CDC.
- It is used as the source of truth for denormalization into consumption.
- It keeps history through SCD Type 2.
- Its changes should affect downstream data after the effective change date.
- CDC extraction and delivery into Snowflake are executed by an external engine (Airbyte OSS in Docker as the baseline).

#### Why

- This allows the demo to show that if a catalog value changes, downstream consumption changes appropriately after the effective date.
- The user explicitly wants that behavior to be visible.
- SCD Type 2 is the correct pattern for effective-dated history.

### 3. The effect of catalog changes is by effective event date

#### Definition

- Consumption should reflect the catalog version effective at the relevant event date.
- The historical catalog is not just a latest-value overwrite table.
- The join logic must respect effective dating.

#### Why

- This ensures the consumption result is historically correct.
- It allows the demo to show how a price or attribute change in PostgreSQL affects later data.
- It is the right model for time-aware analysis.

### 4. `reference` keeps full history indefinitely

#### Definition

- The historical external catalog is retained indefinitely.
- Purging can be introduced later if operational needs change.

#### Why

- The user wants maximum traceability now.
- Keeping all history makes the CDC story stronger.
- It leaves room for future adjustment without changing the current decision.

### 5. `core` retains historical change tracking

#### Definition

- `core` preserves historical changes for normalized business entities.
- `reference` separately preserves historical changes for external catalog entities.
- `core` history and `reference` history are both persistent and queryable for their respective domains.

#### Why

- The redesign explicitly requires historical behavior in `core` as well as `reference`.
- This supports traceability from source-derived business records and avoids losing historical context in the main modeled domain.
- The separation remains strong because `core` and `reference` still represent different histories from different sources.

### 6. `reference` is separate from `core`

#### Definition

- `core` and `reference` are physically and conceptually separate.
- `reference` does not get collapsed into `core`.
- Downstream denormalization happens from both layers.

#### Why

- The separation helps show the impact of PostgreSQL catalog changes clearly.
- It makes the historical reference behavior easier to explain.
- It reinforces the demo story of external CDC-driven catalog updates.

### 7. CDC transport is external to Snowflake runtime

#### Definition

- Snowflake trial limitations prevent using External Access Integration for direct runtime calls from Snowflake to NeonDB.
- The project uses an external CDC engine to transport changes from NeonDB to Snowflake staging/reference.
- Airbyte OSS (Docker) is the default transport choice for the project baseline.

#### Why

- It keeps the architecture compliant with current account constraints.
- It preserves Free-First principles using open-source tooling.
- It maintains deterministic, auditable CDC runs with clear ownership boundaries.

## Consumption Behavior

### 1. `consumption` is built only from `core` + `reference`

#### Definition

- The consumption layer is derived from the normalized core and the historical reference layer.
- The AI agent does not query `core` or `reference` directly.
- `consumption` is the only stable output surface for queries.

#### Why

- It enforces one governed answer surface.
- It avoids direct access to persistent implementation layers.
- It matches the user’s preference for precomputed consumption.

### 2. Consumption is precomputed and materialized

#### Definition

- Consumption tables are materialized views.
- The output is already denormalized for read performance.
- No repeated ad hoc recomputation should be required for every AI query.

#### Why

- It minimizes cost.
- It improves query performance.
- It keeps the demo responsive and predictable.

### 3. Consumption refresh cadence is 24 hours in demo

#### Definition

- Materialized consumption refreshes automatically every 24 hours.
- This is the demo baseline.

#### Why

- It balances freshness with simplicity.
- It demonstrates automatic refresh capability.
- It keeps the design easy to explain.

## Data Quality

### 1. Data quality is mandatory

#### Definition

- Data quality is required in core and in consumption.
- It is not a secondary nice-to-have.
- It is part of the design contract.

#### Why

- The user wants the output to be trustworthy.
- Data quality must be visible and not hidden.
- This supports the AI use case and the overall credibility of the demo.

### 2. The agent must always explain freshness and quality

#### Definition

- Responses must always show freshness status, quality status, assumptions, and any exclusions/filters that affected the answer.
- Explainability must be complete and consistent for all validation responses.

#### Why

- It gives the user confidence in the result.
- It makes the system’s behavior more transparent.

## Layer Naming and Replacement

### 1. Bronze/Silver/Gold are replaced in the documentation

#### Definition

- The documentation should no longer frame the architecture as Bronze/Silver/Gold.
- The formal naming should be `core`, `reference`, and `consumption`.
- If any old names remain in implementation, they are only internal legacy references and not the documented architectural model.

#### Why

- The user explicitly asked to replace the old names in the documentation.
- The new architecture is better described by purpose than by medallion labels.
- This keeps the new design aligned to the actual behavior.

## Explicit Decisions Closed

The following choices are now closed for the redesign:

- New SpecKit feature instead of reusing the old one.
- Long explicit feature name.
- Demo and product documented separately.
- `core` / `reference` / `consumption` replace Bronze / Silver / Gold in the documentation.
- `core` is normalized, persistent, and historical.
- `core` can include some derived business dimensions.
- `reference` is a separate historical CDC layer for PostgreSQL catalog data.
- `reference` uses SCD Type 2 and keeps full history indefinitely.
- `consumption` is the only output surface.
- `consumption` is built from `core` + `reference`.
- `consumption` is made of materialized views.
- The AI agent only reads from `consumption`.
- The AI agent is read-only.
- The AI agent explains freshness, quality, filters, and lineage context.
- The AI agent may explain the source layer used.
- NeonDB stays as a separate external reference source to demonstrate CDC.
- CDC transport from NeonDB into Snowflake is externalized via Airbyte OSS (Docker baseline).
- PostgreSQL catalog changes affect downstream results by effective date.
- Iceberg remains part of the demo.
- Sharing and export remain mandatory demo capabilities.
- Ingestion remains event-driven from Blob Storage.
- Bronze remains minimal and operational.
- Historical raw can be placed in Iceberg.
- Every major SpecKit and implementation stage must be explained before advancing.
- Confirmation must happen one question at a time.
- Confirmation questions must validate the actual result, not just ask for generic approval.

## Collaboration Protocol

The working protocol for future sessions is strict and persistent.

### Rules

- After each major stage, explain what was produced, what was validated, and why it matters.
- Ask only one confirmation question at a time.
- Do not proceed to the next major stage without explicit confirmation from the user.
- Confirmation questions must be specific to the artifact or validation result that was just produced.
- If additional clarification is needed, continue with one focused question at a time until the result is unambiguous.

## SpecKit Hook Policy

The project enforces mandatory extension hooks for every major SpecKit phase.

### Required execution behavior

- Hooks configured in `.specify/extensions.yml` are mandatory and must execute before/after each phase where defined.
- `speckit.specify` requires pre-clarification and post-checklist hooks.
- `speckit.plan` requires pre-clarification and post-checklist hooks.
- `speckit.tasks` requires pre-clarification and post-analysis hooks.
- `speckit.implement` requires pre-analysis and post-convergence hooks.
- A phase is not considered closed until all mandatory hooks for that phase complete.

### Why this policy was chosen

- Ensures quality gates are enforced consistently instead of manually remembered.
- Reduces artifact drift between spec, plan, tasks, and implementation.
- Guarantees explicit validation checkpoints before and after each major phase.

### Why this protocol was chosen

- The user wants strong control over each step of the process.
- Generic approval questions are not sufficient to verify that the actual outcome matches intent.
- Step-by-step confirmation reduces rework and prevents silent drift.
- This protocol is especially important for SpecKit because each phase feeds the next one.

## Why this architecture was chosen overall

This architecture was selected because it is the cleanest way to satisfy all of the user’s goals at the same time:

- It keeps the demo understandable.
- It shows an explicit external CDC story.
- It demonstrates historical catalog changes affecting business outputs.
- It minimizes query cost by using precomputed materialized consumption.
- It keeps the AI layer governed and read-only.
- It preserves important platform features such as Iceberg, sharing, and export.
- It gives a single source of truth for future SpecKit work.

## How to use this document later

When starting a new conversation, this file should be treated as the continuity baseline.

Suggested order of use:
1. Read this document first.
2. Use it to feed `speckit.specify`.
3. Then derive `speckit.plan`.
4. Then derive `speckit.tasks`.

## Notes for the future

If any decision must change later, update this document first so the new baseline is explicit before continuing with implementation work.

## Session Update 2026-07-22 (Handoff Baseline)

This section is the continuity handoff for starting a new conversation without losing the current architecture direction.

### Official CDC execution path (current baseline)

- CDC source remains NeonDB PostgreSQL.
- CDC transport is externalized using Airbyte OSS in Docker as the baseline runtime.
- Snowflake receives landed CDC deltas and applies SCD2/effective-date behavior in project SQL.
- Direct Snowflake runtime external calls to NeonDB are not part of the baseline due to trial-account limitations.

### Why this update was made

- Snowflake trial accounts do not support External Access Integration required for direct runtime external connectivity.
- External CDC transport preserves the same architecture intent (reference history + effective-date consumption) while remaining constitution-compliant.
- Free-First remains respected because Airbyte OSS is open source and does not require managed replication licensing.

### Documentation status after this update

- README now states external CDC engine path explicitly.
- Feature 002 spec/plan/research/contracts/quickstart/tasks are aligned to external CDC transport.
- Deployment and pipeline documentation reflect Airbyte OSS baseline and trial-compatible constraints.

### Non-negotiable continuity for next conversation

- Do not reopen architecture naming (`core`/`reference`/`consumption`).
- Do not revert to direct Snowflake runtime external access path while trial constraints remain.
- Keep AI read-only and consumption-only.
- Keep one-question-at-a-time confirmation protocol and mandatory SpecKit hook policy.

## Next Conversation Start Point (Do This First)

When a new conversation starts, the assistant must resume from this exact point:

- Architecture is already decided and documented.
- Spec/plan/tasks for feature `002-ai-ev-insights-normalized-pipeline-complete-description` already exist.
- Current next objective is to prepare the Product-ready implementation package for external CDC runtime (Airbyte OSS in Docker) without reopening closed decisions.

### First response behavior required

- Start by confirming continuity has been loaded from this file.
- Ask one focused confirmation question only:
	- whether to begin with implementation documentation/package design for Airbyte OSS external CDC runtime.
- Do not execute infrastructure/runtime changes automatically.

### Immediate work package to produce in next session

Produce and/or refine a complete implementation package for:

1. Airbyte OSS Docker runtime setup for NeonDB -> Snowflake CDC landing.
2. Snowflake reference landing + SCD2 merge operational model.
3. Runbook with step-by-step operations, validation checks, failure handling, and rollback.
4. Evidence checklist for cadence, lineage, SCD2 integrity, and effective-date propagation.

### Guardrails for the next session

- No secrets in repo files or chat outputs.
- No command/script execution without explicit user approval.
- One question at a time for clarifications/approvals.
- If constraints change (account type, budget, tooling), update this continuity file before changing architecture artifacts.

### Suggested execution order in the next session

1. Validate that feature `002` artifacts remain the active source of truth.
2. Draft Airbyte runtime topology and operation flow (source, destination, cadence, retries).
3. Map CDC payload to Snowflake landing/reference objects and SCD2 merge contract.
4. Define monitoring and alerting expectations for CDC transport and merge outcomes.
5. Present checkpoint summary and ask explicit approval before implementation actions.
