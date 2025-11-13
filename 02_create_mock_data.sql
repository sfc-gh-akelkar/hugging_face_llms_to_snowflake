-- ============================================================================
-- Mock Clinical Data Generator
-- ============================================================================
-- Purpose: Create realistic mock data mimicking Clarity/Caboodle clinical data
-- Note: This is synthetic data for PoC purposes only
-- ============================================================================

USE ROLE ML_ENGINEER;
USE DATABASE PEDIATRIC_ML;
USE SCHEMA CLINICAL_DATA;
USE WAREHOUSE DATA_LOAD_WH;

-- ----------------------------------------------------------------------------
-- 1. Patient Demographics (mimics Epic Clarity PATIENT table)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE TABLE PATIENTS (
    PATIENT_ID NUMBER AUTOINCREMENT,
    MRN VARCHAR(20),  -- Medical Record Number
    FIRST_NAME VARCHAR(50),
    LAST_NAME VARCHAR(50),
    DATE_OF_BIRTH DATE,
    AGE_YEARS NUMBER,
    GENDER VARCHAR(10),
    RACE VARCHAR(50),
    ETHNICITY VARCHAR(50),
    PRIMARY_LANGUAGE VARCHAR(20),
    ZIP_CODE VARCHAR(10),
    CREATED_DATE TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (PATIENT_ID)
);

-- Generate 1000 mock pediatric patients
INSERT INTO PATIENTS (MRN, FIRST_NAME, LAST_NAME, DATE_OF_BIRTH, AGE_YEARS, GENDER, RACE, ETHNICITY, PRIMARY_LANGUAGE, ZIP_CODE)
SELECT
    'MRN' || LPAD(SEQ4(), 8, '0') AS MRN,
    CASE (UNIFORM(1, 10, RANDOM()) % 10)
        WHEN 0 THEN 'Emma' WHEN 1 THEN 'Liam' WHEN 2 THEN 'Olivia'
        WHEN 3 THEN 'Noah' WHEN 4 THEN 'Ava' WHEN 5 THEN 'Sophia'
        WHEN 6 THEN 'Jackson' WHEN 7 THEN 'Isabella' WHEN 8 THEN 'Lucas'
        ELSE 'Mia'
    END AS FIRST_NAME,
    CASE (UNIFORM(1, 10, RANDOM()) % 10)
        WHEN 0 THEN 'Smith' WHEN 1 THEN 'Johnson' WHEN 2 THEN 'Williams'
        WHEN 3 THEN 'Brown' WHEN 4 THEN 'Jones' WHEN 5 THEN 'Garcia'
        WHEN 6 THEN 'Miller' WHEN 7 THEN 'Davis' WHEN 8 THEN 'Rodriguez'
        ELSE 'Martinez'
    END AS LAST_NAME,
    DATEADD(DAY, -UNIFORM(365, 6570, RANDOM()), CURRENT_DATE()) AS DATE_OF_BIRTH,  -- Ages 1-18
    FLOOR(DATEDIFF(DAY, DATEADD(DAY, -UNIFORM(365, 6570, RANDOM()), CURRENT_DATE()), CURRENT_DATE()) / 365.25) AS AGE_YEARS,
    CASE (UNIFORM(1, 2, RANDOM()) % 2) WHEN 0 THEN 'Male' ELSE 'Female' END AS GENDER,
    CASE (UNIFORM(1, 6, RANDOM()) % 6)
        WHEN 0 THEN 'White' WHEN 1 THEN 'Black or African American'
        WHEN 2 THEN 'Asian' WHEN 3 THEN 'Hispanic or Latino'
        WHEN 4 THEN 'Other' ELSE 'Multiracial'
    END AS RACE,
    CASE (UNIFORM(1, 3, RANDOM()) % 3)
        WHEN 0 THEN 'Hispanic or Latino' WHEN 1 THEN 'Not Hispanic or Latino'
        ELSE 'Unknown'
    END AS ETHNICITY,
    CASE (UNIFORM(1, 5, RANDOM()) % 5)
        WHEN 0 THEN 'English' WHEN 1 THEN 'Spanish' WHEN 2 THEN 'Chinese'
        WHEN 3 THEN 'Vietnamese' ELSE 'English'
    END AS PRIMARY_LANGUAGE,
    LPAD(UNIFORM(10000, 99999, RANDOM()), 5, '0') AS ZIP_CODE
FROM TABLE(GENERATOR(ROWCOUNT => 1000));

-- ----------------------------------------------------------------------------
-- 2. Clinical Encounters (mimics Epic PAT_ENC table)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE TABLE ENCOUNTERS (
    ENCOUNTER_ID NUMBER AUTOINCREMENT,
    PATIENT_ID NUMBER,
    ENCOUNTER_DATE DATE,
    ENCOUNTER_TYPE VARCHAR(50),
    DEPARTMENT VARCHAR(100),
    PRIMARY_DIAGNOSIS VARCHAR(200),
    ATTENDING_PROVIDER VARCHAR(100),
    ENCOUNTER_STATUS VARCHAR(20),
    PRIMARY KEY (ENCOUNTER_ID),
    FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID)
);

-- Generate encounters for patients
INSERT INTO ENCOUNTERS (PATIENT_ID, ENCOUNTER_DATE, ENCOUNTER_TYPE, DEPARTMENT, PRIMARY_DIAGNOSIS, ATTENDING_PROVIDER, ENCOUNTER_STATUS)
SELECT
    PATIENT_ID,
    DATEADD(DAY, -UNIFORM(1, 730, RANDOM()), CURRENT_DATE()) AS ENCOUNTER_DATE,
    CASE (UNIFORM(1, 6, RANDOM()) % 6)
        WHEN 0 THEN 'Office Visit' WHEN 1 THEN 'Emergency'
        WHEN 2 THEN 'Inpatient' WHEN 3 THEN 'Telehealth'
        WHEN 4 THEN 'Surgery' ELSE 'Follow-up'
    END AS ENCOUNTER_TYPE,
    CASE (UNIFORM(1, 8, RANDOM()) % 8)
        WHEN 0 THEN 'Pediatric Oncology' WHEN 1 THEN 'General Pediatrics'
        WHEN 2 THEN 'Pediatric Cardiology' WHEN 3 THEN 'Pediatric Neurology'
        WHEN 4 THEN 'Pediatric Surgery' WHEN 5 THEN 'Emergency Department'
        WHEN 6 THEN 'Pediatric ICU' ELSE 'Outpatient Clinic'
    END AS DEPARTMENT,
    CASE (UNIFORM(1, 15, RANDOM()) % 15)
        WHEN 0 THEN 'Acute Lymphoblastic Leukemia (ALL)'
        WHEN 1 THEN 'Acute Myeloid Leukemia (AML)'
        WHEN 2 THEN 'Neuroblastoma'
        WHEN 3 THEN 'Wilms Tumor'
        WHEN 4 THEN 'Brain Tumor - Medulloblastoma'
        WHEN 5 THEN 'Lymphoma'
        WHEN 6 THEN 'Asthma Exacerbation'
        WHEN 7 THEN 'Type 1 Diabetes Mellitus'
        WHEN 8 THEN 'Pneumonia'
        WHEN 9 THEN 'Gastroenteritis'
        WHEN 10 THEN 'Seizure Disorder'
        WHEN 11 THEN 'Congenital Heart Disease'
        WHEN 12 THEN 'Fracture - upper extremity'
        WHEN 13 THEN 'Well Child Visit'
        ELSE 'Upper Respiratory Infection'
    END AS PRIMARY_DIAGNOSIS,
    'Dr. ' || CASE (UNIFORM(1, 8, RANDOM()) % 8)
        WHEN 0 THEN 'Anderson' WHEN 1 THEN 'Chen' WHEN 2 THEN 'Patel'
        WHEN 3 THEN 'Thompson' WHEN 4 THEN 'Garcia' WHEN 5 THEN 'Williams'
        WHEN 6 THEN 'Johnson' ELSE 'Rodriguez'
    END AS ATTENDING_PROVIDER,
    'Completed' AS ENCOUNTER_STATUS
FROM PATIENTS
CROSS JOIN TABLE(GENERATOR(ROWCOUNT => 3))  -- 3 encounters per patient on average
WHERE UNIFORM(1, 10, RANDOM()) > 1;  -- 90% of patients have encounters

-- ----------------------------------------------------------------------------
-- 3. Clinical Notes (mimics Epic HNO_NOTE_TEXT table)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE TABLE CLINICAL_NOTES (
    NOTE_ID NUMBER AUTOINCREMENT,
    ENCOUNTER_ID NUMBER,
    PATIENT_ID NUMBER,
    NOTE_DATE TIMESTAMP_NTZ,
    NOTE_TYPE VARCHAR(50),
    NOTE_STATUS VARCHAR(20),
    AUTHOR VARCHAR(100),
    NOTE_TEXT VARCHAR(16777216),  -- Max VARCHAR size in Snowflake
    PRIMARY KEY (NOTE_ID),
    FOREIGN KEY (ENCOUNTER_ID) REFERENCES ENCOUNTERS(ENCOUNTER_ID),
    FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID)
);

-- Generate clinical notes with realistic content
INSERT INTO CLINICAL_NOTES (ENCOUNTER_ID, PATIENT_ID, NOTE_DATE, NOTE_TYPE, NOTE_STATUS, AUTHOR, NOTE_TEXT)
SELECT
    E.ENCOUNTER_ID,
    E.PATIENT_ID,
    E.ENCOUNTER_DATE,
    CASE (UNIFORM(1, 5, RANDOM()) % 5)
        WHEN 0 THEN 'Progress Note' WHEN 1 THEN 'H&P Note'
        WHEN 2 THEN 'Discharge Summary' WHEN 3 THEN 'Consultation Note'
        ELSE 'Procedure Note'
    END AS NOTE_TYPE,
    'Signed' AS NOTE_STATUS,
    E.ATTENDING_PROVIDER AS AUTHOR,
    -- Generate realistic clinical note text
    'CHIEF COMPLAINT: ' ||
    CASE 
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Leukemia%' THEN 'Fever and fatigue, ongoing chemotherapy treatment'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Asthma%' THEN 'Shortness of breath and wheezing'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Diabetes%' THEN 'Blood sugar management follow-up'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Pneumonia%' THEN 'Cough, fever, and difficulty breathing'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Seizure%' THEN 'Seizure episode, medication adjustment needed'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Tumor%' THEN 'Chemotherapy follow-up, tumor monitoring'
        ELSE 'General pediatric concern'
    END ||
    '\n\nHISTORY OF PRESENT ILLNESS: Patient is a ' || 
    CAST(FLOOR(DATEDIFF(DAY, P.DATE_OF_BIRTH, E.ENCOUNTER_DATE) / 365.25) AS VARCHAR) ||
    ' year old ' || P.GENDER || ' presenting with ' || E.PRIMARY_DIAGNOSIS || '. ' ||
    CASE 
        WHEN E.DEPARTMENT = 'Pediatric Oncology' THEN 
            'Patient is currently undergoing treatment protocol. Recent labs show WBC count monitored. ' ||
            'Chemotherapy regimen includes vincristine, doxorubicin, and prednisone. ' ||
            'Patient tolerating treatment with manageable side effects including nausea controlled with ondansetron.'
        WHEN E.DEPARTMENT = 'Emergency Department' THEN
            'Patient arrived via ambulance. Vitals on arrival: HR 120, RR 28, Temp 101.2F, O2 sat 94% on RA. ' ||
            'Patient appears in moderate distress. Physical examination significant for findings consistent with diagnosis.'
        WHEN E.DEPARTMENT = 'General Pediatrics' THEN
            'Patient is here for routine follow-up. Growth and development appropriate for age. ' ||
            'Immunizations are up to date. Family history non-contributory.'
        ELSE
            'Patient has been under our care for this condition. Symptoms have been managed with current treatment plan.'
    END ||
    '\n\nMEDICATIONS: ' ||
    CASE 
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Leukemia%' OR E.PRIMARY_DIAGNOSIS LIKE '%Lymphoma%' THEN
            'Vincristine 1.5mg/m2 IV weekly, Doxorubicin 30mg/m2 IV, Prednisone 40mg PO daily, ' ||
            'Ondansetron 4mg PO q8h PRN nausea, Filgrastim 5mcg/kg SQ daily'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Asthma%' THEN
            'Albuterol 2 puffs q4-6h PRN, Fluticasone 88mcg 2 puffs BID, Montelukast 5mg PO daily'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Diabetes%' THEN
            'Insulin glargine 10 units SQ qHS, Insulin lispro per sliding scale with meals'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Seizure%' THEN
            'Levetiracetam 500mg PO BID, Lamotrigine 100mg PO BID'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Pneumonia%' THEN
            'Ceftriaxone 50mg/kg IV daily, Azithromycin 10mg/kg PO daily'
        ELSE
            'Acetaminophen 15mg/kg PO q6h PRN fever/pain'
    END ||
    '\n\nASSESSMENT AND PLAN:\n1. ' || E.PRIMARY_DIAGNOSIS || ' - ' ||
    CASE 
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Leukemia%' OR E.PRIMARY_DIAGNOSIS LIKE '%Tumor%' THEN
            'Continue current chemotherapy protocol. Monitor CBC weekly. Transfusion support as needed. ' ||
            'Infection prophylaxis with trimethoprim-sulfamethoxazole. Follow-up in oncology clinic in 1 week.'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Asthma%' THEN
            'Continue controller medications. Provided asthma action plan. Follow-up in 3 months or PRN exacerbation.'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Diabetes%' THEN
            'Continue insulin regimen. Nutrition consult recommended. Check HbA1c in 3 months. ' ||
            'Diabetes education reinforced with family.'
        WHEN E.PRIMARY_DIAGNOSIS LIKE '%Pneumonia%' THEN
            'Complete 7-day course of antibiotics. Supportive care with hydration. ' ||
            'Follow-up chest X-ray in 4-6 weeks if symptoms persist.'
        ELSE
            'Symptomatic treatment. Patient education provided. Follow-up as needed.'
    END ||
    '\n\nSigned: ' || E.ATTENDING_PROVIDER || '\nDate: ' || TO_VARCHAR(E.ENCOUNTER_DATE, 'YYYY-MM-DD HH24:MI:SS')
FROM ENCOUNTERS E
JOIN PATIENTS P ON E.PATIENT_ID = P.PATIENT_ID;

-- ----------------------------------------------------------------------------
-- 4. Laboratory Results (mimics Epic ORDER_RESULTS table)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE TABLE LAB_RESULTS (
    LAB_RESULT_ID NUMBER AUTOINCREMENT,
    ENCOUNTER_ID NUMBER,
    PATIENT_ID NUMBER,
    RESULT_DATE TIMESTAMP_NTZ,
    TEST_NAME VARCHAR(200),
    TEST_VALUE VARCHAR(100),
    REFERENCE_RANGE VARCHAR(100),
    ABNORMAL_FLAG VARCHAR(10),
    UNIT VARCHAR(50),
    PRIMARY KEY (LAB_RESULT_ID),
    FOREIGN KEY (ENCOUNTER_ID) REFERENCES ENCOUNTERS(ENCOUNTER_ID),
    FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID)
);

-- Generate lab results
INSERT INTO LAB_RESULTS (ENCOUNTER_ID, PATIENT_ID, RESULT_DATE, TEST_NAME, TEST_VALUE, REFERENCE_RANGE, ABNORMAL_FLAG, UNIT)
SELECT
    E.ENCOUNTER_ID,
    E.PATIENT_ID,
    E.ENCOUNTER_DATE,
    TEST_NAME,
    TEST_VALUE,
    REFERENCE_RANGE,
    ABNORMAL_FLAG,
    UNIT
FROM ENCOUNTERS E
CROSS JOIN (
    -- CBC panel
    SELECT 'WBC' AS TEST_NAME, CAST(UNIFORM(3, 15, RANDOM()) AS VARCHAR) AS TEST_VALUE, '5-15' AS REFERENCE_RANGE, 
           CASE WHEN UNIFORM(3, 15, RANDOM()) < 5 OR UNIFORM(3, 15, RANDOM()) > 15 THEN 'L' ELSE '' END AS ABNORMAL_FLAG, 
           'K/uL' AS UNIT
    UNION ALL
    SELECT 'Hemoglobin', CAST(UNIFORM(10, 16, RANDOM()) AS VARCHAR), '11-16', 
           CASE WHEN UNIFORM(10, 16, RANDOM()) < 11 THEN 'L' ELSE '' END, 'g/dL'
    UNION ALL
    SELECT 'Platelets', CAST(UNIFORM(150, 400, RANDOM()) AS VARCHAR), '150-400', 
           CASE WHEN UNIFORM(150, 400, RANDOM()) < 150 THEN 'L' ELSE '' END, 'K/uL'
    UNION ALL
    SELECT 'Absolute Neutrophil Count', CAST(UNIFORM(1, 8, RANDOM()) AS VARCHAR), '1.5-8', 
           CASE WHEN UNIFORM(1, 8, RANDOM()) < 1.5 THEN 'L' ELSE '' END, 'K/uL'
    UNION ALL
    -- Basic metabolic panel
    SELECT 'Glucose', CAST(UNIFORM(70, 180, RANDOM()) AS VARCHAR), '70-100', 
           CASE WHEN UNIFORM(70, 180, RANDOM()) > 100 THEN 'H' ELSE '' END, 'mg/dL'
    UNION ALL
    SELECT 'Sodium', CAST(UNIFORM(135, 145, RANDOM()) AS VARCHAR), '135-145', '', 'mmol/L'
    UNION ALL
    SELECT 'Potassium', CAST(UNIFORM(3.5, 5.0, RANDOM()) AS VARCHAR), '3.5-5.0', '', 'mmol/L'
    UNION ALL
    SELECT 'Creatinine', CAST(UNIFORM(0.3, 1.0, RANDOM()) AS VARCHAR), '0.3-1.0', '', 'mg/dL'
) AS LAB_TESTS
WHERE E.DEPARTMENT IN ('Pediatric Oncology', 'Emergency Department', 'Pediatric ICU')
    AND UNIFORM(1, 10, RANDOM()) > 3;  -- 70% get labs

-- ----------------------------------------------------------------------------
-- 5. Medications (mimics Epic ORDER_MED table)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE TABLE MEDICATIONS (
    MEDICATION_ID NUMBER AUTOINCREMENT,
    ENCOUNTER_ID NUMBER,
    PATIENT_ID NUMBER,
    ORDER_DATE TIMESTAMP_NTZ,
    MEDICATION_NAME VARCHAR(200),
    DOSE VARCHAR(50),
    ROUTE VARCHAR(20),
    FREQUENCY VARCHAR(50),
    START_DATE DATE,
    END_DATE DATE,
    ORDERING_PROVIDER VARCHAR(100),
    MEDICATION_CLASS VARCHAR(100),
    PRIMARY KEY (MEDICATION_ID),
    FOREIGN KEY (ENCOUNTER_ID) REFERENCES ENCOUNTERS(ENCOUNTER_ID),
    FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID)
);

-- Generate medication orders
INSERT INTO MEDICATIONS (ENCOUNTER_ID, PATIENT_ID, ORDER_DATE, MEDICATION_NAME, DOSE, ROUTE, FREQUENCY, START_DATE, END_DATE, ORDERING_PROVIDER, MEDICATION_CLASS)
SELECT
    E.ENCOUNTER_ID,
    E.PATIENT_ID,
    E.ENCOUNTER_DATE,
    MEDICATION_NAME,
    DOSE,
    ROUTE,
    FREQUENCY,
    E.ENCOUNTER_DATE,
    DATEADD(DAY, DURATION_DAYS, E.ENCOUNTER_DATE),
    E.ATTENDING_PROVIDER,
    MEDICATION_CLASS
FROM ENCOUNTERS E
CROSS JOIN (
    -- Oncology medications
    SELECT 'Vincristine' AS MEDICATION_NAME, '1.5 mg/m2' AS DOSE, 'IV' AS ROUTE, 'Weekly' AS FREQUENCY, 28 AS DURATION_DAYS, 'Chemotherapy' AS MEDICATION_CLASS
    UNION ALL SELECT 'Doxorubicin', '30 mg/m2', 'IV', 'Every 21 days', 21, 'Chemotherapy'
    UNION ALL SELECT 'Cyclophosphamide', '600 mg/m2', 'IV', 'Every 21 days', 21, 'Chemotherapy'
    UNION ALL SELECT 'Methotrexate', '15 mg/m2', 'IT', 'Every 4 weeks', 28, 'Chemotherapy'
    UNION ALL SELECT 'Ondansetron', '4 mg', 'PO', 'Q8H PRN', 7, 'Antiemetic'
    UNION ALL SELECT 'Filgrastim', '5 mcg/kg', 'SQ', 'Daily', 14, 'Growth Factor'
    -- Other pediatric medications
    UNION ALL SELECT 'Albuterol', '2 puffs', 'Inhaled', 'Q4-6H PRN', 30, 'Bronchodilator'
    UNION ALL SELECT 'Amoxicillin', '40 mg/kg/day', 'PO', 'BID', 10, 'Antibiotic'
    UNION ALL SELECT 'Ibuprofen', '10 mg/kg', 'PO', 'Q6H PRN', 5, 'NSAID'
    UNION ALL SELECT 'Acetaminophen', '15 mg/kg', 'PO', 'Q6H PRN', 5, 'Analgesic'
    UNION ALL SELECT 'Insulin Glargine', '10 units', 'SQ', 'Daily at bedtime', 90, 'Insulin'
    UNION ALL SELECT 'Levetiracetam', '500 mg', 'PO', 'BID', 90, 'Antiepileptic'
) AS MEDS
WHERE (
    (E.DEPARTMENT = 'Pediatric Oncology' AND MEDS.MEDICATION_CLASS = 'Chemotherapy')
    OR (E.DEPARTMENT != 'Pediatric Oncology' AND MEDS.MEDICATION_CLASS != 'Chemotherapy')
)
AND UNIFORM(1, 10, RANDOM()) > 2;  -- 80% get medication orders

-- ----------------------------------------------------------------------------
-- 6. Data Quality Checks and Statistics
-- ----------------------------------------------------------------------------

-- Patient statistics
SELECT 
    'PATIENTS' AS TABLE_NAME,
    COUNT(*) AS RECORD_COUNT,
    COUNT(DISTINCT PATIENT_ID) AS UNIQUE_PATIENTS,
    MIN(AGE_YEARS) AS MIN_AGE,
    MAX(AGE_YEARS) AS MAX_AGE,
    ROUND(AVG(AGE_YEARS), 1) AS AVG_AGE
FROM PATIENTS;

-- Encounter statistics
SELECT 
    'ENCOUNTERS' AS TABLE_NAME,
    COUNT(*) AS RECORD_COUNT,
    COUNT(DISTINCT PATIENT_ID) AS UNIQUE_PATIENTS,
    COUNT(DISTINCT DEPARTMENT) AS DEPARTMENTS,
    MIN(ENCOUNTER_DATE) AS EARLIEST_ENCOUNTER,
    MAX(ENCOUNTER_DATE) AS LATEST_ENCOUNTER
FROM ENCOUNTERS;

-- Department distribution
SELECT 
    DEPARTMENT,
    COUNT(*) AS ENCOUNTER_COUNT,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS PERCENTAGE
FROM ENCOUNTERS
GROUP BY DEPARTMENT
ORDER BY ENCOUNTER_COUNT DESC;

-- Diagnosis distribution (top 10)
SELECT 
    PRIMARY_DIAGNOSIS,
    COUNT(*) AS COUNT,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS PERCENTAGE
FROM ENCOUNTERS
GROUP BY PRIMARY_DIAGNOSIS
ORDER BY COUNT DESC
LIMIT 10;

-- Clinical notes statistics
SELECT 
    'CLINICAL_NOTES' AS TABLE_NAME,
    COUNT(*) AS RECORD_COUNT,
    COUNT(DISTINCT PATIENT_ID) AS UNIQUE_PATIENTS,
    ROUND(AVG(LENGTH(NOTE_TEXT)), 0) AS AVG_NOTE_LENGTH,
    MIN(LENGTH(NOTE_TEXT)) AS MIN_NOTE_LENGTH,
    MAX(LENGTH(NOTE_TEXT)) AS MAX_NOTE_LENGTH
FROM CLINICAL_NOTES;

-- Lab results statistics
SELECT 
    'LAB_RESULTS' AS TABLE_NAME,
    COUNT(*) AS RECORD_COUNT,
    COUNT(DISTINCT PATIENT_ID) AS UNIQUE_PATIENTS,
    COUNT(DISTINCT TEST_NAME) AS UNIQUE_TESTS
FROM LAB_RESULTS;

-- Medications statistics
SELECT 
    'MEDICATIONS' AS TABLE_NAME,
    COUNT(*) AS RECORD_COUNT,
    COUNT(DISTINCT PATIENT_ID) AS UNIQUE_PATIENTS,
    COUNT(DISTINCT MEDICATION_NAME) AS UNIQUE_MEDICATIONS
FROM MEDICATIONS;

/*
============================================================================
MOCK DATA CREATION COMPLETE
============================================================================

Summary:
- 1,000 pediatric patients (ages 1-18)
- ~2,700 clinical encounters
- ~2,700 clinical notes with realistic content
- ~13,000 lab results
- ~8,000 medication orders

This data mimics Clarity/Caboodle structure and is ready for ML model testing.

Next Steps:
1. Import models via Snowsight UI:
   - Follow instructions in 03_import_models_via_ui.md

2. Run use case examples:
   - 04_use_case_semantic_search.sql
   - 05_use_case_oncology_matching.sql
   - 06_use_case_entity_extraction.sql

============================================================================
*/

