# Detailed Guide: Importing HuggingFace Models into Snowflake Model Registry

## Overview

**🎉 Good News!** Snowflake now supports importing HuggingFace models directly through the Snowsight UI - no Python scripting required!

This guide provides comprehensive information about the import process, with a focus on the **UI-based method** which is the simplest and recommended approach.

**Official Documentation**: [Import models from external service](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/snowsight-ui#import-and-deploy-models-from-an-external-service)

## Two Import Methods

### Method 1: Snowsight UI (Recommended) ✅
- **Pros**: No code required, visual interface, automatic deployment
- **Cons**: Limited customization options
- **Best for**: Most users, production deployments, quick POCs
- **See**: `03_import_models_via_ui.md` for step-by-step instructions

### Method 2: Python/Snowpark (Advanced)
- **Pros**: Full control, automation, custom pipelines
- **Cons**: Requires Python development, more complex setup
- **Best for**: Advanced users, custom workflows, CI/CD pipelines
- **See**: This guide (sections below) for technical details

---

## Recommended Approach: Use the UI Method

For this pediatric hospital use case, **we recommend the UI method** because:
1. ✅ Faster setup (no Python environment needed)
2. ✅ Easier to demonstrate to stakeholders
3. ✅ Handles all complexity automatically
4. ✅ Creates REST APIs automatically
5. ✅ Better for POC and production

**→ Follow the instructions in `03_import_models_via_ui.md` for detailed steps.**

---

## Prerequisites (UI Method)

### Snowflake Requirements
- **Edition**: Business Critical or higher (for PHI processing)
- **Privileges Required**:
  - CREATE DATABASE
  - CREATE SCHEMA  
  - CREATE MODEL (Model Registry)
  - CREATE COMPUTE POOL
  - CREATE SERVICE
- **Compute Pool**: Required for model serving

### No Local Setup Required!
Unlike the Python method, the UI approach requires **no local installation** of:
- Python packages
- Model libraries
- HuggingFace utilities

Everything happens in Snowflake's infrastructure.

## Model Import Process

### Architecture Overview

**UI Method (Recommended):**
```
HuggingFace Hub → Snowflake → Model Registry → Container Service → REST API
```

**Python Method (Advanced):**
```
HuggingFace Hub → Local Download → Snowflake Stage → Model Registry → UDF
```

### What Happens During UI Import

When you import via Snowsight UI, Snowflake automatically:
1. **Downloads** model files from HuggingFace to Snowflake infrastructure
2. **Registers** the model in Model Registry
3. **Builds** a containerized runtime environment
4. **Deploys** as a Snowpark Container Service
5. **Creates** SQL functions and REST API endpoints
6. **Monitors** service health and availability

**Total time**: 10-20 minutes per model (depending on size)

---

## Quick Reference: Model Handles

Copy these exact handles for import:

### Model 1: sentence-transformers/all-MiniLM-L6-v2
**Handle**: `sentence-transformers/all-MiniLM-L6-v2`  
**Task**: Feature Extraction  
**Size**: ~80 MB  
**Use Case**: Semantic search of clinical notes

### Model 2: dmis-lab/biobert-v1.1
**Handle**: `dmis-lab/biobert-v1.1`  
**Task**: Token Classification  
**Size**: ~420 MB  
**Use Case**: Biomedical named entity recognition (NER)

### Model 3: microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224
**Handle**: `microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224`  
**Task**: Zero-Shot Classification  
**Size**: ~500 MB  
**Use Case**: Medical image classification (vision-language model)

**→ For detailed step-by-step import instructions, see `03_import_models_via_ui.md`**

---

## Advanced: Python Import Method (Optional)

The sections below document the Python/Snowpark method for advanced users who need:
- Automation and CI/CD integration
- Custom model preprocessing
- Fine-grained control over deployment

**Note**: Most users should use the UI method described above.

### Python Method Overview

#### Step 1: Download from HuggingFace
```python
from sentence_transformers import SentenceTransformer
import os

# Download model
model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')

# Save to local directory
model.save('models/minilm-l6-v2')
print(f"Model saved: {os.path.getsize('models/minilm-l6-v2')} bytes")
```

#### Step 2: Create Model Handler
```python
# Create model_handler.py
import pandas as pd
from sentence_transformers import SentenceTransformer

class MiniLMHandler:
    def __init__(self):
        self.model = None
    
    def load_model(self, model_dir):
        self.model = SentenceTransformer(model_dir)
        return self
    
    def predict(self, texts: pd.DataFrame) -> pd.DataFrame:
        """
        Generate embeddings for input texts
        """
        sentences = texts['TEXT'].tolist()
        embeddings = self.model.encode(sentences, convert_to_numpy=True)
        
        return pd.DataFrame({
            'EMBEDDING': embeddings.tolist()
        })
```

#### Step 3: Package and Upload to Snowflake
```python
from snowflake.snowpark import Session
from snowflake.ml.model import ModelVersion
import json

# Create Snowflake session
connection_parameters = {
    "account": "<your_account>",
    "user": "<your_user>",
    "password": "<your_password>",
    "role": "ACCOUNTADMIN",
    "warehouse": "ML_WAREHOUSE",
    "database": "PEDIATRIC_ML",
    "schema": "MODELS"
}

session = Session.builder.configs(connection_parameters).create()

# Create stage for models
session.sql("""
    CREATE STAGE IF NOT EXISTS MODEL_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Stage for HuggingFace models'
""").collect()

# Upload model files
session.file.put(
    local_file_name="models/minilm-l6-v2/*",
    stage_location="@MODEL_STAGE/minilm-l6-v2",
    auto_compress=True,
    overwrite=True
)
```

#### Step 4: Register in Model Registry
```python
from snowflake.ml.registry import ModelRegistry

registry = ModelRegistry(session=session, database_name="PEDIATRIC_ML", schema_name="MODELS")

# Register model
model_ref = registry.log_model(
    model_name="MINILM_EMBEDDINGS",
    version_name="v1",
    model_version=model,
    conda_dependencies=["sentence-transformers", "torch"],
    comment="Sentence embeddings for clinical notes semantic search"
)

print(f"Model registered: {model_ref.fully_qualified_name}")
```

#### Step 5: Create UDF for Inference
```sql
CREATE OR REPLACE FUNCTION EMBED_TEXT(text VARCHAR)
RETURNS ARRAY
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('sentence-transformers', 'torch', 'transformers')
HANDLER = 'embed'
AS
$$
from sentence_transformers import SentenceTransformer
import sys

# Load model from stage
model = None

def embed(text):
    global model
    if model is None:
        # Load model from stage
        import_dir = sys._xoptions.get("snowflake_import_directory")
        model = SentenceTransformer(f"{import_dir}/minilm-l6-v2")
    
    embedding = model.encode([text])[0]
    return embedding.tolist()
$$;
```

---

## Model 2: dmis-lab/biobert-v1.1

### Model Details
- **Type**: BERT-based biomedical NER
- **Size**: ~420 MB
- **Output**: Named entities (medications, symptoms, diseases)
- **Use Case**: Clinical entity extraction

### Import Steps

#### Step 1: Download from HuggingFace
```python
from transformers import AutoTokenizer, AutoModel
import torch

# Download model and tokenizer
model_name = "dmis-lab/biobert-v1.1"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModel.from_pretrained(model_name)

# Save locally
tokenizer.save_pretrained('models/biobert-v1.1')
model.save_pretrained('models/biobert-v1.1')

print(f"BioBERT model downloaded successfully")
```

#### Step 2: Create NER Pipeline Handler
```python
# Create biobert_handler.py
import pandas as pd
from transformers import pipeline

class BioBERTHandler:
    def __init__(self):
        self.ner_pipeline = None
    
    def load_model(self, model_dir):
        # Note: For full NER, you'd need a fine-tuned NER model
        # This example shows embedding extraction
        from transformers import AutoTokenizer, AutoModel
        self.tokenizer = AutoTokenizer.from_pretrained(model_dir)
        self.model = AutoModel.from_pretrained(model_dir)
        return self
    
    def predict(self, texts: pd.DataFrame) -> pd.DataFrame:
        """
        Extract biomedical entities from clinical text
        """
        results = []
        for text in texts['TEXT'].tolist():
            inputs = self.tokenizer(text, return_tensors="pt", 
                                   truncation=True, max_length=512)
            outputs = self.model(**inputs)
            
            # Get CLS token embedding (can be used for classification)
            cls_embedding = outputs.last_hidden_state[0][0].detach().numpy()
            results.append(cls_embedding.tolist())
        
        return pd.DataFrame({'EMBEDDING': results})
```

#### Step 3: Upload to Snowflake
```python
# Upload BioBERT model
session.file.put(
    local_file_name="models/biobert-v1.1/*",
    stage_location="@MODEL_STAGE/biobert-v1.1",
    auto_compress=True,
    overwrite=True
)

# Register in Model Registry
biobert_ref = registry.log_model(
    model_name="BIOBERT_NER",
    version_name="v1",
    model_version=model,
    conda_dependencies=["transformers", "torch"],
    comment="BioBERT for clinical entity extraction"
)
```

#### Step 4: Create UDF
```sql
CREATE OR REPLACE FUNCTION EXTRACT_ENTITIES(text VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('transformers', 'torch')
HANDLER = 'extract_entities'
AS
$$
from transformers import AutoTokenizer, AutoModel
import sys
import torch

tokenizer = None
model = None

def extract_entities(text):
    global tokenizer, model
    if tokenizer is None:
        import_dir = sys._xoptions.get("snowflake_import_directory")
        tokenizer = AutoTokenizer.from_pretrained(f"{import_dir}/biobert-v1.1")
        model = AutoModel.from_pretrained(f"{import_dir}/biobert-v1.1")
    
    # Tokenize and get embeddings
    inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
    with torch.no_grad():
        outputs = model(**inputs)
    
    # Return CLS embedding for classification
    cls_embedding = outputs.last_hidden_state[0][0].tolist()
    
    return {
        'embedding': cls_embedding[:10],  # First 10 dims for demo
        'text_length': len(text),
        'token_count': len(inputs['input_ids'][0])
    }
$$;
```

---

## Model 3: microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224

### Model Details
- **Type**: Vision-Language Model (CLIP)
- **Size**: ~500 MB
- **Input**: Images + Text labels
- **Use Case**: Medical image classification (X-rays, MRI, pathology)

### Import Steps

#### Step 1: Download from HuggingFace
```python
from open_clip import create_model_from_pretrained, get_tokenizer
from huggingface_hub import hf_hub_download
import json

# Download model files
model_path = hf_hub_download(
    repo_id="microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224",
    filename="open_clip_pytorch_model.bin",
    cache_dir="models/biomedclip"
)

config_path = hf_hub_download(
    repo_id="microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224",
    filename="open_clip_config.json",
    cache_dir="models/biomedclip"
)

print(f"BiomedCLIP downloaded to: {model_path}")
```

#### Step 2: Create Image Classification Handler
```python
# Create biomedclip_handler.py
import pandas as pd
import torch
from PIL import Image
from open_clip import create_model_from_pretrained, get_tokenizer
import io
import base64

class BiomedCLIPHandler:
    def __init__(self):
        self.model = None
        self.preprocess = None
        self.tokenizer = None
    
    def load_model(self, model_dir):
        self.model, self.preprocess = create_model_from_pretrained(
            'hf-hub:microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224'
        )
        self.tokenizer = get_tokenizer(
            'hf-hub:microsoft/BiomedCLIP-PubMedBERT_256-vit_base_patch16_224'
        )
        self.model.eval()
        return self
    
    def predict(self, data: pd.DataFrame) -> pd.DataFrame:
        """
        Classify medical images against text labels
        Input: IMAGE_BYTES (base64), LABELS (comma-separated)
        Output: CLASSIFICATION, CONFIDENCE
        """
        results = []
        
        for idx, row in data.iterrows():
            # Decode image
            image_bytes = base64.b64decode(row['IMAGE_BYTES'])
            image = Image.open(io.BytesIO(image_bytes))
            
            # Get labels
            labels = row['LABELS'].split(',')
            template = 'this is a photo of '
            
            # Prepare inputs
            image_input = self.preprocess(image).unsqueeze(0)
            text_input = self.tokenizer([template + l for l in labels], context_length=256)
            
            # Get predictions
            with torch.no_grad():
                image_features, text_features, logit_scale = self.model(image_input, text_input)
                logits = (logit_scale * image_features @ text_features.t()).softmax(dim=-1)
            
            # Get top prediction
            top_idx = logits.argmax().item()
            confidence = logits[0][top_idx].item()
            
            results.append({
                'CLASSIFICATION': labels[top_idx],
                'CONFIDENCE': confidence
            })
        
        return pd.DataFrame(results)
```

#### Step 3: Upload to Snowflake
```python
# Upload BiomedCLIP
session.file.put(
    local_file_name="models/biomedclip/*",
    stage_location="@MODEL_STAGE/biomedclip",
    auto_compress=True,
    overwrite=True
)

# Register in Model Registry
biomedclip_ref = registry.log_model(
    model_name="BIOMEDCLIP_CLASSIFIER",
    version_name="v1",
    model_version=model,
    conda_dependencies=["open-clip-torch", "torch", "transformers", "Pillow"],
    comment="BiomedCLIP for pediatric medical image classification"
)
```

---

## Testing the Models

### Test 1: Semantic Search with MiniLM
```sql
-- Find similar clinical notes
WITH note_embeddings AS (
    SELECT 
        NOTE_ID,
        NOTE_TEXT,
        EMBED_TEXT(NOTE_TEXT) AS embedding
    FROM CLINICAL_NOTES
    LIMIT 1000
)
SELECT 
    n1.NOTE_ID as source_note,
    n2.NOTE_ID as similar_note,
    COSINE_SIMILARITY(n1.embedding, n2.embedding) as similarity
FROM note_embeddings n1
CROSS JOIN note_embeddings n2
WHERE n1.NOTE_ID != n2.NOTE_ID
ORDER BY similarity DESC
LIMIT 10;
```

### Test 2: Entity Extraction with BioBERT
```sql
-- Extract entities from clinical notes
SELECT 
    NOTE_ID,
    NOTE_TEXT,
    EXTRACT_ENTITIES(NOTE_TEXT) AS entities
FROM CLINICAL_NOTES
WHERE NOTE_TYPE = 'ONCOLOGY'
LIMIT 100;
```

### Test 3: Image Classification (Conceptual)
```sql
-- Classify radiology images
-- Note: Requires image data in BINARY format
SELECT 
    IMAGE_ID,
    PATIENT_ID,
    CLASSIFY_IMAGE(
        IMAGE_BYTES,
        'chest X-ray,brain MRI,bone X-ray,CT scan'
    ) AS classification
FROM RADIOLOGY_IMAGES
WHERE PATIENT_AGE < 18
LIMIT 50;
```

---

## Troubleshooting

### Issue: Model Too Large for UDF
**Solution**: Use MODEL_REGISTRY with external functions or Snowpark Stored Procedures

### Issue: Timeout During Inference
**Solution**: Increase warehouse size or batch requests

### Issue: Package Conflicts
**Solution**: Use conda environments and specify exact versions in requirements

### Issue: Out of Memory
**Solution**: Process in smaller batches, use CPU-optimized models

---

## Performance Optimization

### 1. Batch Processing
```sql
-- Process notes in batches
CREATE OR REPLACE PROCEDURE BATCH_EMBED_NOTES(batch_size INT)
RETURNS STRING
LANGUAGE PYTHON
AS
$$
def batch_embed_notes(session, batch_size):
    # Process in chunks
    offset = 0
    while True:
        batch = session.sql(f"""
            SELECT NOTE_ID, NOTE_TEXT 
            FROM CLINICAL_NOTES 
            LIMIT {batch_size} OFFSET {offset}
        """).collect()
        
        if not batch:
            break
            
        # Process batch...
        offset += batch_size
    
    return f"Processed {offset} notes"
$$;
```

### 2. Caching Embeddings
```sql
-- Cache embeddings to avoid recomputation
CREATE TABLE CLINICAL_NOTE_EMBEDDINGS AS
SELECT 
    NOTE_ID,
    EMBED_TEXT(NOTE_TEXT) AS embedding,
    CURRENT_TIMESTAMP() AS computed_at
FROM CLINICAL_NOTES;

-- Create index for similarity search
CREATE INDEX IF NOT EXISTS idx_note_embeddings 
ON CLINICAL_NOTE_EMBEDDINGS(NOTE_ID);
```

### 3. Use Appropriate Warehouse Size
- **Small**: Testing with < 100 records
- **Medium**: Production workloads 100-10K records
- **Large/X-Large**: Batch processing > 10K records or image models

---

## Next Steps

1. ✅ Models imported and registered
2. ✅ UDFs created for inference
3. ⏭ Validate with sample data
4. ⏭ Integrate with Clarity/Caboodle pipelines
5. ⏭ Set up automated retraining
6. ⏭ Deploy to production with governance

## References
- [Snowflake Model Registry Documentation](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry)
- [HuggingFace Model Hub](https://huggingface.co/models)
- [Snowpark Python Developer Guide](https://docs.snowflake.com/en/developer-guide/snowpark/python/index)

