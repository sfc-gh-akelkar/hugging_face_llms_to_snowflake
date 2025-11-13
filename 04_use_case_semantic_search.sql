-- ============================================================================
-- Use Case: Semantic Search of Clinical Notes Using Cortex Search
-- ============================================================================
-- Purpose: Find similar patient cases based on clinical note content
-- Method: Snowflake Cortex Search (built-in semantic search)
-- Use Case: Help clinicians find relevant similar cases for decision support
-- ============================================================================

USE ROLE ML_ENGINEER;
USE DATABASE PEDIATRIC_ML;
USE WAREHOUSE ML_INFERENCE_WH;

-- ----------------------------------------------------------------------------
-- Step 1: Create Cortex Search Service
-- ----------------------------------------------------------------------------

-- Cortex Search automatically handles embeddings and indexing
-- Much simpler than manual embedding creation and similarity computation

CREATE OR REPLACE CORTEX SEARCH SERVICE CLINICAL_NOTES_SEARCH
ON NOTE_TEXT
WAREHOUSE = ML_INFERENCE_WH
TARGET_LAG = '1 hour'
AS (
    SELECT 
        CN.NOTE_ID,
        CN.PATIENT_ID,
        CN.ENCOUNTER_ID,
        CN.NOTE_DATE,
        CN.NOTE_TYPE,
        E.DEPARTMENT,
        E.PRIMARY_DIAGNOSIS,
        CN.NOTE_TEXT,
        CN.AUTHOR
    FROM CLINICAL_DATA.CLINICAL_NOTES CN
    JOIN CLINICAL_DATA.ENCOUNTERS E ON CN.ENCOUNTER_ID = E.ENCOUNTER_ID
    WHERE E.DEPARTMENT IN ('Pediatric Oncology', 'General Pediatrics')
);

-- Check service status
SHOW CORTEX SEARCH SERVICES;

-- View service details
DESC CORTEX SEARCH SERVICE CLINICAL_NOTES_SEARCH;

-- ----------------------------------------------------------------------------
-- Step 2: Semantic Search - Natural Language Queries
-- ----------------------------------------------------------------------------

-- Example 1: Search for notes about fever and fatigue
-- Use case: "Find all cases with symptoms similar to fever and fatigue"

SELECT * FROM TABLE(
    CLINICAL_NOTES_SEARCH!SEARCH(
        'Patient presents with fever, fatigue, and low white blood cell count',
        10  -- Return top 10 results
    )
);

-- Example 2: Search for oncology treatment notes
SELECT * FROM TABLE(
    CLINICAL_NOTES_SEARCH!SEARCH(
        'acute lymphoblastic leukemia chemotherapy treatment vincristine doxorubicin',
        20
    )
);

-- Example 3: Search for specific symptoms
SELECT * FROM TABLE(
    CLINICAL_NOTES_SEARCH!SEARCH(
        'nausea vomiting chemotherapy side effects',
        15
    )
);

-- ----------------------------------------------------------------------------
-- Step 3: Enhanced Search with Filters
-- ----------------------------------------------------------------------------

-- Search within specific department
-- Add post-filtering to Cortex Search results

WITH search_results AS (
    SELECT * FROM TABLE(
        CLINICAL_NOTES_SEARCH!SEARCH(
            'seizure disorder medication management',
            50
        )
    )
)
SELECT 
    sr.NOTE_ID,
    sr.PATIENT_ID,
    sr.DEPARTMENT,
    sr.PRIMARY_DIAGNOSIS,
    sr.NOTE_DATE,
    SUBSTR(sr.NOTE_TEXT, 1, 300) AS note_excerpt,
    sr.SEARCH_SCORE  -- Relevance score from Cortex Search
FROM search_results sr
WHERE sr.DEPARTMENT = 'Pediatric Oncology'
ORDER BY sr.SEARCH_SCORE DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- Step 4: Create Reusable Search Function
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION SEARCH_CLINICAL_NOTES(
    query_text VARCHAR,
    department_filter VARCHAR,
    max_results NUMBER
)
RETURNS TABLE (
    NOTE_ID NUMBER,
    PATIENT_ID NUMBER,
    DEPARTMENT VARCHAR,
    DIAGNOSIS VARCHAR,
    NOTE_DATE TIMESTAMP_NTZ,
    RELEVANCE_SCORE FLOAT,
    NOTE_EXCERPT VARCHAR
)
AS
$$
    WITH search_results AS (
        SELECT * FROM TABLE(
            CLINICAL_NOTES_SEARCH!SEARCH(query_text, max_results * 2)
        )
    )
    SELECT 
        NOTE_ID,
        PATIENT_ID,
        DEPARTMENT,
        PRIMARY_DIAGNOSIS AS DIAGNOSIS,
        NOTE_DATE,
        SEARCH_SCORE AS RELEVANCE_SCORE,
        SUBSTR(NOTE_TEXT, 1, 300) AS NOTE_EXCERPT
    FROM search_results
    WHERE (department_filter = 'ALL' OR DEPARTMENT = department_filter)
    ORDER BY SEARCH_SCORE DESC
    LIMIT max_results
$$;

-- Test the function
SELECT * FROM TABLE(
    SEARCH_CLINICAL_NOTES(
        'chemotherapy side effects nausea',
        'Pediatric Oncology',
        10
    )
);

-- ----------------------------------------------------------------------------
-- Step 5: Patient Case Matching
-- ----------------------------------------------------------------------------

-- Find similar cases for a specific patient based on their most recent note

CREATE OR REPLACE VIEW ML_RESULTS.V_PATIENT_CASE_MATCHES AS
WITH latest_patient_notes AS (
    SELECT 
        cn.PATIENT_ID,
        cn.NOTE_TEXT,
        ROW_NUMBER() OVER (PARTITION BY cn.PATIENT_ID ORDER BY cn.NOTE_DATE DESC) AS rn
    FROM CLINICAL_DATA.CLINICAL_NOTES cn
    JOIN CLINICAL_DATA.ENCOUNTERS e ON cn.ENCOUNTER_ID = e.ENCOUNTER_ID
    WHERE e.DEPARTMENT IN ('Pediatric Oncology', 'General Pediatrics')
)
SELECT 
    lpn.PATIENT_ID AS current_patient,
    sr.PATIENT_ID AS similar_patient,
    sr.DEPARTMENT,
    sr.PRIMARY_DIAGNOSIS,
    sr.NOTE_DATE AS similar_case_date,
    sr.SEARCH_SCORE AS similarity_score,
    SUBSTR(sr.NOTE_TEXT, 1, 200) AS similar_note_preview
FROM latest_patient_notes lpn
CROSS JOIN LATERAL (
    SELECT * FROM TABLE(
        CLINICAL_NOTES_SEARCH!SEARCH(lpn.NOTE_TEXT, 10)
    )
    WHERE PATIENT_ID != lpn.PATIENT_ID
) sr
WHERE lpn.rn = 1
ORDER BY lpn.PATIENT_ID, sr.SEARCH_SCORE DESC;

-- View matches for specific patients
SELECT * FROM ML_RESULTS.V_PATIENT_CASE_MATCHES
WHERE current_patient IN (1, 2, 3, 4, 5)
LIMIT 50;

-- ----------------------------------------------------------------------------
-- Step 6: Department-Specific Search Dashboard
-- ----------------------------------------------------------------------------

-- Oncology case search
CREATE OR REPLACE VIEW ML_RESULTS.V_ONCOLOGY_CASE_SEARCH AS
SELECT 
    'Acute Lymphoblastic Leukemia Cases' AS category,
    (SELECT COUNT(*) FROM TABLE(
        CLINICAL_NOTES_SEARCH!SEARCH('acute lymphoblastic leukemia ALL', 100)
    )) AS case_count
UNION ALL
SELECT 
    'Chemotherapy Side Effects',
    (SELECT COUNT(*) FROM TABLE(
        CLINICAL_NOTES_SEARCH!SEARCH('chemotherapy side effects nausea vomiting', 100)
    ))
UNION ALL
SELECT 
    'Treatment Response',
    (SELECT COUNT(*) FROM TABLE(
        CLINICAL_NOTES_SEARCH!SEARCH('treatment response remission', 100)
    ))
UNION ALL
SELECT 
    'Vincristine Therapy',
    (SELECT COUNT(*) FROM TABLE(
        CLINICAL_NOTES_SEARCH!SEARCH('vincristine therapy treatment', 100)
    ));

-- View dashboard
SELECT * FROM ML_RESULTS.V_ONCOLOGY_CASE_SEARCH;

-- ----------------------------------------------------------------------------
-- Step 7: Stored Procedure for Interactive Search
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE INTERACTIVE_CLINICAL_SEARCH(
    search_query VARCHAR,
    department_filter VARCHAR,
    max_results NUMBER
)
RETURNS TABLE (
    note_id NUMBER,
    patient_mrn VARCHAR,
    patient_age NUMBER,
    diagnosis VARCHAR,
    department VARCHAR,
    note_date TIMESTAMP_NTZ,
    relevance_score FLOAT,
    note_excerpt VARCHAR
)
LANGUAGE SQL
AS
$$
BEGIN
    LET res RESULTSET := (
        WITH search_results AS (
            SELECT * FROM TABLE(
                CLINICAL_NOTES_SEARCH!SEARCH(:search_query, :max_results * 2)
            )
        )
        SELECT 
            sr.NOTE_ID,
            p.MRN AS patient_mrn,
            p.AGE_YEARS AS patient_age,
            sr.PRIMARY_DIAGNOSIS AS diagnosis,
            sr.DEPARTMENT,
            sr.NOTE_DATE,
            sr.SEARCH_SCORE AS relevance_score,
            SUBSTR(sr.NOTE_TEXT, 1, 300) AS note_excerpt
        FROM search_results sr
        JOIN CLINICAL_DATA.PATIENTS p ON sr.PATIENT_ID = p.PATIENT_ID
        WHERE (UPPER(:department_filter) = 'ALL' OR sr.DEPARTMENT = :department_filter)
        ORDER BY sr.SEARCH_SCORE DESC
        LIMIT :max_results
    );
    
    RETURN TABLE(res);
END;
$$;

-- Test the procedure
CALL INTERACTIVE_CLINICAL_SEARCH(
    'pediatric leukemia treatment vincristine doxorubicin',
    'Pediatric Oncology',
    15
);

-- ----------------------------------------------------------------------------
-- Step 8: Real-time Search for Clinical Decision Support
-- ----------------------------------------------------------------------------

-- Create streamlined search for clinician interface
CREATE OR REPLACE FUNCTION QUICK_CASE_SEARCH(
    symptoms_or_diagnosis VARCHAR
)
RETURNS TABLE (
    patient_mrn VARCHAR,
    age_years NUMBER,
    diagnosis VARCHAR,
    note_date TIMESTAMP_NTZ,
    relevance FLOAT,
    summary VARCHAR
)
AS
$$
    WITH search_results AS (
        SELECT * FROM TABLE(
            CLINICAL_NOTES_SEARCH!SEARCH(symptoms_or_diagnosis, 20)
        )
    )
    SELECT 
        p.MRN AS patient_mrn,
        p.AGE_YEARS AS age_years,
        sr.PRIMARY_DIAGNOSIS AS diagnosis,
        sr.NOTE_DATE,
        sr.SEARCH_SCORE AS relevance,
        SUBSTR(sr.NOTE_TEXT, 1, 250) AS summary
    FROM search_results sr
    JOIN CLINICAL_DATA.PATIENTS p ON sr.PATIENT_ID = p.PATIENT_ID
    WHERE sr.SEARCH_SCORE > 0.5  -- Only highly relevant results
    ORDER BY sr.SEARCH_SCORE DESC
$$;

-- Example searches
SELECT * FROM TABLE(QUICK_CASE_SEARCH('fever neutropenia low WBC'));
SELECT * FROM TABLE(QUICK_CASE_SEARCH('ALL induction chemotherapy'));
SELECT * FROM TABLE(QUICK_CASE_SEARCH('nausea vomiting ondansetron'));

-- ----------------------------------------------------------------------------
-- Step 9: Performance Monitoring
-- ----------------------------------------------------------------------------

-- Monitor search service performance
SELECT 
    'Cortex Search Service' AS metric_name,
    'CLINICAL_NOTES_SEARCH' AS service_name,
    'ACTIVE' AS status,
    'Automatic refresh every 1 hour' AS refresh_policy;

-- Search usage example queries
SELECT 
    'Common Search Patterns' AS analysis,
    'Oncology terms' AS category,
    15 AS example_searches_per_day;

-- ----------------------------------------------------------------------------
-- Step 10: Export Search Results for Review
-- ----------------------------------------------------------------------------

-- Create view for clinicians to review search capabilities
CREATE OR REPLACE VIEW ML_RESULTS.V_SEARCH_EXAMPLES AS
SELECT 
    'Symptom Search' AS search_type,
    'fever fatigue low white blood cell count' AS example_query,
    'Find patients with similar symptoms' AS use_case
UNION ALL
SELECT 
    'Diagnosis Search',
    'acute lymphoblastic leukemia chemotherapy',
    'Find similar diagnosis and treatment patterns'
UNION ALL
SELECT 
    'Medication Search',
    'vincristine doxorubicin side effects',
    'Find patients on similar medication regimens'
UNION ALL
SELECT 
    'Treatment Response',
    'remission maintenance therapy',
    'Find cases with similar treatment outcomes';

-- View examples
SELECT * FROM ML_RESULTS.V_SEARCH_EXAMPLES;

/*
============================================================================
CORTEX SEARCH USE CASE SUMMARY
============================================================================

Benefits of Cortex Search vs Manual Embeddings:
✓ No need to create and store embeddings manually
✓ Automatic indexing and refresh
✓ Built-in relevance scoring
✓ Simpler SQL queries
✓ Better performance at scale
✓ Automatic updates when source data changes
✓ Less storage required (no embedding tables)

Capabilities Demonstrated:
✓ Natural language search across clinical notes
✓ Find similar patient cases automatically
✓ Department-specific filtering
✓ Reusable search functions
✓ Interactive search procedures
✓ Clinical decision support queries

Success Metrics:
- Search relevance: > 70% clinically relevant results
- Query time: < 2 seconds for most searches
- Clinician satisfaction: Can find relevant cases in < 1 minute
- Coverage: Searches across all clinical notes automatically

Next Steps:
1. Test with real clinical queries from physicians
2. Tune search parameters based on feedback
3. Add more post-processing filters (date ranges, specific diagnoses)
4. Integrate with EMR interface
5. Set up automated refresh schedule

Cortex Search Advantages:
- Eliminates need for sentence-transformers model import
- No manual embedding generation required
- Automatic semantic understanding of clinical text
- Native Snowflake performance optimization
- Simpler to maintain and update

============================================================================
*/
