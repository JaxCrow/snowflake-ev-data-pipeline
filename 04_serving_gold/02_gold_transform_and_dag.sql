-- ============================================================
-- Gold Layer: Stored Procedures and DAG Child Task
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- 1. Metadata logging procedure
CREATE OR REPLACE PROCEDURE EV_PROJECT_DB.GOLD.SP_LOG_METADATA(
  FILE_NAME STRING,
  LAYER STRING,
  START_TIME TIMESTAMP_LTZ,
  END_TIME TIMESTAMP_LTZ,
  ROWS_PROC INT,
  STATUS STRING,
  ERROR_MSG STRING
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
def main(session, file_name, layer, start_time, end_time, rows_proc, status, error_msg):
    try:
        session.sql(f"""
            INSERT INTO EV_PROJECT_DB.GOLD.PIPELINE_AUDIT
              (FILE_NAME, LAYER, START_TIME, END_TIME, ROWS_PROCESSED, STATUS, ERROR_MESSAGE, QUERY_ID)
            SELECT
              '{file_name}',
              '{layer}',
              '{start_time}'::TIMESTAMP_LTZ,
              '{end_time}'::TIMESTAMP_LTZ,
              {rows_proc},
              '{status}',
              '{error_msg.replace("'", "''")}',
              LAST_QUERY_ID()
        """).collect()
        return "Metadata logged successfully."
    except Exception as e:
        return f"Logging failed: {str(e)}"
$$;

-- 2. Silver → Gold transformation procedure

CREATE OR REPLACE PROCEDURE EV_PROJECT_DB.GOLD.SP_TRANSFORM_SILVER_TO_GOLD()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
def main(session):
    from snowflake.snowpark.functions import col, count, avg, max as max_, current_timestamp
    from datetime import datetime, timezone

    # Captura de tiempo inicial para auditoría
    start_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    try:
        # 1. Lectura de la capa Silver (que ya incluye metadatos de archivo)
        df_silver = session.table("EV_PROJECT_DB.SILVER.CLEAN_EV_DATA")

        # 2. Agregaciones estratégicas (KPIs solicitados en el proyecto)
        df_gold = (
            df_silver
            .group_by(col("MAKE"), col("EV_TYPE"))
            .agg(
                count(col("VIN")).alias("TOTAL_VEHICLES"),
                avg(col("ELECTRIC_RANGE")).alias("AVG_RANGE"),
                max_(col("BASE_MSRP")).alias("MAX_MSRP")
            )
            .with_column("LOAD_TIMESTAMP", current_timestamp())
        )

        # 3. Conteo de filas para el log de auditoría
        row_count = df_gold.count()

        # 4. Refresco de la tabla Iceberg (Idempotencia)
        session.sql("TRUNCATE TABLE EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS").collect()
        df_gold.write.mode("append").save_as_table("EV_PROJECT_DB.GOLD.FACT_EV_MARKET_METRICS")

        end_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

        # 5. Registro de éxito en la tabla de Observabilidad
        session.call(
            "EV_PROJECT_DB.GOLD.SP_LOG_METADATA",
            "silver_to_gold_aggregation", # Nombre del proceso
            "GOLD",                       # Capa destino
            start_time,
            end_time,
            row_count,
            "SUCCESS",
            ""
        )

        return f"SUCCESS: {row_count} aggregated rows pushed to Iceberg table."

    except Exception as e:
        end_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        
        # Registro de falla en la tabla de Observabilidad
        session.call(
            "EV_PROJECT_DB.GOLD.SP_LOG_METADATA",
            "silver_to_gold_aggregation",
            "GOLD",
            start_time,
            end_time,
            0,
            "FAILURE",
            str(e)
        )
        return f"FAILURE: {str(e)}"
$$;

-- 3. Child task: runs AFTER the silver transform completes
CREATE OR REPLACE TASK EV_PROJECT_DB.BRONZE.TSK_SUMMARIZE_GOLD_DATA
  WAREHOUSE = COMPUTE_WH
  AFTER EV_PROJECT_DB.BRONZE.TSK_TRANSFORM_SILVER_DATA
AS
  CALL EV_PROJECT_DB.GOLD.SP_TRANSFORM_SILVER_TO_GOLD();

-- 4. DAG management: safely attach the new task
--    Execute these in order:

-- Step A: Suspend all child tasks bottom-up, then suspend root
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_SUMMARIZE_GOLD_DATA   SUSPEND;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_TRANSFORM_SILVER_DATA SUSPEND;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA        SUSPEND;

-- Step B: Resume all child tasks top-down (leaves first, then root last)
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_SUMMARIZE_GOLD_DATA   RESUME;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_TRANSFORM_SILVER_DATA RESUME;
ALTER TASK EV_PROJECT_DB.BRONZE.TSK_INGEST_EV_DATA        RESUME;