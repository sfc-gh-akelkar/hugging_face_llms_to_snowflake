# Importing HuggingFace Models into Snowflake for Pediatric Hospital Use Cases

## Overview
This repository contains a complete, end-to-end solution for bringing HuggingFace AI models into Snowflake and making them accessible to clinical staff through an intuitive **Streamlit application**.

### ⭐ **RECOMMENDED**: Streamlit App for End Users
The fastest way to get value from this solution is deploying the **Streamlit Clinical Intelligence App** (`08_streamlit_clinical_intelligence_app.py`), which provides:
- 🤖 **Natural language search** - No SQL required
- 👥 **Similar patient finder** - For treatment planning
- 📊 **Interactive dashboards** - Real-time analytics
- 💊 **Entity extraction** - Structured data from notes

**All in ONE unified interface for clinical staff!**

### 🔒 Critical Security Feature
**ALL DATA STAYS IN SNOWFLAKE** - PHI never leaves your Snowflake account. Models run as Snowpark Container Services within your infrastructure. No external API calls with patient data. HIPAA compliant.

## Models & Services Included
1. **Snowflake Cortex Search** - Built-in semantic search (no model import needed!)
2. **microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224** - Biomedical image-text classification
3. **dmis-lab/biobert-v1.1** - Biomedical named entity recognition and text analysis

## Use Cases
- **Clinical Notes Semantic Search**: Find similar patient cases based on clinical notes
- **Oncology Treatment Matching**: Match pediatric oncology patients to similar historical cases
- **Medical Entity Extraction**: Extract medications, symptoms, diagnoses from clinical notes
- **Medical Image Classification**: Classify pediatric radiology images and histopathology

## Repository Structure
```
├── README.md                               # This file
├── QUICKSTART.md                           # Quick start guide
├── END_USER_CONSUMPTION_GUIDE.md           # How clinicians use the solution
│
├── 01_setup_environment.sql                # Snowflake environment setup
├── 02_create_mock_data.sql                 # Generate mock Clarity/Caboodle data
├── 03_import_models_via_ui.md              # Import models via Snowsight UI
├── 04_use_case_semantic_search.sql         # Use case: Clinical notes search
├── 05_use_case_oncology_matching.sql       # Use case: Patient similarity
├── 06_use_case_entity_extraction.sql       # Use case: NER from notes
│
├── 08_streamlit_clinical_intelligence_app.py   # ⭐ RECOMMENDED: Streamlit UI
├── 09_deploy_streamlit_app.sql                 # Deploy Streamlit app
├── 07_snowflake_intelligence_agent.sql         # Alternative: Cortex Analyst
│
├── IMPORT_GUIDE.md                         # Detailed technical guide
├── SECURITY_CONSIDERATIONS.md              # PHI handling and compliance
└── requirements.txt                        # Python dependencies (minimal)
```

## Quick Start

### Prerequisites
- Snowflake Business Critical Edition account
- ACCOUNTADMIN or role with MODEL REGISTRY privileges
- Python 3.8+ with Snowpark
- Network access to HuggingFace Hub

### Step 1: Setup Snowflake Environment
```sql
-- Run 01_setup_environment.sql
-- Creates database, schemas, warehouses, and stages
```

### Step 2: Create Mock Test Data
```sql
-- Run 02_create_mock_data.sql
-- Generates mock clinical data mimicking Clarity/Caboodle
```

### Step 3: Import Models via Snowsight UI
Follow the instructions in `03_import_models_via_ui.md` to import each model through the Snowflake UI:
1. Go to **AI & ML** → **Models** → **Import model**
2. Enter HuggingFace model handle
3. Configure and deploy

**Models to import:**
- `dmis-lab/biobert-v1.1` (entity extraction)
- `microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224` (image classification)

**Note**: Semantic search uses Cortex Search (built-in) - no model import needed!

**Time**: ~45-60 minutes total (mostly waiting for deployment)

### Step 4: Run Use Cases
```sql
-- Clinical notes semantic search
-- Run 04_use_case_semantic_search.sql

-- Oncology patient matching
-- Run 05_use_case_oncology_matching.sql

-- Entity extraction
-- Run 06_use_case_entity_extraction.sql
```

## Success Metrics
- **Import Success Rate**: 100% of models successfully imported and registered
- **Query Performance**: < 5 seconds for semantic search on 10K notes
- **Accuracy**: > 85% precision on entity extraction
- **User Adoption**: Clinicians able to run queries within 1 week of training
- **Data Coverage**: Models process 100% of text-based clinical notes

## Security & Compliance
- All data remains within Snowflake Business Critical tier
- End-to-end encryption for PHI
- Row-level security for clinical data access
- Audit logging enabled
- See `SECURITY_CONSIDERATIONS.md` for complete details

## Support
For questions or issues, refer to the detailed guides:
- `IMPORT_GUIDE.md` - Step-by-step model import instructions
- `SECURITY_CONSIDERATIONS.md` - PHI and HIPAA compliance guidance

## Next Steps After PoC
1. Validate with real de-identified clinical data
2. Fine-tune models on pediatric-specific corpus
3. Integrate with Clarity/Caboodle data pipelines
4. Set up automated model retraining workflows
5. Deploy to production with proper governance

