-- ============================================================================
-- Snowflake Intelligence Agent Setup with Cortex Search
-- ============================================================================
-- Purpose: Create a conversational AI agent that clinicians can query in natural language
-- Benefits: No SQL required, natural language interface, accessible via Snowsight
-- ============================================================================

USE ROLE ML_ENGINEER;
USE DATABASE PEDIATRIC_ML;
USE SCHEMA CLINICAL_DATA;

-- ----------------------------------------------------------------------------
-- Step 1: Create Cortex Analyst Semantic Model
-- ----------------------------------------------------------------------------

-- Define the semantic model that maps business concepts to database schema
CREATE OR REPLACE FILE FORMAT YAML_FORMAT
    TYPE = 'TEXT'
    COMPRESSION = 'NONE';

-- Create a stage for the semantic model file
CREATE OR REPLACE STAGE SEMANTIC_MODELS
    FILE_FORMAT = YAML_FORMAT
    COMMENT = 'Stage for Cortex Analyst semantic model definitions';

-- Upload semantic model (YAML file defining tables, columns, relationships)
-- This file will be created separately and uploaded via Snowsight or SnowSQL

-- ----------------------------------------------------------------------------
-- Step 2: Define Semantic Model (Save as semantic_model.yaml)
-- ----------------------------------------------------------------------------

/*
Save this content as semantic_model.yaml and upload to @SEMANTIC_MODELS stage:

name: pediatric_clinical_intelligence
description: Semantic model for pediatric clinical data analysis with Cortex Search
tables:
  - name: CLINICAL_NOTES
    description: Clinical notes from patient encounters
    base_table:
      database: PEDIATRIC_ML
      schema: CLINICAL_DATA
      table: CLINICAL_NOTES
    dimensions:
      - name: PATIENT_ID
        description: Unique patient identifier
        data_type: NUMBER
      - name: NOTE_TYPE
        description: Type of clinical note (Progress Note, H&P Note, etc.)
        data_type: VARCHAR
      - name: NOTE_DATE
        description: Date when note was created
        data_type: TIMESTAMP_NTZ
      - name: AUTHOR
        description: Clinician who authored the note
        data_type: VARCHAR
    measures:
      - name: note_count
        description: Count of clinical notes
        expr: COUNT(*)
    
  - name: PATIENTS
    description: Patient demographics
    base_table:
      database: PEDIATRIC_ML
      schema: CLINICAL_DATA
      table: PATIENTS
    dimensions:
      - name: PATIENT_ID
        description: Unique patient identifier
        data_type: NUMBER
      - name: MRN
        description: Medical Record Number
        data_type: VARCHAR
      - name: AGE_YEARS
        description: Patient age in years
        data_type: NUMBER
      - name: GENDER
        description: Patient gender
        data_type: VARCHAR
    
  - name: ENCOUNTERS
    description: Patient clinical encounters
    base_table:
      database: PEDIATRIC_ML
      schema: CLINICAL_DATA
      table: ENCOUNTERS
    dimensions:
      - name: ENCOUNTER_ID
        description: Unique encounter identifier
        data_type: NUMBER
      - name: PATIENT_ID
        description: Patient associated with encounter
        data_type: NUMBER
      - name: DEPARTMENT
        description: Department where encounter occurred
        data_type: VARCHAR
      - name: PRIMARY_DIAGNOSIS
        description: Primary diagnosis for encounter
        data_type: VARCHAR
      - name: ENCOUNTER_DATE
        description: Date of encounter
        data_type: DATE

relationships:
  - left_table: CLINICAL_NOTES
    right_table: PATIENTS
    join_type: inner
    join_condition: CLINICAL_NOTES.PATIENT_ID = PATIENTS.PATIENT_ID
  
  - left_table: CLINICAL_NOTES
    right_table: ENCOUNTERS
    join_type: inner
    join_condition: CLINICAL_NOTES.ENCOUNTER_ID = ENCOUNTERS.ENCOUNTER_ID

search_services:
  - name: CLINICAL_NOTES_SEARCH
    description: Semantic search across clinical notes
    base_table: CLINICAL_NOTES
    search_column: NOTE_TEXT
    filter_columns:
      - NOTE_TYPE
      - AUTHOR
      - PATIENT_ID
*/

-- ----------------------------------------------------------------------------
-- Step 3: Create Cortex Analyst Service
-- ----------------------------------------------------------------------------

-- Upload the semantic model YAML file to the stage first via Snowsight:
-- 1. Go to Data -> Databases -> PEDIATRIC_ML -> CLINICAL_DATA -> Stages
-- 2. Click on SEMANTIC_MODELS stage
-- 3. Click "Upload Files" and upload semantic_model.yaml

-- Verify the file is uploaded
LIST @SEMANTIC_MODELS;

-- ----------------------------------------------------------------------------
-- Step 4: Test Cortex Analyst with Natural Language Queries
-- ----------------------------------------------------------------------------

-- Example natural language queries that clinicians can ask:

-- Query 1: Find patients with specific symptoms
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3-70b',
    CONCAT(
        'You are a clinical AI assistant. Based on the following clinical notes, ',
        'find patients with fever and neutropenia: ',
        (SELECT LISTAGG(NOTE_TEXT, ' ') WITHIN GROUP (ORDER BY NOTE_DATE DESC)
         FROM CLINICAL_NOTES LIMIT 5)
    )
) AS ai_response;

-- Query 2: Use Cortex Search with natural language wrapper
CREATE OR REPLACE FUNCTION ASK_CLINICAL_QUESTION(question VARCHAR)
RETURNS TABLE (
    answer VARCHAR,
    relevant_notes ARRAY,
    patient_ids ARRAY
)
AS
$$
    WITH search_results AS (
        SELECT PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                'CLINICAL_NOTES_SEARCH',
                OBJECT_CONSTRUCT(
                    'query', question,
                    'columns', ARRAY_CONSTRUCT('NOTE_TEXT', 'PATIENT_ID', 'NOTE_DATE'),
                    'limit', 10
                )
            )
        )['results'] as results
    )
    SELECT 
        SNOWFLAKE.CORTEX.COMPLETE(
            'llama3-70b',
            CONCAT('Based on these clinical notes, answer: ', question, 
                   '\n\nRelevant notes: ', sr.results::VARCHAR)
        ) AS answer,
        ARRAY_AGG(sr.results) AS relevant_notes,
        ARRAY_AGG(DISTINCT sr.results['PATIENT_ID']) AS patient_ids
    FROM search_results sr
$$;

-- Test the natural language interface
SELECT * FROM TABLE(
    ASK_CLINICAL_QUESTION('What are common side effects seen in leukemia patients on chemotherapy?')
);

-- ----------------------------------------------------------------------------
-- Step 5: Create User-Friendly Views for Snowflake Intelligence
-- ----------------------------------------------------------------------------

-- View 1: Recent Oncology Cases
CREATE OR REPLACE VIEW V_RECENT_ONCOLOGY_CASES AS
SELECT 
    p.MRN,
    p.AGE_YEARS,
    p.GENDER,
    e.PRIMARY_DIAGNOSIS,
    e.ENCOUNTER_DATE,
    cn.NOTE_TYPE,
    SUBSTR(cn.NOTE_TEXT, 1, 500) AS note_preview,
    cn.AUTHOR
FROM CLINICAL_NOTES cn
JOIN PATIENTS p ON cn.PATIENT_ID = p.PATIENT_ID
JOIN ENCOUNTERS e ON cn.ENCOUNTER_ID = e.ENCOUNTER_ID
WHERE e.DEPARTMENT = 'Pediatric Oncology'
    AND cn.NOTE_DATE >= DATEADD(DAY, -30, CURRENT_DATE())
ORDER BY cn.NOTE_DATE DESC;

-- View 2: Patient Search Summary (for agent context)
CREATE OR REPLACE VIEW V_PATIENT_SEARCH_SUMMARY AS
SELECT 
    COUNT(DISTINCT p.PATIENT_ID) AS total_patients,
    COUNT(DISTINCT e.ENCOUNTER_ID) AS total_encounters,
    COUNT(DISTINCT cn.NOTE_ID) AS total_notes,
    COUNT(DISTINCT e.DEPARTMENT) AS departments,
    MAX(cn.NOTE_DATE) AS latest_note_date
FROM PATIENTS p
LEFT JOIN ENCOUNTERS e ON p.PATIENT_ID = e.PATIENT_ID
LEFT JOIN CLINICAL_NOTES cn ON e.ENCOUNTER_ID = cn.ENCOUNTER_ID;

-- ----------------------------------------------------------------------------
-- Step 6: Grant Access for Snowflake Intelligence Agent
-- ----------------------------------------------------------------------------

-- Grant necessary permissions to CLINICAL_USER role
GRANT SELECT ON VIEW V_RECENT_ONCOLOGY_CASES TO ROLE CLINICAL_USER;
GRANT SELECT ON VIEW V_PATIENT_SEARCH_SUMMARY TO ROLE CLINICAL_USER;
GRANT SELECT ON VIEW CLINICAL_NOTES_SEARCH TO ROLE CLINICAL_USER;

-- Grant Cortex functions access
GRANT USAGE ON FUNCTION SNOWFLAKE.CORTEX.SEARCH_PREVIEW TO ROLE CLINICAL_USER;
GRANT USAGE ON FUNCTION SNOWFLAKE.CORTEX.COMPLETE TO ROLE CLINICAL_USER;

/*
============================================================================
SNOWFLAKE INTELLIGENCE AGENT - USER GUIDE
============================================================================

## For Clinicians (Non-Technical Users):

### Option 1: Snowsight UI Chat Interface
1. Open Snowsight (https://app.snowflake.com)
2. Navigate to "AI & ML" -> "Cortex Analyst"
3. Select the semantic model: "pediatric_clinical_intelligence"
4. Ask questions in natural language:
   - "Show me all leukemia patients from the past month"
   - "Find cases similar to patient MRN12345678"
   - "What are common chemotherapy side effects?"
   - "How many oncology patients had fever and neutropenia?"

### Option 2: Custom Application Integration
Integrate Cortex Search into your EMR/clinical app:
- Use Snowflake's REST API to call SEARCH_PREVIEW
- Display results in a user-friendly interface
- No SQL knowledge required for end users

### Option 3: BI Tool Integration (Tableau, Power BI)
- Connect BI tool to views (V_RECENT_ONCOLOGY_CASES)
- Use natural language query features
- Build interactive dashboards with search

## Example Natural Language Queries:

1. "Find all patients with acute lymphoblastic leukemia who received vincristine"
2. "Show me patients with fever and low white blood cell count in the past week"
3. "Compare treatment outcomes for patients with similar diagnoses"
4. "What medications are commonly prescribed for nausea in oncology patients?"
5. "Find cases similar to this clinical presentation: [paste note text]"

## Benefits Over Direct SQL:
- ✅ No SQL knowledge required
- ✅ Natural language interface
- ✅ Contextual understanding
- ✅ Faster queries for non-technical staff
- ✅ Built-in PHI security (data stays in Snowflake)

## Next Steps:
1. Create semantic model YAML file
2. Upload to @SEMANTIC_MODELS stage
3. Configure Cortex Analyst in Snowsight
4. Train clinical staff on natural language queries
5. Monitor usage and refine semantic model

============================================================================
*/

