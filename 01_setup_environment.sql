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
-- 5. Create Roles and Grant Permissions
-- ----------------------------------------------------------------------------

-- Note: Network policies and rules assumed to be configured at account level

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

-- Create role for clinical users (read-only inference)
CREATE ROLE IF NOT EXISTS CLINICAL_USER;

GRANT USAGE ON DATABASE PEDIATRIC_ML TO ROLE CLINICAL_USER;
GRANT USAGE ON SCHEMA PEDIATRIC_ML.CLINICAL_DATA TO ROLE CLINICAL_USER;
GRANT USAGE ON SCHEMA PEDIATRIC_ML.ML_RESULTS TO ROLE CLINICAL_USER;
GRANT USAGE ON WAREHOUSE ML_INFERENCE_WH TO ROLE CLINICAL_USER;

-- ----------------------------------------------------------------------------
-- 6. Enable Model Registry
-- ----------------------------------------------------------------------------

-- Model registry is automatically enabled in Business Critical edition
-- Verify with:
SHOW PARAMETERS LIKE 'ENABLE_MODEL_REGISTRY' IN ACCOUNT;

-- ----------------------------------------------------------------------------
-- 7. Set Up Resource Monitors (Optional but Recommended)
-- ----------------------------------------------------------------------------

CREATE RESOURCE MONITOR IF NOT EXISTS ML_MONTHLY_MONITOR
    WITH 
    CREDIT_QUOTA = 1000  -- Adjust based on budget
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS 
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- Apply to ML warehouses
ALTER WAREHOUSE ML_IMPORT_WH SET RESOURCE_MONITOR = ML_MONTHLY_MONITOR;
ALTER WAREHOUSE ML_INFERENCE_WH SET RESOURCE_MONITOR = ML_MONTHLY_MONITOR;

-- ----------------------------------------------------------------------------
-- 9. Create Helper Functions
-- ----------------------------------------------------------------------------

-- Cosine similarity function for embeddings
CREATE OR REPLACE FUNCTION COSINE_SIMILARITY(vec1 ARRAY, vec2 ARRAY)
RETURNS FLOAT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
HANDLER = 'cosine_similarity'
AS
$$
import numpy as np

def cosine_similarity(vec1, vec2):
    """Calculate cosine similarity between two vectors"""
    if not vec1 or not vec2:
        return 0.0
    
    v1 = np.array(vec1)
    v2 = np.array(vec2)
    
    # Handle zero vectors
    norm1 = np.linalg.norm(v1)
    norm2 = np.linalg.norm(v2)
    
    if norm1 == 0 or norm2 == 0:
        return 0.0
    
    return float(np.dot(v1, v2) / (norm1 * norm2))
$$;

-- Euclidean distance function
CREATE OR REPLACE FUNCTION EUCLIDEAN_DISTANCE(vec1 ARRAY, vec2 ARRAY)
RETURNS FLOAT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
HANDLER = 'euclidean_distance'
AS
$$
import numpy as np

def euclidean_distance(vec1, vec2):
    """Calculate Euclidean distance between two vectors"""
    if not vec1 or not vec2:
        return float('inf')
    
    v1 = np.array(vec1)
    v2 = np.array(vec2)
    
    return float(np.linalg.norm(v1 - v2))
$$;

-- ----------------------------------------------------------------------------
-- 10. Create Audit Tables
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
SHOW STAGES IN SCHEMA PEDIATRIC_ML.MODELS;

-- Test helper functions
SELECT COSINE_SIMILARITY([1,2,3], [1,2,3]) AS perfect_match;  -- Should return 1.0
SELECT COSINE_SIMILARITY([1,0,0], [0,1,0]) AS orthogonal;     -- Should return 0.0
SELECT EUCLIDEAN_DISTANCE([0,0,0], [3,4,0]) AS distance_5;    -- Should return 5.0

-- Display summary
SELECT 'Environment setup complete!' AS STATUS,
       'Database: PEDIATRIC_ML' AS DATABASE_INFO,
       'Schemas: MODELS, CLINICAL_DATA, ML_RESULTS' AS SCHEMA_INFO,
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

