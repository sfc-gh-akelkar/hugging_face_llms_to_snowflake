-- ============================================================================
-- Snowflake Environment Setup for HuggingFace Models
-- ============================================================================
-- Purpose: Create database, schemas, warehouses, and stages for model import
-- Requires: ACCOUNTADMIN role or equivalent privileges
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ----------------------------------------------------------------------------
-- 1. Create Database and Schemas
-- ----------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS PEDIATRIC_ML
    COMMENT = 'Database for pediatric hospital ML models and clinical data';

USE DATABASE PEDIATRIC_ML;

CREATE SCHEMA IF NOT EXISTS MODELS
    COMMENT = 'Schema for model registry and model artifacts';

CREATE SCHEMA IF NOT EXISTS CLINICAL_DATA
    COMMENT = 'Schema for clinical data (Clarity/Caboodle source)';

CREATE SCHEMA IF NOT EXISTS ML_RESULTS
    COMMENT = 'Schema for model inference results';

-- ----------------------------------------------------------------------------
-- 2. Create Warehouses
-- ----------------------------------------------------------------------------

-- Warehouse for model import and registration
CREATE WAREHOUSE IF NOT EXISTS ML_IMPORT_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for importing and registering models';

-- Warehouse for inference workloads
CREATE WAREHOUSE IF NOT EXISTS ML_INFERENCE_WH
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for running model inference';

-- Warehouse for data loading
CREATE WAREHOUSE IF NOT EXISTS DATA_LOAD_WH
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for loading clinical data';

-- ----------------------------------------------------------------------------
-- 3. Create Stages for Model Storage
-- ----------------------------------------------------------------------------

USE SCHEMA MODELS;

-- Internal stage for HuggingFace models
CREATE STAGE IF NOT EXISTS HF_MODEL_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for storing HuggingFace model files';

-- Stage for model inference packages
CREATE STAGE IF NOT EXISTS MODEL_CODE_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Python inference code and dependencies';
    
-- Note: Encryption is automatic in Snowflake (at rest and in transit)

-- ----------------------------------------------------------------------------
-- 4. Create File Formats
-- ----------------------------------------------------------------------------

CREATE FILE FORMAT IF NOT EXISTS CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null', '')
    EMPTY_FIELD_AS_NULL = TRUE
    COMPRESSION = 'AUTO';

CREATE FILE FORMAT IF NOT EXISTS JSON_FORMAT
    TYPE = 'JSON'
    COMPRESSION = 'AUTO'
    STRIP_OUTER_ARRAY = TRUE;

-- ----------------------------------------------------------------------------
-- 5. Create Compute Pools for Model Serving
-- ----------------------------------------------------------------------------

-- Compute pool for ML model inference (CPU-based for PoC)
CREATE COMPUTE POOL IF NOT EXISTS ML_INFERENCE_POOL
    MIN_NODES = 1
    MAX_NODES = 3
    INSTANCE_FAMILY = CPU_X64_XS  -- X-Small CPU instances for PoC
    AUTO_RESUME = TRUE
    AUTO_SUSPEND_SECS = 600  -- 10 minutes idle before suspend
    COMMENT = 'Compute pool for serving ML models (BioBERT, BiomedCLIP)';

-- ----------------------------------------------------------------------------
-- 6. Create Roles and Grant Permissions
-- ----------------------------------------------------------------------------

-- Note: Network policies and rules assumed to be configured at account level

-- Get current user to grant roles
SET CURRENT_USER_VAR = (SELECT CURRENT_USER());

-- Create role for ML engineers
CREATE ROLE IF NOT EXISTS ML_ENGINEER;

-- Grant database and schema access
GRANT USAGE ON DATABASE PEDIATRIC_ML TO ROLE ML_ENGINEER;
GRANT ALL ON SCHEMA PEDIATRIC_ML.MODELS TO ROLE ML_ENGINEER;
GRANT ALL ON SCHEMA PEDIATRIC_ML.CLINICAL_DATA TO ROLE ML_ENGINEER;
GRANT ALL ON SCHEMA PEDIATRIC_ML.ML_RESULTS TO ROLE ML_ENGINEER;

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE ML_IMPORT_WH TO ROLE ML_ENGINEER;
GRANT USAGE ON WAREHOUSE ML_INFERENCE_WH TO ROLE ML_ENGINEER;
GRANT USAGE ON WAREHOUSE DATA_LOAD_WH TO ROLE ML_ENGINEER;

-- Grant stage access
GRANT READ, WRITE ON STAGE PEDIATRIC_ML.MODELS.HF_MODEL_STAGE TO ROLE ML_ENGINEER;
GRANT READ, WRITE ON STAGE PEDIATRIC_ML.MODELS.MODEL_CODE_STAGE TO ROLE ML_ENGINEER;

-- Grant compute pool access for model deployment and inference
GRANT USAGE ON COMPUTE POOL ML_INFERENCE_POOL TO ROLE ML_ENGINEER;
GRANT MONITOR ON COMPUTE POOL ML_INFERENCE_POOL TO ROLE ML_ENGINEER;

-- Create role for clinical users (read-only inference)
CREATE ROLE IF NOT EXISTS CLINICAL_USER;

GRANT USAGE ON DATABASE PEDIATRIC_ML TO ROLE CLINICAL_USER;
GRANT USAGE ON SCHEMA PEDIATRIC_ML.CLINICAL_DATA TO ROLE CLINICAL_USER;
GRANT USAGE ON SCHEMA PEDIATRIC_ML.ML_RESULTS TO ROLE CLINICAL_USER;
GRANT USAGE ON WAREHOUSE ML_INFERENCE_WH TO ROLE CLINICAL_USER;

-- Grant compute pool usage for inference (read-only)
GRANT USAGE ON COMPUTE POOL ML_INFERENCE_POOL TO ROLE CLINICAL_USER;

-- Grant roles to current user so they can be used immediately
GRANT ROLE ML_ENGINEER TO USER IDENTIFIER($CURRENT_USER_VAR);
GRANT ROLE CLINICAL_USER TO USER IDENTIFIER($CURRENT_USER_VAR);

-- ----------------------------------------------------------------------------
-- 7. Create Audit Tables
-- ----------------------------------------------------------------------------

USE SCHEMA ML_RESULTS;

CREATE TABLE IF NOT EXISTS MODEL_INFERENCE_LOG (
    LOG_ID NUMBER AUTOINCREMENT,
    MODEL_NAME VARCHAR,
    INPUT_ID VARCHAR,
    INFERENCE_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EXECUTION_TIME_MS NUMBER,
    USER_NAME VARCHAR DEFAULT CURRENT_USER(),
    WAREHOUSE_USED VARCHAR,
    SUCCESS BOOLEAN,
    ERROR_MESSAGE VARCHAR,
    PRIMARY KEY (LOG_ID)
);

CREATE TABLE IF NOT EXISTS MODEL_PERFORMANCE_METRICS (
    METRIC_ID NUMBER AUTOINCREMENT,
    MODEL_NAME VARCHAR,
    METRIC_DATE DATE DEFAULT CURRENT_DATE(),
    TOTAL_INFERENCES NUMBER,
    AVG_EXECUTION_TIME_MS NUMBER,
    SUCCESS_RATE FLOAT,
    PRIMARY KEY (METRIC_ID)
);

-- ----------------------------------------------------------------------------
-- Verification
-- ----------------------------------------------------------------------------

-- Show created objects
SHOW DATABASES LIKE 'PEDIATRIC_ML';
SHOW SCHEMAS IN DATABASE PEDIATRIC_ML;
SHOW WAREHOUSES LIKE '%ML%';
SHOW COMPUTE POOLS LIKE 'ML_INFERENCE_POOL';
SHOW STAGES IN SCHEMA PEDIATRIC_ML.MODELS;

-- Display summary
SELECT 'Environment setup complete!' AS STATUS,
       'Database: PEDIATRIC_ML' AS DATABASE_INFO,
       'Schemas: MODELS, CLINICAL_DATA, ML_RESULTS' AS SCHEMA_INFO,
       'Compute Pool: ML_INFERENCE_POOL' AS COMPUTE_POOL_INFO,
       'Ready to import HuggingFace models' AS NEXT_STEP;

/*
============================================================================
SETUP COMPLETE
============================================================================

Next Steps:
1. Run 02_create_mock_data.sql to generate test data
2. Import models via Snowsight UI:
   - Follow instructions in 03_import_models_via_ui.md
3. Run use case examples:
   - 04_use_case_semantic_search.sql
   - 05_use_case_oncology_matching.sql
   - 06_use_case_entity_extraction.sql

For questions, see IMPORT_GUIDE.md
============================================================================
*/

