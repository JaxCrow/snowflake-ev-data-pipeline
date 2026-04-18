-- ============================================================
-- Silver Layer: Schema, Table, and Transformation Procedure
-- ============================================================

-- 1. Create the SILVER schema
CREATE SCHEMA IF NOT EXISTS EV_PROJECT_DB.SILVER;

-- 2. Create the CLEAN_EV_DATA table
CREATE OR REPLACE TABLE EV_PROJECT_DB.SILVER.CLEAN_EV_DATA (
  VIN              VARCHAR,
  MAKE             VARCHAR,
  MODEL            VARCHAR,
  MODEL_YEAR       INT,
  ELECTRIC_RANGE   INT,
  BASE_MSRP        FLOAT,
  LOAD_TIMESTAMP   TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 3. Stored Procedure: Transform Bronze → Silver using Snowpark DataFrame API
CREATE OR REPLACE PROCEDURE EV_PROJECT_DB.SILVER.SP_TRANSFORM_BRONZE_TO_SILVER()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
def main(session):
    from snowflake.snowpark.functions import col, current_timestamp
    
    # 1. Lectura de la tabla Bronze
    df_raw = session.table("EV_PROJECT_DB.BRONZE.RAW_EV_DATA")
    
    # 2. Transformación: Extracción de datos del JSON + Metadata de Snowflake
    df_clean = df_raw.select(
        # Datos de Negocio
        col("JSON_DATA")["VIN"].as_("VIN"),
        col("JSON_DATA")["County"].as_("COUNTY"),
        col("JSON_DATA")["City"].as_("CITY"),
        col("JSON_DATA")["Postal Code"].as_("POSTAL_CODE"),
        col("JSON_DATA")["Model Year"].as_("MODEL_YEAR").cast("int"),
        col("JSON_DATA")["Make"].as_("MAKE"),
        col("JSON_DATA")["Model"].as_("MODEL"),
        col("JSON_DATA")["Electric Vehicle Type"].as_("EV_TYPE"),
        col("JSON_DATA")["Clean Alternative Fuel Vehicle (CAFV) Eligibility"].as_("CAFV_ELIGIBILITY"),
        col("JSON_DATA")["Electric Range"].as_("ELECTRIC_RANGE").cast("float"),
        col("JSON_DATA")["Base MSRP"].as_("BASE_MSRP").cast("float"),
        col("JSON_DATA")["Legislative District"].as_("LEGISLATIVE_DISTRICT"),
        col("JSON_DATA")["Electric Utility"].as_("ELECTRIC_UTILITY"),
        
        # Metadata para Auditoría y Linaje
        # Nota: Asegúrate de que tu tabla Bronze tenga estas columnas de metadata cargadas
        col("SOURCE_FILE").as_("SOURCE_FILE"), 
        col("SOURCE_FILE_ROW").as_("SOURCE_FILE_ROW"),
        current_timestamp().as_("LOAD_TIMESTAMP")
    ).filter(col("VIN").is_not_null())

    # 3. Persistencia (Append para mantener historial de ingestas)
    df_clean.write.mode("append").save_as_table("EV_PROJECT_DB.SILVER.CLEAN_EV_DATA")
    
    return f"SUCCESS: {df_clean.count()} rows processed with metadata."
$$;
