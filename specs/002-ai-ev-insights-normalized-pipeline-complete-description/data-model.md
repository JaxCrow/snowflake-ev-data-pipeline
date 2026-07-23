# Data Model: AI EV Insights Normalized Pipeline Complete Description

Date: 2026-07-21
Spec: specs/002-ai-ev-insights-normalized-pipeline-complete-description/spec.md

## Layered Model

- `core` (persistent, normalized, business entities)
- `reference` (persistent, historical external catalog from PostgreSQL CDC, SCD2)
- `consumption` (materialized denormalized `mv_` outputs only)

## Entities

### 1. Core EV Event

- Layer: `core`
- Description: Normalized representation of EV source records derived from JSON ingestion pipeline.
- Key attributes (representative):
  - event_id
  - event_timestamp
  - vehicle_key
  - location_key
  - source_file
  - load_timestamp
- Notes:
  - Stores normalized business state with historical preservation.
  - May include selected derived dimensions needed for stable reuse.

### 2. Core Vehicle Entity

- Layer: `core`
- Description: Normalized vehicle attributes linked to EV events.
- Key attributes (representative):
  - vehicle_key
  - vin_prefix
  - make
  - model
  - model_year
  - ev_type
  - range_value
  - msrp_base
- Notes:
  - Historical layer semantics per architecture decision.

### 3. Core Entity History Version

- Layer: `core`
- Description: Historical version record for core business entities retained for time-aware traceability.
- Key attributes:
  - entity_business_key
  - version_start_at
  - version_end_at
  - is_current
  - change_reason_or_source
- Notes:
  - Enables historical querying of core business state over time.

### 4. Reference Catalog Version (SCD2)

- Layer: `reference`
- Description: Historical catalog versions synchronized from PostgreSQL CDC.
- Key attributes:
  - catalog_key
  - external_source_id
  - business attributes (including pricing and category fields)
  - effective_start_at
  - effective_end_at
  - is_current
  - cdc_operation
  - cdc_synced_at
- Notes:
  - Full history retained.
  - Supports effective-dated joins to consumption derivations.

### 5. Consumption Materialized Model

- Layer: `consumption`
- Description: Denormalized output model, materialized with `mv_` prefix, built from `core` + `reference`.
- Key attributes (representative):
  - metric dimensions (make/model/type/region/time)
  - metric values
  - effective catalog attributes used at event date
  - freshness marker
  - quality marker
- Notes:
  - Only layer accessible to AI and downstream consumers.

### 6. AI Insight Response Envelope

- Layer: `consumption` interface
- Description: Contracted response content for AI outputs.
- Required fields:
  - answer
  - assumptions
  - freshness_status
  - quality_status
  - exclusions_or_filters
  - source_surface (consumption only)

## Relationships

- Core EV Event (many) -> Core Vehicle Entity (one)
- Core Vehicle Entity (one) -> Core Entity History Version (many)
- Core EV Event (many) -> Reference Catalog Version (one by effective-date match)
- Core + Reference (many-to-many derivation) -> Consumption Materialized Models (many)
- Consumption Materialized Models (many) -> AI Insight Response Envelope (many)

## Effective-Date Join Rule

For consumption derivations, reference values are selected by event date using SCD2 validity window:

- Event date must be `>= effective_start_at`
- Event date must be `< effective_end_at` (or open-ended current record)

This enforces historical correctness for pre-change vs post-change analytics.

## Validation Rules

- Core normalized keys must be non-null and unique at entity level.
- Core historical versions must not contain overlapping validity windows for the same business key.
- Reference SCD2 must not contain overlapping validity windows for the same business key.
- Consumption models must only reference approved `core` + `reference` sources.
- AI response envelope must always include freshness, quality, assumptions, and exclusions/filters.
- Consumption objects must use `mv_` naming convention.

## State and Refresh Semantics

- Ingestion: event-driven by Blob file landing.
- Reference sync: CDC-driven from PostgreSQL.
- Consumption refresh: automatic every 24 hours in demo mode.
- AI: read-only against consumption outputs.
