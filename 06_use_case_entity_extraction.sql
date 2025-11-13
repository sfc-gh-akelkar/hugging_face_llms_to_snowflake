-- ============================================================================
-- Use Case: Biomedical Entity Extraction from Clinical Notes
-- ============================================================================
-- Purpose: Extract medications, symptoms, diagnoses, and lab values from
--          clinical documentation using BioBERT
-- Model: dmis-lab/biobert-v1.1
-- Use Case: Automated clinical data extraction for quality metrics and research
-- ============================================================================

USE ROLE ML_ENGINEER;
USE DATABASE PEDIATRIC_ML;
USE WAREHOUSE ML_INFERENCE_WH;

-- ----------------------------------------------------------------------------
-- Step 1: Extract Medical Terms from All Clinical Notes
-- ----------------------------------------------------------------------------

CREATE OR REPLACE TABLE ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES AS
SELECT 
    cn.NOTE_ID,
    cn.PATIENT_ID,
    cn.ENCOUNTER_ID,
    cn.NOTE_DATE,
    cn.NOTE_TYPE,
    e.DEPARTMENT,
    e.PRIMARY_DIAGNOSIS,
    EXTRACT_MEDICAL_TERMS(cn.NOTE_TEXT) AS extracted_terms,
    ARRAY_SIZE(EXTRACT_MEDICAL_TERMS(cn.NOTE_TEXT)) AS term_count,
    CURRENT_TIMESTAMP() AS extraction_timestamp
FROM CLINICAL_DATA.CLINICAL_NOTES cn
JOIN CLINICAL_DATA.ENCOUNTERS e ON cn.ENCOUNTER_ID = e.ENCOUNTER_ID
WHERE e.DEPARTMENT IN ('Pediatric Oncology', 'General Pediatrics')
LIMIT 500;

-- View extraction summary
SELECT 
    DEPARTMENT,
    COUNT(*) AS notes_processed,
    SUM(term_count) AS total_terms_extracted,
    ROUND(AVG(term_count), 1) AS avg_terms_per_note
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES
GROUP BY DEPARTMENT;

-- ----------------------------------------------------------------------------
-- Step 2: Create Normalized Entity Tables
-- ----------------------------------------------------------------------------

-- Medications mentioned in clinical notes
CREATE OR REPLACE VIEW ML_RESULTS.V_EXTRACTED_MEDICATIONS AS
SELECT 
    eme.NOTE_ID,
    eme.PATIENT_ID,
    eme.ENCOUNTER_ID,
    eme.NOTE_DATE,
    eme.DEPARTMENT,
    t.value:term::VARCHAR AS medication_name,
    t.value:category::VARCHAR AS entity_category,
    t.value:start::NUMBER AS position_start,
    t.value:end::NUMBER AS position_end
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES eme,
    LATERAL FLATTEN(input => eme.extracted_terms) t
WHERE t.value:category::VARCHAR = 'medication'
ORDER BY eme.NOTE_DATE DESC, eme.NOTE_ID, position_start;

-- View extracted medications
SELECT 
    medication_name,
    COUNT(DISTINCT PATIENT_ID) AS unique_patients,
    COUNT(DISTINCT NOTE_ID) AS mentions_in_notes,
    DEPARTMENT
FROM ML_RESULTS.V_EXTRACTED_MEDICATIONS
GROUP BY medication_name, DEPARTMENT
ORDER BY mentions_in_notes DESC
LIMIT 20;

-- Symptoms mentioned in clinical notes
CREATE OR REPLACE VIEW ML_RESULTS.V_EXTRACTED_SYMPTOMS AS
SELECT 
    eme.NOTE_ID,
    eme.PATIENT_ID,
    eme.NOTE_DATE,
    eme.DEPARTMENT,
    t.value:term::VARCHAR AS symptom_name,
    t.value:start::NUMBER AS position_start
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES eme,
    LATERAL FLATTEN(input => eme.extracted_terms) t
WHERE t.value:category::VARCHAR = 'symptom';

-- Lab tests mentioned in clinical notes
CREATE OR REPLACE VIEW ML_RESULTS.V_EXTRACTED_LAB_MENTIONS AS
SELECT 
    eme.NOTE_ID,
    eme.PATIENT_ID,
    eme.NOTE_DATE,
    eme.DEPARTMENT,
    t.value:term::VARCHAR AS lab_test_name
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES eme,
    LATERAL FLATTEN(input => eme.extracted_terms) t
WHERE t.value:category::VARCHAR = 'lab';

-- Oncology-specific terms
CREATE OR REPLACE VIEW ML_RESULTS.V_EXTRACTED_ONCOLOGY_TERMS AS
SELECT 
    eme.NOTE_ID,
    eme.PATIENT_ID,
    eme.NOTE_DATE,
    eme.DEPARTMENT,
    eme.PRIMARY_DIAGNOSIS,
    t.value:term::VARCHAR AS oncology_term
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES eme,
    LATERAL FLATTEN(input => eme.extracted_terms) t
WHERE t.value:category::VARCHAR = 'oncology';

-- ----------------------------------------------------------------------------
-- Step 3: Patient Symptom Timeline
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW ML_RESULTS.V_PATIENT_SYMPTOM_TIMELINE AS
WITH patient_symptoms AS (
    SELECT 
        PATIENT_ID,
        symptom_name,
        NOTE_DATE,
        ROW_NUMBER() OVER (PARTITION BY PATIENT_ID, symptom_name ORDER BY NOTE_DATE) AS occurrence_num
    FROM ML_RESULTS.V_EXTRACTED_SYMPTOMS
)
SELECT 
    p.MRN,
    p.FIRST_NAME || ' ' || p.LAST_NAME AS patient_name,
    p.AGE_YEARS,
    ps.symptom_name,
    ps.NOTE_DATE,
    ps.occurrence_num,
    CASE 
        WHEN ps.occurrence_num = 1 THEN 'First Mention'
        WHEN ps.occurrence_num >= 3 THEN 'Recurring'
        ELSE 'Follow-up'
    END AS symptom_status
FROM patient_symptoms ps
JOIN CLINICAL_DATA.PATIENTS p ON ps.PATIENT_ID = p.PATIENT_ID
ORDER BY p.MRN, ps.NOTE_DATE, ps.symptom_name;

-- View symptom timeline for specific patients
SELECT * FROM ML_RESULTS.V_PATIENT_SYMPTOM_TIMELINE
WHERE MRN IN (SELECT MRN FROM CLINICAL_DATA.PATIENTS LIMIT 5)
ORDER BY MRN, NOTE_DATE;

-- ----------------------------------------------------------------------------
-- Step 4: Medication Compliance Checking
-- ----------------------------------------------------------------------------

-- Compare documented medications vs mentioned medications
CREATE OR REPLACE VIEW ML_RESULTS.V_MEDICATION_DOCUMENTATION_CHECK AS
WITH ordered_medications AS (
    SELECT DISTINCT
        m.PATIENT_ID,
        m.ENCOUNTER_ID,
        LOWER(m.MEDICATION_NAME) AS medication_name_ordered,
        m.ORDER_DATE
    FROM CLINICAL_DATA.MEDICATIONS m
),
mentioned_medications AS (
    SELECT DISTINCT
        em.PATIENT_ID,
        em.ENCOUNTER_ID,
        LOWER(em.medication_name) AS medication_name_mentioned,
        em.NOTE_DATE
    FROM ML_RESULTS.V_EXTRACTED_MEDICATIONS em
)
SELECT 
    om.PATIENT_ID,
    om.ENCOUNTER_ID,
    om.medication_name_ordered,
    om.ORDER_DATE,
    mm.medication_name_mentioned,
    mm.NOTE_DATE,
    CASE 
        WHEN mm.medication_name_mentioned IS NOT NULL THEN 'Documented in Note'
        ELSE 'Missing from Note'
    END AS documentation_status
FROM ordered_medications om
LEFT JOIN mentioned_medications mm 
    ON om.PATIENT_ID = mm.PATIENT_ID
    AND om.ENCOUNTER_ID = mm.ENCOUNTER_ID
    AND om.medication_name_ordered = mm.medication_name_mentioned
WHERE om.ORDER_DATE >= DATEADD(DAY, -30, CURRENT_DATE())
ORDER BY om.PATIENT_ID, documentation_status, om.medication_name_ordered;

-- Summary of documentation completeness
SELECT 
    documentation_status,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS percentage
FROM ML_RESULTS.V_MEDICATION_DOCUMENTATION_CHECK
GROUP BY documentation_status;

-- ----------------------------------------------------------------------------
-- Step 5: Adverse Event Detection
-- ----------------------------------------------------------------------------

-- Detect potential adverse events by correlating symptoms with medications
CREATE OR REPLACE VIEW ML_RESULTS.V_POTENTIAL_ADVERSE_EVENTS AS
WITH patient_meds_and_symptoms AS (
    SELECT 
        em.PATIENT_ID,
        em.NOTE_DATE,
        em.NOTE_ID,
        em.medication_name,
        es.symptom_name,
        DATEDIFF(DAY, 
            (SELECT MIN(m.START_DATE) 
             FROM CLINICAL_DATA.MEDICATIONS m 
             WHERE m.PATIENT_ID = em.PATIENT_ID 
                 AND LOWER(m.MEDICATION_NAME) = LOWER(em.medication_name)),
            es.NOTE_DATE) AS days_after_medication_start
    FROM ML_RESULTS.V_EXTRACTED_MEDICATIONS em
    JOIN ML_RESULTS.V_EXTRACTED_SYMPTOMS es 
        ON em.PATIENT_ID = es.PATIENT_ID
        AND em.NOTE_DATE = es.NOTE_DATE
),
known_adverse_events AS (
    -- Common chemotherapy adverse events
    SELECT 'vincristine' AS medication, 'nausea' AS adverse_symptom
    UNION ALL SELECT 'vincristine', 'vomiting'
    UNION ALL SELECT 'vincristine', 'weakness'
    UNION ALL SELECT 'doxorubicin', 'nausea'
    UNION ALL SELECT 'doxorubicin', 'vomiting'
    UNION ALL SELECT 'doxorubicin', 'fatigue'
    UNION ALL SELECT 'cyclophosphamide', 'nausea'
    UNION ALL SELECT 'methotrexate', 'nausea'
)
SELECT 
    pms.PATIENT_ID,
    p.MRN,
    p.FIRST_NAME || ' ' || p.LAST_NAME AS patient_name,
    pms.medication_name,
    pms.symptom_name,
    pms.NOTE_DATE,
    pms.days_after_medication_start,
    CASE 
        WHEN kae.adverse_symptom IS NOT NULL THEN 'Known Adverse Event'
        ELSE 'Potential Adverse Event'
    END AS event_type
FROM patient_meds_and_symptoms pms
JOIN CLINICAL_DATA.PATIENTS p ON pms.PATIENT_ID = p.PATIENT_ID
LEFT JOIN known_adverse_events kae 
    ON LOWER(pms.medication_name) = LOWER(kae.medication)
    AND LOWER(pms.symptom_name) = LOWER(kae.adverse_symptom)
WHERE pms.days_after_medication_start BETWEEN 0 AND 14  -- Within 2 weeks of starting
ORDER BY pms.PATIENT_ID, pms.NOTE_DATE;

-- View adverse events
SELECT 
    event_type,
    medication_name,
    symptom_name,
    COUNT(DISTINCT PATIENT_ID) AS affected_patients,
    COUNT(*) AS total_occurrences
FROM ML_RESULTS.V_POTENTIAL_ADVERSE_EVENTS
GROUP BY event_type, medication_name, symptom_name
ORDER BY affected_patients DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- Step 6: Treatment Regimen Extraction
-- ----------------------------------------------------------------------------

-- Extract common treatment regimens from clinical notes
CREATE OR REPLACE VIEW ML_RESULTS.V_TREATMENT_REGIMENS AS
WITH patient_medications AS (
    SELECT 
        PATIENT_ID,
        NOTE_DATE,
        LISTAGG(DISTINCT medication_name, ' + ') WITHIN GROUP (ORDER BY medication_name) AS regimen
    FROM ML_RESULTS.V_EXTRACTED_MEDICATIONS
    WHERE entity_category = 'medication'
    GROUP BY PATIENT_ID, NOTE_DATE
    HAVING COUNT(DISTINCT medication_name) >= 2  -- At least 2 medications
)
SELECT 
    pm.regimen,
    COUNT(DISTINCT pm.PATIENT_ID) AS num_patients,
    opp.PRIMARY_DIAGNOSIS,
    ROUND(AVG(p.AGE_YEARS), 1) AS avg_patient_age
FROM patient_medications pm
JOIN CLINICAL_DATA.PATIENTS p ON pm.PATIENT_ID = p.PATIENT_ID
LEFT JOIN ML_RESULTS.ONCOLOGY_PATIENT_PROFILES opp ON pm.PATIENT_ID = opp.PATIENT_ID
GROUP BY pm.regimen, opp.PRIMARY_DIAGNOSIS
HAVING COUNT(DISTINCT pm.PATIENT_ID) >= 2
ORDER BY num_patients DESC
LIMIT 20;

-- View common regimens
SELECT * FROM ML_RESULTS.V_TREATMENT_REGIMENS;

-- ----------------------------------------------------------------------------
-- Step 7: Lab Value Extraction from Text
-- ----------------------------------------------------------------------------

-- Create UDF to extract numeric lab values from text
CREATE OR REPLACE FUNCTION EXTRACT_LAB_VALUES(text STRING)
RETURNS ARRAY
LANGUAGE PYTHON
RUNTIME_VERSION = '3.9'
HANDLER = 'extract_values'
AS
$$
import re

def extract_values(text):
    '''
    Extract lab values mentioned in text
    Examples: "WBC 12.5", "Hemoglobin 10.2 g/dL", "Platelets 150 K/uL"
    '''
    if not text:
        return []
    
    # Common lab test patterns
    patterns = [
        (r'wbc[:\s]+(\d+\.?\d*)', 'WBC'),
        (r'hemoglobin[:\s]+(\d+\.?\d*)', 'Hemoglobin'),
        (r'platelets?[:\s]+(\d+\.?\d*)', 'Platelets'),
        (r'anc[:\s]+(\d+\.?\d*)', 'ANC'),
        (r'glucose[:\s]+(\d+\.?\d*)', 'Glucose'),
        (r'creatinine[:\s]+(\d+\.?\d*)', 'Creatinine'),
    ]
    
    extracted_values = []
    text_lower = text.lower()
    
    for pattern, test_name in patterns:
        matches = re.finditer(pattern, text_lower)
        for match in matches:
            try:
                value = float(match.group(1))
                extracted_values.append({
                    'test_name': test_name,
                    'value': value,
                    'position': match.start()
                })
            except:
                pass
    
    return extracted_values
$$;

-- Apply lab value extraction
CREATE OR REPLACE TABLE ML_RESULTS.EXTRACTED_LAB_VALUES AS
SELECT 
    NOTE_ID,
    PATIENT_ID,
    NOTE_DATE,
    DEPARTMENT,
    EXTRACT_LAB_VALUES(NOTE_TEXT) AS lab_values,
    ARRAY_SIZE(EXTRACT_LAB_VALUES(NOTE_TEXT)) AS num_values_found
FROM CLINICAL_DATA.CLINICAL_NOTES
WHERE NOTE_TEXT LIKE '%WBC%' 
    OR NOTE_TEXT LIKE '%hemoglobin%'
    OR NOTE_TEXT LIKE '%platelets%'
LIMIT 200;

-- Unnest and analyze
SELECT 
    lv.value:test_name::VARCHAR AS test_name,
    lv.value:value::FLOAT AS test_value,
    elv.NOTE_DATE,
    elv.PATIENT_ID
FROM ML_RESULTS.EXTRACTED_LAB_VALUES elv,
    LATERAL FLATTEN(input => elv.lab_values) lv
ORDER BY test_name, NOTE_DATE;

-- ----------------------------------------------------------------------------
-- Step 8: Quality Metrics Dashboard
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW ML_RESULTS.V_ENTITY_EXTRACTION_METRICS AS
SELECT 
    'Total Notes Processed' AS metric,
    CAST(COUNT(DISTINCT NOTE_ID) AS VARCHAR) AS value,
    NULL AS breakdown
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES

UNION ALL

SELECT 
    'Total Entities Extracted',
    CAST(SUM(term_count) AS VARCHAR),
    NULL
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES

UNION ALL

SELECT 
    'Unique Patients',
    CAST(COUNT(DISTINCT PATIENT_ID) AS VARCHAR),
    NULL
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES

UNION ALL

SELECT 
    'Medications Extracted',
    CAST(COUNT(*) AS VARCHAR),
    DEPARTMENT
FROM ML_RESULTS.V_EXTRACTED_MEDICATIONS
GROUP BY DEPARTMENT

UNION ALL

SELECT 
    'Symptoms Extracted',
    CAST(COUNT(*) AS VARCHAR),
    DEPARTMENT
FROM ML_RESULTS.V_EXTRACTED_SYMPTOMS
GROUP BY DEPARTMENT

UNION ALL

SELECT 
    'Avg Entities per Note',
    CAST(ROUND(AVG(term_count), 1) AS VARCHAR),
    DEPARTMENT
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES
GROUP BY DEPARTMENT

ORDER BY metric, breakdown;

-- View metrics
SELECT * FROM ML_RESULTS.V_ENTITY_EXTRACTION_METRICS;

-- ----------------------------------------------------------------------------
-- Step 9: Export for Manual Validation
-- ----------------------------------------------------------------------------

-- Create sample for clinical validation
CREATE OR REPLACE TABLE ML_RESULTS.ENTITY_EXTRACTION_VALIDATION_SAMPLE AS
SELECT 
    eme.NOTE_ID,
    p.MRN,
    eme.NOTE_DATE,
    eme.DEPARTMENT,
    eme.PRIMARY_DIAGNOSIS,
    eme.extracted_terms,
    eme.term_count,
    'Pending Review' AS validation_status,
    NULL AS reviewer_name,
    NULL AS review_date,
    NULL AS accuracy_score
FROM ML_RESULTS.EXTRACTED_MEDICAL_ENTITIES eme
JOIN CLINICAL_DATA.PATIENTS p ON eme.PATIENT_ID = p.PATIENT_ID
ORDER BY RANDOM()
LIMIT 50;

-- View sample for validation
SELECT 
    NOTE_ID,
    MRN,
    DEPARTMENT,
    PRIMARY_DIAGNOSIS,
    term_count,
    validation_status
FROM ML_RESULTS.ENTITY_EXTRACTION_VALIDATION_SAMPLE
ORDER BY NOTE_ID;

-- ----------------------------------------------------------------------------
-- Step 10: Research Cohort Building
-- ----------------------------------------------------------------------------

-- Find patients with specific entity combinations for research
CREATE OR REPLACE FUNCTION FIND_PATIENTS_WITH_ENTITIES(
    required_medications ARRAY,
    required_symptoms ARRAY,
    department_filter VARCHAR
)
RETURNS TABLE (
    patient_id NUMBER,
    mrn VARCHAR,
    age_years NUMBER,
    num_matching_meds NUMBER,
    num_matching_symptoms NUMBER,
    latest_note_date TIMESTAMP_NTZ
)
AS
$$
    WITH patient_meds AS (
        SELECT DISTINCT
            em.PATIENT_ID,
            em.medication_name
        FROM ML_RESULTS.V_EXTRACTED_MEDICATIONS em
        WHERE em.DEPARTMENT = department_filter OR department_filter = 'ALL'
    ),
    patient_symptoms AS (
        SELECT DISTINCT
            es.PATIENT_ID,
            es.symptom_name
        FROM ML_RESULTS.V_EXTRACTED_SYMPTOMS es
        WHERE es.DEPARTMENT = department_filter OR department_filter = 'ALL'
    ),
    patient_matches AS (
        SELECT 
            pm.PATIENT_ID,
            COUNT(DISTINCT CASE WHEN rm.value::VARCHAR = pm.medication_name THEN 1 END) AS num_matching_meds,
            COUNT(DISTINCT CASE WHEN rs.value::VARCHAR = ps.symptom_name THEN 1 END) AS num_matching_symptoms
        FROM patient_meds pm
        CROSS JOIN TABLE(FLATTEN(input => required_medications)) rm
        LEFT JOIN patient_symptoms ps ON pm.PATIENT_ID = ps.PATIENT_ID
        CROSS JOIN TABLE(FLATTEN(input => required_symptoms)) rs
        GROUP BY pm.PATIENT_ID
    )
    SELECT 
        pm.PATIENT_ID,
        p.MRN,
        p.AGE_YEARS,
        pm.num_matching_meds,
        pm.num_matching_symptoms,
        MAX(cn.NOTE_DATE) AS latest_note_date
    FROM patient_matches pm
    JOIN CLINICAL_DATA.PATIENTS p ON pm.PATIENT_ID = p.PATIENT_ID
    JOIN CLINICAL_DATA.CLINICAL_NOTES cn ON pm.PATIENT_ID = cn.PATIENT_ID
    WHERE pm.num_matching_meds >= ARRAY_SIZE(required_medications)
        AND pm.num_matching_symptoms >= ARRAY_SIZE(required_symptoms)
    GROUP BY pm.PATIENT_ID, p.MRN, p.AGE_YEARS, pm.num_matching_meds, pm.num_matching_symptoms
$$;

-- Example: Find patients on vincristine who experienced nausea
SELECT * FROM TABLE(
    FIND_PATIENTS_WITH_ENTITIES(
        ARRAY_CONSTRUCT('vincristine'),
        ARRAY_CONSTRUCT('nausea'),
        'Pediatric Oncology'
    )
);

/*
============================================================================
ENTITY EXTRACTION USE CASE SUMMARY
============================================================================

Capabilities Demonstrated:
✓ Extract medical entities (medications, symptoms, labs, diagnoses)
✓ Track patient symptom timelines
✓ Check medication documentation completeness
✓ Detect potential adverse events
✓ Identify treatment regimens from notes
✓ Extract numeric lab values from text
✓ Build research cohorts based on entity combinations
✓ Generate quality metrics

Clinical Value:
- Documentation Quality: Identify gaps in clinical documentation
- Pharmacovigilance: Detect adverse drug events
- Research: Build cohorts for retrospective studies
- Quality Metrics: Track symptom management and treatment patterns
- Decision Support: Understand full clinical picture from notes

Success Metrics:
- Extraction accuracy: > 85% precision on medications and symptoms
- Processing speed: < 2 seconds per note
- Documentation completeness: Improve from 70% to 90%
- Adverse event detection: Identify 95% of known ADEs

Limitations:
- Rule-based extraction (not full NER model)
- Limited to pre-defined entity categories
- May miss context and negation
- Requires validation by clinical experts

Improvements for Production:
1. Fine-tune BioBERT on pediatric clinical notes for NER
2. Add negation detection ("no fever" vs "fever")
3. Add temporal extraction (onset, duration, resolution)
4. Include severity and frequency modifiers
5. Implement relationship extraction (drug-symptom pairs)
6. Add spell-checking and abbreviation expansion

Example Workflows:
1. Quality Improvement: Extract chemotherapy regimens across all ALL patients
2. Pharmacovigilance: Monitor for vincristine-related neuropathy
3. Research: Build cohort of patients with fever + neutropenia
4. Documentation: Alert if prescribed medication not mentioned in note

Next Steps:
1. Validate extraction accuracy on 100 random notes
2. Compare against structured data (orders, labs) for consistency
3. Train clinical staff on using entity extraction queries
4. Set up automated alerts for adverse event patterns
5. Integrate with quality dashboard

============================================================================
*/

