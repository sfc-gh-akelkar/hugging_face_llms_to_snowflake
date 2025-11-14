# Importing HuggingFace Models via Snowsight UI

## Overview
Snowflake now supports importing models directly from HuggingFace through the Snowsight UI - no Python scripts needed! This is the simplest and recommended method for importing models.

**Reference**: [Snowflake Documentation - Import models from external service](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/snowsight-ui#import-and-deploy-models-from-an-external-service)

## 🔒 Critical Security Consideration

**ALL DATA STAYS IN SNOWFLAKE**

When you import models via UI:
1. ✅ Snowflake downloads models from HuggingFace **on your behalf** (no PHI involved)
2. ✅ Models are deployed in **your Snowflake account** (Snowpark Container Services)
3. ✅ All inference happens **within your infrastructure**
4. ✅ **PHI never sent to external services** (HuggingFace, external APIs, etc.)
5. ✅ Covered by **your Snowflake BAA**

This architecture is critical for HIPAA compliance - patient data never leaves your Snowflake environment.

---

## Prerequisites

1. **Snowflake Business Critical Edition** (for PHI processing)
2. **Compute Pool** for model serving
3. **Appropriate Role** with MODEL REGISTRY privileges
4. **Completed Setup** - Run `01_setup_environment.sql` first

### Create Compute Pool (One-Time Setup)

```sql
-- Create compute pool for model serving
USE ROLE ACCOUNTADMIN;

CREATE COMPUTE POOL ML_INFERENCE_POOL
    MIN_NODES = 1
    MAX_NODES = 3
    INSTANCE_FAMILY = CPU_X64_S
    AUTO_RESUME = TRUE
    AUTO_SUSPEND_SECS = 600
    COMMENT = 'Compute pool for HuggingFace model inference';

-- Grant access
GRANT USAGE, MONITOR ON COMPUTE POOL ML_INFERENCE_POOL TO ROLE ML_ENGINEER;
```

---

## ⭐ Semantic Search: Use Cortex Search (No Import Needed!)

For semantic search of clinical notes, use **Snowflake Cortex Search** instead of importing a model:

```sql
-- Create Cortex Search Service (see 04_use_case_semantic_search.sql for full example)
CREATE CORTEX SEARCH SERVICE CLINICAL_NOTES_SEARCH
ON NOTE_TEXT
WAREHOUSE = ML_INFERENCE_WH
TARGET_LAG = '1 hour'
AS (
    SELECT NOTE_ID, PATIENT_ID, NOTE_TEXT, DEPARTMENT, PRIMARY_DIAGNOSIS
    FROM CLINICAL_DATA.CLINICAL_NOTES
);
```

**Benefits:**
- ✅ No model import needed
- ✅ Automatic embeddings and indexing
- ✅ Simpler queries
- ✅ Better performance
- ✅ Auto-refreshes when data changes

---

## Model 1: dmis-lab/biobert-v1.1

### Purpose
- **Use Case**: Biomedical entity extraction, clinical NLP
- **Output**: Named entities (medications, symptoms, diagnoses)
- **Task Type**: Token Classification (for NER)

### Import Steps

1. **Navigate to Models**
   - In Snowsight, go to **AI & ML** → **Models**
   - Click **Import model**

2. **Configure Model Import**
   
   **Model Details:**
   - **Model handle**: `dmis-lab/biobert-v1.1`
   - **Task**: Select **Token Classification**
   - **Trust remote code**: Leave unchecked
   - **Hugging Face token secret**: Leave empty (public model)

3. **Registry Settings**
   
   - **Model name**: `BIOBERT_NER`
   - **Version name**: `v1`
   - **Database**: `PEDIATRIC_ML`
   - **Schema**: `MODELS`
   
   **Advanced Settings:**
   - **Comment**: `BioBERT for clinical entity extraction from pediatric notes`

4. **Deployment Configuration**
   
   - **Service name**: `BIOBERT_NER_SERVICE`
   - **Create REST API endpoint**: ✅ Check this
   - **Compute pool**: Select `ML_INFERENCE_POOL`
   - **Number of instances**: `1`
   
   **Advanced Settings:**
   - ✅ **Accept Snowflake's default settings**
   - Snowflake optimizes these based on the model and compute pool
   - Only adjust if you have specific performance issues after testing
   - Settings can be modified later through ALTER SERVICE

5. **Deploy**
   - Click **Deploy**
   - Deployment takes 10-15 minutes

---

## Model 2: microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224

### Purpose
- **Use Case**: Medical image classification (X-rays, MRI, pathology)
- **Output**: Image classifications with confidence scores
- **Task Type**: Zero-Shot Classification (CLIP-based vision-language model)

### Import Steps

1. **Navigate to Models**
   - In Snowsight, go to **AI & ML** → **Models**
   - Click **Import model**

2. **Configure Model Import**
   
   **Model Details:**
   - **Model handle**: `microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224`
   - **Task**: Select **Zero-Shot Classification**
   - **Trust remote code**: Leave unchecked
   - **Hugging Face token secret**: Leave empty (public model)

3. **Registry Settings**
   
   - **Model name**: `BIOMEDCLIP_CLASSIFIER`
   - **Version name**: `v1`
   - **Database**: `PEDIATRIC_ML`
   - **Schema**: `MODELS`
   
   **Advanced Settings:**
   - **Pip requirements**: 
     - Add: `open-clip-torch>=2.23.0`
     - Add: `Pillow>=10.0.0`
   - **Comment**: `BiomedCLIP for pediatric medical image classification`

4. **Deployment Configuration**
   
   - **Service name**: `BIOMEDCLIP_SERVICE`
   - **Create REST API endpoint**: ✅ Check this
   - **Compute pool**: Select `ML_INFERENCE_POOL`
   - **Number of instances**: `1`
   
   **Advanced Settings:**
   - ✅ **Accept Snowflake's default settings**
   - Snowflake optimizes these based on the model and compute pool
   - Only adjust if you have specific performance issues after testing
   - Settings can be modified later through ALTER SERVICE

5. **Deploy**
   - Click **Deploy**
   - Deployment takes 15-20 minutes (larger model)

---

## Monitoring Deployment

### View Deployment Progress

1. **Check Query History**
   - Go to **Monitoring** → **Query History**
   - Find the query with `SYSTEM$DEPLOY_MODEL`
   - Check status and any error messages

2. **Monitor Jobs**
   - Go to **Monitoring** → **Services & jobs**
   - Look for jobs named:
     - `MODEL_DEPLOY_*` (model download and registration)
     - `MODEL_BUILD_*` (container image build)
   - Select the job and view **Logs** tab

3. **Check Service Status**
   - Go to **AI & ML** → **Models**
   - Select your model
   - Go to **Inference Services** tab
   - Status should show **Running** when complete

### Troubleshooting

**Deployment fails:**
- Check compute pool is running: `SHOW COMPUTE POOLS;`
- Verify sufficient resources in compute pool
- Review error logs in Query History
- Ensure correct model handle (check HuggingFace for exact name)

**Service shows as "Pending":**
- This is normal - deployment can take 15-20 minutes
- Check the `MODEL_BUILD_*` job logs for progress
- Container image is being built in the background

**Out of Memory errors:**
- First, verify you're using Snowflake's default settings (they are pre-optimized)
- If still occurring, increase memory allocation in Advanced Settings
- Or reduce number of workers/max batch rows
- Consider using larger compute pool instance family

---

## Testing the Deployed Models

### Get Model Function Names

```sql
-- Show functions created by the model
USE DATABASE PEDIATRIC_ML;
USE SCHEMA MODELS;

-- List all functions in the schema
SHOW FUNCTIONS IN SCHEMA MODELS;

-- Or query information schema
SELECT 
    FUNCTION_NAME,
    ARGUMENT_SIGNATURE,
    DATA_TYPE
FROM INFORMATION_SCHEMA.FUNCTIONS
WHERE FUNCTION_SCHEMA = 'MODELS'
ORDER BY CREATED DESC;
```

### Test BioBERT Token Classification

```sql
-- Extract features from clinical text
SELECT BIOBERT_NER!PREDICT(
    OBJECT_CONSTRUCT(
        'inputs', 'Patient diagnosed with acute lymphoblastic leukemia. Prescribed vincristine and doxorubicin.'
    )
) AS biobert_features;
```

### Test BiomedCLIP (if you have image data)

```sql
-- Classify medical image
-- Note: Requires image data in base64 format
SELECT BIOMEDCLIP_CLASSIFIER!PREDICT(
    OBJECT_CONSTRUCT(
        'image', TO_VARCHAR(image_base64),
        'candidate_labels', ARRAY_CONSTRUCT(
            'chest X-ray normal',
            'chest X-ray pneumonia',
            'brain MRI'
        )
    )
) AS classification
FROM RADIOLOGY_IMAGES
LIMIT 1;
```

---

## Create User-Friendly UDFs (Optional)

The deployed services create functions with names like `MODELNAME!PREDICT`. You can create simpler wrapper functions:

```sql
-- Wrapper for BioBERT entity extraction
CREATE OR REPLACE FUNCTION EXTRACT_BIOMEDICAL_ENTITIES(text VARCHAR)
RETURNS VARIANT
AS
$$
    SELECT BIOBERT_NER!PREDICT(
        OBJECT_CONSTRUCT('inputs', text)
    )
$$;

-- Test the wrapper
SELECT EXTRACT_BIOMEDICAL_ENTITIES('Patient with leukemia on vincristine and prednisone') AS entities;
```

---

## Managing Deployed Services

### View Service Status

```sql
-- Show all services
SHOW SERVICES IN COMPUTE POOL ML_INFERENCE_POOL;

-- Get service details
DESCRIBE SERVICE BIOBERT_NER_SERVICE;
DESCRIBE SERVICE BIOMEDCLIP_SERVICE;
```

### Suspend/Resume Services

```sql
-- Suspend service to save costs when not in use
ALTER SERVICE BIOBERT_NER_SERVICE SUSPEND;

-- Resume service when needed
ALTER SERVICE BIOBERT_NER_SERVICE RESUME;
```

### Update Service Configuration

```sql
-- Scale up instances for higher load
ALTER SERVICE BIOBERT_NER_SERVICE 
    SET MIN_INSTANCES = 2, MAX_INSTANCES = 5;

-- Modify compute pool if needed
ALTER SERVICE BIOBERT_NER_SERVICE
    SET COMPUTE POOL = ML_INFERENCE_POOL;
```

---

## Cost Optimization Tips

1. **Auto-Suspend**: Set aggressive auto-suspend on compute pools (600 seconds)
2. **Right-Size Resources**: Start small, scale up only if needed
3. **Suspend When Not in Use**: Manually suspend services during non-business hours
4. **Share Compute Pool**: Multiple models can share the same compute pool
5. **Batch Requests**: Process multiple items in one call rather than many individual calls

```sql
-- Check compute pool usage
SELECT * FROM TABLE(
    INFORMATION_SCHEMA.COMPUTE_POOL_USAGE_HISTORY(
        COMPUTE_POOL_NAME => 'ML_INFERENCE_POOL',
        START_TIME => DATEADD(DAY, -7, CURRENT_TIMESTAMP())
    )
);
```

---

## Summary: What You've Deployed

✅ **Model 1: MiniLM** - Semantic search and text embeddings  
✅ **Model 2: BioBERT** - Biomedical entity extraction  
✅ **Model 3: BiomedCLIP** - Medical image classification

**Total Setup Time**: ~45-60 minutes (including deployment wait time)

**Next Steps**:
1. Run the use case SQL files (06-08) to see these models in action
2. Create wrapper functions for easier usage
3. Integrate with your Clarity/Caboodle data pipelines
4. Monitor usage and optimize resources

---

## Additional Resources

- [Snowflake Model Registry Documentation](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry)
- [Snowpark Container Services](https://docs.snowflake.com/en/developer-guide/snowpark-container-services)
- [HuggingFace Model Hub](https://huggingface.co/models)
- [Model Serving in SPCS](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/model-serving)

---

**Questions?** The UI-based import is significantly simpler than the Python approach. If you encounter issues, check the Query History and job logs in the Monitoring section.

