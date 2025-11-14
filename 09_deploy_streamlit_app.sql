-- ============================================================================
-- Deploy Streamlit Clinical Intelligence App
-- ============================================================================
-- Purpose: Deploy the Streamlit app to Snowflake for clinician access
-- Benefit: Single unified interface for chat + dashboards + search
-- ============================================================================

USE ROLE ML_ENGINEER;
USE DATABASE PEDIATRIC_ML;
USE WAREHOUSE ML_INFERENCE_WH;

-- ----------------------------------------------------------------------------
-- Step 1: Create Streamlit App in Snowflake
-- ----------------------------------------------------------------------------

-- Create the Streamlit app
CREATE STREAMLIT IF NOT EXISTS PEDIATRIC_ML.CLINICAL_DATA.CLINICAL_INTELLIGENCE_APP
    ROOT_LOCATION = '@PEDIATRIC_ML.CLINICAL_DATA.STREAMLIT_STAGE'
    MAIN_FILE = '08_streamlit_clinical_intelligence_app.py'
    QUERY_WAREHOUSE = 'ML_INFERENCE_WH'
    TITLE = 'Pediatric Clinical Intelligence'
    COMMENT = 'Unified clinical search, patient matching, and analytics interface';

-- Create stage for Streamlit app files
CREATE STAGE IF NOT EXISTS STREAMLIT_STAGE
    COMMENT = 'Stage for Streamlit app files';

-- ----------------------------------------------------------------------------
-- Step 2: Upload Streamlit App File
-- ----------------------------------------------------------------------------

/*
Upload the Python file to the stage:

Method 1: Via Snowsight UI
1. Go to Data -> Databases -> PEDIATRIC_ML -> CLINICAL_DATA -> Stages
2. Click on STREAMLIT_STAGE
3. Click "Upload Files"
4. Upload 08_streamlit_clinical_intelligence_app.py

Method 2: Via SnowSQL
PUT file://08_streamlit_clinical_intelligence_app.py @PEDIATRIC_ML.CLINICAL_DATA.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

Method 3: Via Python (Snowpark)
session.file.put(
    "08_streamlit_clinical_intelligence_app.py",
    "@PEDIATRIC_ML.CLINICAL_DATA.STREAMLIT_STAGE",
    auto_compress=False,
    overwrite=True
)
*/

-- Verify file upload
LIST @STREAMLIT_STAGE;

-- ----------------------------------------------------------------------------
-- Step 3: Grant Access Permissions
-- ----------------------------------------------------------------------------

-- Grant usage on warehouse to both roles
GRANT USAGE ON WAREHOUSE ML_INFERENCE_WH TO ROLE CLINICAL_USER;
GRANT USAGE ON WAREHOUSE ML_INFERENCE_WH TO ROLE ML_ENGINEER;

-- Grant access to Cortex Search service
GRANT USAGE ON CORTEX SEARCH SERVICE CLINICAL_NOTES_SEARCH TO ROLE CLINICAL_USER;

-- Grant Cortex functions access (for AI summaries)
GRANT USAGE ON FUNCTION SNOWFLAKE.CORTEX.COMPLETE TO ROLE CLINICAL_USER;
GRANT USAGE ON FUNCTION SNOWFLAKE.CORTEX.SEARCH_PREVIEW TO ROLE CLINICAL_USER;

-- Grant read access to clinical data
GRANT SELECT ON ALL TABLES IN SCHEMA PEDIATRIC_ML.CLINICAL_DATA TO ROLE CLINICAL_USER;
GRANT SELECT ON ALL VIEWS IN SCHEMA PEDIATRIC_ML.CLINICAL_DATA TO ROLE CLINICAL_USER;
GRANT SELECT ON ALL TABLES IN SCHEMA PEDIATRIC_ML.ML_RESULTS TO ROLE CLINICAL_USER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA PEDIATRIC_ML.CLINICAL_DATA TO ROLE CLINICAL_USER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA PEDIATRIC_ML.CLINICAL_DATA TO ROLE CLINICAL_USER;

-- Grant Streamlit app access
GRANT USAGE ON STREAMLIT CLINICAL_INTELLIGENCE_APP TO ROLE CLINICAL_USER;

-- ----------------------------------------------------------------------------
-- Step 4: Test and Verify Deployment
-- ----------------------------------------------------------------------------

-- Show Streamlit apps
SHOW STREAMLITS IN SCHEMA PEDIATRIC_ML.CLINICAL_DATA;

-- Get Streamlit app URL
DESC STREAMLIT CLINICAL_INTELLIGENCE_APP;

-- ----------------------------------------------------------------------------
-- Step 5: Access Instructions for Clinical Staff
-- ----------------------------------------------------------------------------

/*
============================================================================
ACCESSING THE STREAMLIT APP
============================================================================

## For Clinicians (CLINICAL_USER role):

### Method 1: Snowsight UI
1. Log into Snowsight: https://app.snowflake.com
2. Navigate to: Projects -> Streamlit
3. Click on "Pediatric Clinical Intelligence"
4. The app will load in your browser

### Method 2: Direct URL
1. Get the URL from DESC STREAMLIT command above
2. Bookmark the URL for quick access
3. Share with clinical team

## App Features:

### 🔍 Clinical Search Tab
- Enter natural language queries
- Get AI-powered summaries
- Filter by note type
- View patient details

Example queries:
- "fever and neutropenia in leukemia patients"
- "vincristine side effects"
- "acute lymphoblastic leukemia treatment"

### 👥 Similar Patients Tab
- Enter patient MRN or ID
- Find patients with similar presentations
- View demographics and encounter history
- Useful for treatment planning

### 📊 Analytics Dashboard Tab
- Overview metrics (patients, encounters, notes)
- Department statistics
- Diagnosis distribution
- Age distribution
- Recent activity trends

### 💊 Entity Extraction Tab
- Paste clinical note text
- Extract structured entities (medications, symptoms)
- Or search existing notes and analyze
- Uses BioBERT NER model

## Security Features:
✅ All data stays in Snowflake
✅ Role-based access control
✅ Audit logging
✅ HIPAA compliant

## Support:
Contact Clinical Informatics team for access or issues.

============================================================================
*/

-- ----------------------------------------------------------------------------
-- Step 6: Optional - Create Shortcuts/Views for Common Queries
-- ----------------------------------------------------------------------------

-- Create a view for oncology clinicians
CREATE OR REPLACE VIEW CLINICAL_DATA.V_ONCOLOGY_QUICK_SEARCH AS
SELECT 
    p.MRN,
    p.AGE_YEARS,
    p.GENDER,
    e.PRIMARY_DIAGNOSIS,
    cn.NOTE_DATE,
    cn.NOTE_TYPE,
    cn.NOTE_TEXT
FROM CLINICAL_NOTES cn
JOIN PATIENTS p ON cn.PATIENT_ID = p.PATIENT_ID
JOIN ENCOUNTERS e ON cn.ENCOUNTER_ID = e.ENCOUNTER_ID
WHERE e.DEPARTMENT = 'Pediatric Oncology'
    AND cn.NOTE_DATE >= DATEADD(MONTH, -6, CURRENT_DATE());

GRANT SELECT ON VIEW CLINICAL_DATA.V_ONCOLOGY_QUICK_SEARCH TO ROLE CLINICAL_USER;

-- ----------------------------------------------------------------------------
-- Step 7: Monitoring and Maintenance
-- ----------------------------------------------------------------------------

-- Monitor Streamlit app usage
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.STREAMLITS_USAGE_HISTORY
WHERE STREAMLIT_NAME = 'CLINICAL_INTELLIGENCE_APP'
ORDER BY START_TIME DESC
LIMIT 100;

-- Monitor query performance
SELECT 
    QUERY_TEXT,
    EXECUTION_TIME,
    WAREHOUSE_NAME,
    USER_NAME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TEXT LIKE '%CLINICAL_NOTES_SEARCH%'
    AND START_TIME >= DATEADD(DAY, -7, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 100;

-- Check Cortex Search service health
SHOW CORTEX SEARCH SERVICES;
DESC CORTEX SEARCH SERVICE CLINICAL_NOTES_SEARCH;

-- ----------------------------------------------------------------------------
-- Step 8: Update and Redeploy (When Making Changes)
-- ----------------------------------------------------------------------------

/*
To update the Streamlit app after making code changes:

1. Upload new version of Python file:
   PUT file://08_streamlit_clinical_intelligence_app.py @STREAMLIT_STAGE OVERWRITE=TRUE;

2. The app will automatically refresh for users
   (Streamlit in Snowflake auto-detects file changes)

3. No need to recreate the Streamlit object unless changing:
   - Root location
   - Main file name
   - Warehouse
   - Permissions
*/

-- ----------------------------------------------------------------------------
-- Troubleshooting
-- ----------------------------------------------------------------------------

/*
Common Issues and Solutions:

1. "Access Denied" Error
   - Check role grants: SHOW GRANTS TO ROLE CLINICAL_USER;
   - Ensure user has CLINICAL_USER role: SHOW GRANTS TO USER <username>;
   - Grant role if missing: GRANT ROLE CLINICAL_USER TO USER <username>;

2. "Warehouse Not Found" Error
   - Ensure ML_INFERENCE_WH exists: SHOW WAREHOUSES;
   - Grant usage: GRANT USAGE ON WAREHOUSE ML_INFERENCE_WH TO ROLE CLINICAL_USER;

3. "Cortex Search Service Not Found"
   - Check service exists: SHOW CORTEX SEARCH SERVICES;
   - Recreate if missing: Run 04_use_case_semantic_search.sql Step 1

4. App Not Loading
   - Check file uploaded: LIST @STREAMLIT_STAGE;
   - Verify app created: SHOW STREAMLITS;
   - Check Python syntax errors in app file

5. Slow Performance
   - Increase warehouse size: ALTER WAREHOUSE ML_INFERENCE_WH SET WAREHOUSE_SIZE = 'MEDIUM';
   - Check query history for bottlenecks
   - Add caching to frequently used queries

6. BioBERT Model Not Available
   - Check model service: SHOW SERVICES IN COMPUTE POOL ML_INFERENCE_POOL;
   - Ensure model deployed: See 03_import_models_via_ui.md
   - Restart service if needed: ALTER SERVICE BIOBERT_NER_SERVICE RESUME;
*/

/*
============================================================================
STREAMLIT APP DEPLOYMENT COMPLETE
============================================================================

Next Steps:
1. Share app URL with clinical staff
2. Provide training (15-30 minutes per user)
3. Gather feedback on search relevance and UX
4. Iterate on app features based on user needs
5. Monitor usage and performance

Benefits Over Other Approaches:
✅ Single interface for all features (no switching tools)
✅ No SQL knowledge required
✅ Custom UX tailored to clinical workflows
✅ Combines chat + dashboards + search
✅ Faster than teaching multiple tools
✅ Better adoption with intuitive interface
✅ Still 100% secure (all data in Snowflake)

============================================================================
*/

