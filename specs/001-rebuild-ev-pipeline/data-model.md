# Data Model: Rebuild Snowflake EV Pipeline

Date: 2026-07-15
Spec: specs/001-rebuild-ev-pipeline/spec.md

## Entities

### 1. EV Registration Record

- Description: Source registration event ingested from external source files.
- Core attributes:
  - source_file
  - source_row_id
  - registration_timestamp
  - vehicle_identifier
  - location attributes
  - raw payload reference
- Lifecycle:
  - Ingested (Bronze)
  - Standardized (Silver)
  - Aggregated/curated (Gold)

### 2. Catalogue Vehicle Record (CDC)

- Description: External vehicle reference maintained in NeonDB and synchronized via CDC.
- Core attributes:
  - vehicle_id
  - make
  - model
  - model_year
  - category/subcategory
  - change_timestamp
- Lifecycle:
  - Source change in NeonDB
  - CDC capture and sync to Snowflake
  - Available for enrichment joins

### 3. Curated Metric

- Description: Business-facing aggregate derived from transformed and enriched data.
- Core attributes:
  - metric_name
  - metric_value
  - grain (time/location/category)
  - calculation_timestamp
  - upstream lineage pointers
- Lifecycle:
  - Calculated in Gold/dbt
  - Validated by DQ/tests
  - Exposed to sharing/analytics consumers

### 4. Data Quality Result

- Description: Validation outcome for a DQ rule execution.
- Core attributes:
  - check_name
  - check_scope
  - status (pass/fail)
  - failure_count
  - execution_timestamp
  - alert_triggered flag
- Lifecycle:
  - Produced during DQ stage
  - Stored/queried for monitoring
  - Used in completion gate

### 5. Analytics Query Session

- Description: Analyst interaction mapped to validated metric outputs.
- Core attributes:
  - query_text
  - resolved metric references
  - response_payload
  - validation_status against expected values
  - execution_timestamp

## Relationships

- EV Registration Record (many) -> Curated Metric (many-to-aggregated)
- Catalogue Vehicle Record (one/many by vehicle_id) -> EV Registration Record (many)
- Curated Metric (many) -> Analytics Query Session (many)
- Data Quality Result (many) validates EV Registration Record, Catalogue Vehicle Record, and Curated Metric outputs.

## Validation Rules

- Registration records must be parseable and mapped to required business fields for Silver.
- CDC synchronized catalogue records must preserve key identity uniqueness.
- Curated metric calculations must align with validated aggregation logic and expected totals.
- DQ outcomes must be observable and retained for completion sign-off.
- Analytics responses used for sign-off must match expected curated metric values.

## Lineage Boundaries

- Source lineage starts at Azure Blob and NeonDB.
- Transformation lineage spans Bronze -> Silver -> Gold -> dbt/analytics outputs.
- Consumption lineage includes Iceberg, Sharing, and Streamlit analyst interface.
