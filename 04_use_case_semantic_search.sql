-- ============================================================================
-- Use Case: Semantic Search of Clinical Notes
-- ============================================================================
-- Purpose: Find similar patient cases based on clinical note content
-- Model: sentence-transformers/all-MiniLM-L6-v2
-- Use Case: Help clinicians find relevant similar cases for decision support
-- ============================================================================

USE ROLE ML_ENGINEER;
USE DATABASE PEDIATRIC_ML;
USE WAREHOUSE ML_INFERENCE_WH;

-- ----------------------------------------------------------------------------
-- Step 1: Create embeddings for all clinical notes
-- ----------------------------------------------------------------------------

-- Note: For production, this would be done incrementally as new notes arrive
-- For PoC, we'll create embeddings for a subset of notes

CREATE OR REPLACE TABLE ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS AS
SELECT 
    CN.NOTE_ID,
    CN.PATIENT_ID,
    CN.ENCOUNTER_ID,
    CN.NOTE_DATE,
    CN.NOTE_TYPE,
    E.DEPARTMENT,
    E.PRIMARY_DIAGNOSIS,
    CN.NOTE_TEXT,
    EMBED_TEXT(CN.NOTE_TEXT) AS embedding,
    CURRENT_TIMESTAMP() AS embedding_created_at
FROM CLINICAL_DATA.CLINICAL_NOTES CN
JOIN CLINICAL_DATA.ENCOUNTERS E ON CN.ENCOUNTER_ID = E.ENCOUNTER_ID
WHERE E.DEPARTMENT IN ('Pediatric Oncology', 'General Pediatrics')
LIMIT 500;  -- Start with 500 notes for PoC

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_note_embeddings_note_id 
    ON ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS(NOTE_ID);

-- Check embedding statistics
SELECT 
    'Total notes embedded' AS metric,
    COUNT(*) AS value
FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS
UNION ALL
SELECT 
    'Unique patients',
    COUNT(DISTINCT PATIENT_ID)
FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS
UNION ALL
SELECT 
    'Departments',
    COUNT(DISTINCT DEPARTMENT)
FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS
UNION ALL
SELECT 
    'Avg embedding dimension',
    CAST(AVG(ARRAY_SIZE(embedding)) AS NUMBER)
FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS;

-- ----------------------------------------------------------------------------
-- Step 2: Semantic Search Function - Find Similar Notes
-- ----------------------------------------------------------------------------

-- Example 1: Find notes similar to a specific note
-- Use case: "Show me similar cases to this patient"

WITH source_note AS (
    SELECT 
        NOTE_ID,
        PATIENT_ID,
        NOTE_TEXT,
        DEPARTMENT,
        PRIMARY_DIAGNOSIS,
        embedding
    FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS
    WHERE NOTE_ID = 1  -- Example: First note
)
SELECT 
    s.NOTE_ID AS source_note_id,
    s.PRIMARY_DIAGNOSIS AS source_diagnosis,
    t.NOTE_ID AS similar_note_id,
    t.PATIENT_ID AS similar_patient_id,
    t.PRIMARY_DIAGNOSIS AS similar_diagnosis,
    t.DEPARTMENT,
    COSINE_SIMILARITY(s.embedding, t.embedding) AS similarity_score,
    SUBSTR(t.NOTE_TEXT, 1, 200) || '...' AS note_preview
FROM source_note s
CROSS JOIN ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS t
WHERE t.NOTE_ID != s.NOTE_ID
ORDER BY similarity_score DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- Step 3: Search by Query Text
-- ----------------------------------------------------------------------------

-- Example 2: Search notes using natural language query
-- Use case: "Find all cases with symptoms similar to fever and fatigue"

CREATE OR REPLACE VIEW ML_RESULTS.V_SEARCH_CLINICAL_NOTES AS
WITH query_embedding AS (
    SELECT EMBED_TEXT('Patient presents with fever, fatigue, and low white blood cell count. Suspected acute leukemia.') AS query_emb
)
SELECT 
    cn.NOTE_ID,
    cn.PATIENT_ID,
    p.FIRST_NAME || ' ' || p.LAST_NAME AS patient_name,
    p.AGE_YEARS,
    cn.DEPARTMENT,
    cn.PRIMARY_DIAGNOSIS,
    cn.NOTE_DATE,
    COSINE_SIMILARITY(qe.query_emb, cn.embedding) AS relevance_score,
    SUBSTR(cn.NOTE_TEXT, 1, 300) || '...' AS note_excerpt
FROM query_embedding qe
CROSS JOIN ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS cn
JOIN CLINICAL_DATA.PATIENTS p ON cn.PATIENT_ID = p.PATIENT_ID
WHERE COSINE_SIMILARITY(qe.query_emb, cn.embedding) > 0.5  -- Threshold
ORDER BY relevance_score DESC
LIMIT 20;

-- View results
SELECT * FROM ML_RESULTS.V_SEARCH_CLINICAL_NOTES;

-- ----------------------------------------------------------------------------
-- Step 4: Department-Specific Semantic Search
-- ----------------------------------------------------------------------------

-- Example 3: Find similar oncology cases
CREATE OR REPLACE FUNCTION FIND_SIMILAR_ONCOLOGY_CASES(
    query_text VARCHAR,
    top_k NUMBER
)
RETURNS TABLE (
    NOTE_ID NUMBER,
    PATIENT_ID NUMBER,
    DIAGNOSIS VARCHAR,
    SIMILARITY_SCORE FLOAT,
    NOTE_PREVIEW VARCHAR
)
AS
$$
    WITH query_embedding AS (
        SELECT EMBED_TEXT(query_text) AS query_emb
    )
    SELECT 
        cn.NOTE_ID,
        cn.PATIENT_ID,
        cn.PRIMARY_DIAGNOSIS AS DIAGNOSIS,
        COSINE_SIMILARITY(qe.query_emb, cn.embedding) AS SIMILARITY_SCORE,
        SUBSTR(cn.NOTE_TEXT, 1, 200) AS NOTE_PREVIEW
    FROM query_embedding qe
    CROSS JOIN ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS cn
    WHERE cn.DEPARTMENT = 'Pediatric Oncology'
    ORDER BY SIMILARITY_SCORE DESC
    LIMIT top_k
$$;

-- Test the function
SELECT * FROM TABLE(
    FIND_SIMILAR_ONCOLOGY_CASES(
        'Pediatric patient with acute lymphoblastic leukemia undergoing induction chemotherapy with vincristine and doxorubicin',
        10
    )
);

-- ----------------------------------------------------------------------------
-- Step 5: Patient Case Matching
-- ----------------------------------------------------------------------------

-- Example 4: For a new patient, find the most similar historical cases
-- Use case: Clinical decision support - "What treatments worked for similar patients?"

CREATE OR REPLACE VIEW ML_RESULTS.V_PATIENT_CASE_MATCHES AS
WITH current_patients AS (
    -- Get most recent note for each patient
    SELECT 
        PATIENT_ID,
        NOTE_ID,
        NOTE_TEXT,
        embedding,
        PRIMARY_DIAGNOSIS,
        DEPARTMENT
    FROM (
        SELECT 
            *,
            ROW_NUMBER() OVER (PARTITION BY PATIENT_ID ORDER BY NOTE_DATE DESC) AS rn
        FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS
    )
    WHERE rn = 1
),
historical_outcomes AS (
    -- Get historical cases with outcomes (simplified - would join to outcomes table)
    SELECT 
        NOTE_ID,
        PATIENT_ID,
        PRIMARY_DIAGNOSIS,
        embedding,
        NOTE_DATE
    FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS
    WHERE NOTE_DATE < DATEADD(MONTH, -6, CURRENT_DATE())  -- At least 6 months old
)
SELECT 
    cp.PATIENT_ID AS current_patient_id,
    cp.PRIMARY_DIAGNOSIS AS current_diagnosis,
    ho.PATIENT_ID AS similar_historical_patient_id,
    ho.PRIMARY_DIAGNOSIS AS historical_diagnosis,
    COSINE_SIMILARITY(cp.embedding, ho.embedding) AS case_similarity,
    ho.NOTE_DATE AS historical_case_date,
    DATEDIFF(MONTH, ho.NOTE_DATE, CURRENT_DATE()) AS months_ago
FROM current_patients cp
CROSS JOIN historical_outcomes ho
WHERE cp.PATIENT_ID != ho.PATIENT_ID
    AND COSINE_SIMILARITY(cp.embedding, ho.embedding) > 0.6  -- High similarity threshold
QUALIFY ROW_NUMBER() OVER (PARTITION BY cp.PATIENT_ID ORDER BY case_similarity DESC) <= 5;

-- View patient matches
SELECT * FROM ML_RESULTS.V_PATIENT_CASE_MATCHES
ORDER BY current_patient_id, case_similarity DESC;

-- ----------------------------------------------------------------------------
-- Step 6: Clustering Similar Cases
-- ----------------------------------------------------------------------------

-- Example 5: Find clusters of similar presentations
-- Use case: "Group similar presentations for quality improvement studies"

CREATE OR REPLACE VIEW ML_RESULTS.V_CASE_CLUSTERS AS
WITH pairwise_similarities AS (
    SELECT 
        n1.NOTE_ID AS note_id_1,
        n2.NOTE_ID AS note_id_2,
        n1.PRIMARY_DIAGNOSIS AS diagnosis_1,
        n2.PRIMARY_DIAGNOSIS AS diagnosis_2,
        n1.DEPARTMENT,
        COSINE_SIMILARITY(n1.embedding, n2.embedding) AS similarity
    FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS n1
    JOIN ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS n2
        ON n1.DEPARTMENT = n2.DEPARTMENT
        AND n1.NOTE_ID < n2.NOTE_ID  -- Avoid duplicates
    WHERE COSINE_SIMILARITY(n1.embedding, n2.embedding) > 0.75  -- Very similar
)
SELECT 
    DEPARTMENT,
    diagnosis_1,
    diagnosis_2,
    COUNT(*) AS similar_case_pairs,
    ROUND(AVG(similarity), 3) AS avg_similarity
FROM pairwise_similarities
GROUP BY DEPARTMENT, diagnosis_1, diagnosis_2
HAVING COUNT(*) >= 3  -- At least 3 similar pairs
ORDER BY similar_case_pairs DESC, avg_similarity DESC
LIMIT 20;

-- View clusters
SELECT * FROM ML_RESULTS.V_CASE_CLUSTERS;

-- ----------------------------------------------------------------------------
-- Step 7: Real-time Search Interface
-- ----------------------------------------------------------------------------

-- Create a stored procedure for interactive search
CREATE OR REPLACE PROCEDURE SEARCH_CLINICAL_NOTES(
    search_query VARCHAR,
    department_filter VARCHAR,
    max_results NUMBER
)
RETURNS TABLE (
    note_id NUMBER,
    patient_id NUMBER,
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
DECLARE
    query_emb ARRAY;
BEGIN
    -- Generate embedding for search query
    query_emb := (SELECT EMBED_TEXT(:search_query));
    
    -- Return matching notes
    LET res RESULTSET := (
        WITH search_results AS (
            SELECT 
                cn.NOTE_ID,
                cn.PATIENT_ID,
                p.AGE_YEARS,
                cn.PRIMARY_DIAGNOSIS,
                cn.DEPARTMENT,
                cn.NOTE_DATE,
                COSINE_SIMILARITY(:query_emb, cn.embedding) AS relevance_score,
                SUBSTR(cn.NOTE_TEXT, 1, 300) AS note_excerpt
            FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS cn
            JOIN CLINICAL_DATA.PATIENTS p ON cn.PATIENT_ID = p.PATIENT_ID
            WHERE 
                (UPPER(:department_filter) = 'ALL' OR cn.DEPARTMENT = :department_filter)
                AND COSINE_SIMILARITY(:query_emb, cn.embedding) > 0.3
            ORDER BY relevance_score DESC
            LIMIT :max_results
        )
        SELECT * FROM search_results
    );
    
    RETURN TABLE(res);
END;
$$;

-- Test the search procedure
CALL SEARCH_CLINICAL_NOTES(
    'Chemotherapy side effects nausea vomiting', 
    'Pediatric Oncology',
    10
);

-- ----------------------------------------------------------------------------
-- Step 8: Performance Metrics
-- ----------------------------------------------------------------------------

-- Track search performance
CREATE OR REPLACE TABLE ML_RESULTS.SEARCH_METRICS (
    metric_id NUMBER AUTOINCREMENT,
    search_date DATE,
    total_searches NUMBER,
    avg_results_returned NUMBER,
    avg_relevance_score FLOAT,
    PRIMARY KEY (metric_id)
);

-- Calculate current metrics
INSERT INTO ML_RESULTS.SEARCH_METRICS (
    search_date,
    total_searches,
    avg_results_returned,
    avg_relevance_score
)
SELECT 
    CURRENT_DATE(),
    500,  -- Example: 500 searches performed
    15,   -- Average 15 results per search
    0.72  -- Average relevance score of 0.72
;

-- ----------------------------------------------------------------------------
-- Step 9: Export Results for Clinical Review
-- ----------------------------------------------------------------------------

-- Create a view for clinicians to review similar cases
CREATE OR REPLACE VIEW ML_RESULTS.V_CLINICIAN_CASE_REVIEW AS
SELECT 
    cne.NOTE_ID,
    p.MRN,
    p.FIRST_NAME || ' ' || p.LAST_NAME AS patient_name,
    p.AGE_YEARS,
    cne.DEPARTMENT,
    cne.PRIMARY_DIAGNOSIS,
    cne.NOTE_DATE,
    cne.NOTE_TYPE,
    cne.NOTE_TEXT,
    (
        SELECT COUNT(*) 
        FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS cne2
        WHERE cne2.NOTE_ID != cne.NOTE_ID
            AND COSINE_SIMILARITY(cne.embedding, cne2.embedding) > 0.7
    ) AS num_similar_cases
FROM ML_RESULTS.CLINICAL_NOTE_EMBEDDINGS cne
JOIN CLINICAL_DATA.PATIENTS p ON cne.PATIENT_ID = p.PATIENT_ID
WHERE cne.DEPARTMENT = 'Pediatric Oncology'
ORDER BY num_similar_cases DESC, cne.NOTE_DATE DESC;

-- View top cases with many similar matches
SELECT 
    NOTE_ID,
    MRN,
    patient_name,
    AGE_YEARS,
    PRIMARY_DIAGNOSIS,
    num_similar_cases,
    NOTE_DATE
FROM ML_RESULTS.V_CLINICIAN_CASE_REVIEW
LIMIT 20;

/*
============================================================================
SEMANTIC SEARCH USE CASE SUMMARY
============================================================================

Capabilities Demonstrated:
✓ Embed clinical notes into 384-dimensional vectors
✓ Find similar patient cases using cosine similarity
✓ Natural language search of clinical documentation
✓ Department-specific case matching
✓ Historical case retrieval for decision support
✓ Case clustering for quality improvement
✓ Real-time search interface via stored procedure

Success Metrics:
- Search relevance: > 70% similarity score for top results
- Query time: < 3 seconds for 500 notes
- Clinician satisfaction: Can find relevant cases in < 1 minute

Next Steps:
1. Test with real de-identified clinical data
2. Gather clinician feedback on result relevance
3. Integrate with Epic/Cerner EMR
4. Add more sophisticated filters (age, diagnosis, medications)
5. Implement feedback loop to improve ranking

Use Cases:
- Clinical decision support: Find similar cases and their outcomes
- Medical education: Retrieve relevant cases for teaching
- Quality improvement: Identify patterns in clinical documentation
- Research: Find cohorts of similar patients for studies

============================================================================
*/

