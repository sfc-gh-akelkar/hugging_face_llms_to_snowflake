# End User Consumption Guide
## How Clinicians Use These ML Models in Practice

This guide explains the **three different ways** clinicians and end users can consume the ML/AI capabilities in this solution.

---

## 🎯 **TL;DR: Which Consumption Pattern Should You Use?**

| User Type | Recommended Pattern | Tool | SQL Required? |
|-----------|-------------------|------|---------------|
| **Non-Technical Clinicians** | 🤖 Intelligence Agent | Snowsight Chat | ❌ No |
| **Clinical Informaticists** | 📊 Views & Dashboards | Tableau/Power BI | ⚠️ Minimal |
| **Data Analysts** | 💻 Direct SQL | Snowsight SQL Editor | ✅ Yes |
| **Custom Applications** | 🔌 REST API | Python/Java/Node.js | ✅ Yes |

---

## Pattern 1: 🤖 Snowflake Intelligence Agent (RECOMMENDED)

**Who**: Non-technical clinicians, nurses, pharmacists  
**What**: Natural language chat interface  
**Where**: Snowsight UI or custom app

### Setup

See `07_snowflake_intelligence_agent.sql` for complete setup.

```sql
-- Create semantic model and upload to Snowflake
-- Configure Cortex Analyst in Snowsight
-- Grant access to CLINICAL_USER role
```

### Example Queries (Natural Language)

Clinicians can ask questions like:

```
"Find all leukemia patients from the past month"

"Show me cases similar to patient MRN12345678"

"What are common side effects in patients on vincristine?"

"How many pediatric oncology patients had fever and neutropenia?"

"Find patients with symptoms similar to: fever, fatigue, low WBC"
```

### How It Works

```
Clinician Question
      ↓
Snowflake Intelligence (Cortex Analyst)
      ↓
Automatic SQL Generation
      ↓
Query Cortex Search + Tables
      ↓
Natural Language Answer
```

### Benefits

✅ **Zero SQL knowledge required**  
✅ **Fastest for ad-hoc questions**  
✅ **Contextual understanding**  
✅ **PHI stays in Snowflake**  
✅ **Conversational interface**

### Limitations

⚠️ Requires Snowflake Business Critical or Higher  
⚠️ Initial semantic model setup needed  
⚠️ Complex multi-step queries may need refinement

---

## Pattern 2: 📊 Views & BI Dashboards

**Who**: Clinical teams, administrators, quality improvement staff  
**What**: Pre-built views and dashboards  
**Where**: Tableau, Power BI, or Snowsight Dashboards

### Available Views

#### From `04_use_case_semantic_search.sql`:
```sql
-- Example: Pre-built search for common scenarios
CREATE VIEW V_RECENT_ONCOLOGY_CASES AS
SELECT 
    p.MRN,
    p.AGE_YEARS,
    e.PRIMARY_DIAGNOSIS,
    cn.NOTE_TYPE,
    cn.NOTE_DATE
FROM CLINICAL_NOTES cn
JOIN PATIENTS p ON cn.PATIENT_ID = p.PATIENT_ID
JOIN ENCOUNTERS e ON cn.ENCOUNTER_ID = e.ENCOUNTER_ID
WHERE e.DEPARTMENT = 'Pediatric Oncology'
    AND cn.NOTE_DATE >= DATEADD(DAY, -30, CURRENT_DATE());
```

#### From `05_use_case_oncology_matching.sql`:
```sql
-- Oncology patient profiles with latest notes
SELECT * FROM ML_RESULTS.ONCOLOGY_PATIENT_PROFILES;

-- Similar patient finder (stored procedure)
CALL FIND_SIMILAR_ONCOLOGY_PATIENTS(patient_id, 10);
```

### Tableau/Power BI Integration

1. **Connect** to Snowflake using CLINICAL_USER role
2. **Import** pre-built views
3. **Create** visualizations:
   - Patient similarity networks
   - Treatment pattern analysis
   - Side effect tracking dashboards
   - Case search interfaces

### Example Dashboard Components

```
┌─────────────────────────────────────────┐
│  Pediatric Oncology Dashboard           │
├─────────────────────────────────────────┤
│  [Search Bar: Enter symptoms/diagnosis]  │
│                                          │
│  Similar Patients:                       │
│  • MRN12345 - Age 8 - ALL - 92% match   │
│  • MRN23456 - Age 7 - ALL - 88% match   │
│                                          │
│  Common Treatments:                      │
│  • Vincristine (45%)                     │
│  • Doxorubicin (38%)                     │
│                                          │
│  [View Details Button]                   │
└─────────────────────────────────────────┘
```

### Benefits

✅ **Visual interface**  
✅ **Pre-built analytics**  
✅ **Scheduled refreshes**  
✅ **Team collaboration**  
✅ **Export capabilities**

### Limitations

⚠️ Fixed query patterns  
⚠️ Requires BI tool licenses  
⚠️ Less flexible than ad-hoc queries

---

## Pattern 3: 💻 Direct SQL Queries

**Who**: Data analysts, clinical informaticists with SQL knowledge  
**What**: Direct Cortex Search and model invocation  
**Where**: Snowsight SQL Editor

### Example: Semantic Search

From `04_use_case_semantic_search.sql`:

```sql
-- Find patients with specific symptoms
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CLINICAL_NOTES_SEARCH',
        '{
            "query": "fever neutropenia chemotherapy",
            "columns": ["NOTE_TEXT", "PATIENT_ID", "NOTE_DATE"],
            "filter": {"@eq": {"NOTE_TYPE": "Progress Note"}},
            "limit": 20
        }'
    )
)['results'] as results;
```

### Example: Entity Extraction with BioBERT

From `06_use_case_entity_extraction.sql`:

```sql
-- Extract medical entities from notes
SELECT 
    NOTE_ID,
    NOTE_TEXT,
    BIOBERT_NER!PREDICT(
        OBJECT_CONSTRUCT('inputs', NOTE_TEXT)
    ) AS extracted_entities
FROM CLINICAL_NOTES
WHERE NOTE_TYPE = 'Progress Note'
LIMIT 100;
```

### Example: Image Classification with BiomedCLIP

```sql
-- Classify medical images
SELECT 
    IMAGE_ID,
    BIOMEDCLIP_SERVICE!PREDICT(
        OBJECT_CONSTRUCT(
            'image', image_data,
            'text', 'pneumonia, normal chest x-ray, pleural effusion'
        )
    ) AS classification
FROM RADIOLOGY_IMAGES
LIMIT 50;
```

### Benefits

✅ **Maximum flexibility**  
✅ **Complex queries**  
✅ **Performance tuning**  
✅ **Automation/scheduling**  
✅ **Data pipeline integration**

### Limitations

⚠️ Requires SQL expertise  
⚠️ Manual query writing  
⚠️ No visual interface

---

## Pattern 4: 🔌 Application Integration (Custom Apps)

**Who**: Development teams building EMR integrations  
**What**: REST API calls to Snowflake  
**Where**: Python, Java, Node.js applications

### Example: Python Application

```python
import snowflake.connector

# Connect to Snowflake
conn = snowflake.connector.connect(
    user='CLINICAL_APP_USER',
    password='...',
    account='...',
    warehouse='ML_INFERENCE_WH',
    database='PEDIATRIC_ML',
    schema='CLINICAL_DATA'
)

# Search for similar patients
def find_similar_patients(query_text):
    cursor = conn.cursor()
    sql = """
    SELECT PARSE_JSON(
        SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
            'CLINICAL_NOTES_SEARCH',
            '{
                "query": "' || %s || '",
                "columns": ["NOTE_TEXT", "PATIENT_ID"],
                "limit": 10
            }'
        )
    )['results'] as results
    """
    cursor.execute(sql, (query_text,))
    return cursor.fetchall()

# Use in application
results = find_similar_patients("fever and neutropenia")
for row in results:
    print(f"Patient ID: {row['PATIENT_ID']}")
    print(f"Note: {row['NOTE_TEXT'][:200]}")
```

### REST API Integration

```javascript
// Node.js example
const snowflake = require('snowflake-sdk');

async function searchClinicalNotes(query) {
    const connection = snowflake.createConnection({...});
    
    const sql = `
        SELECT PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                'CLINICAL_NOTES_SEARCH',
                '{"query": "${query}", "limit": 10}'
            )
        )['results'] as results
    `;
    
    return await connection.execute({sqlText: sql});
}

// Integrate into EMR
app.get('/api/similar-cases', async (req, res) => {
    const results = await searchClinicalNotes(req.query.symptoms);
    res.json(results);
});
```

### Benefits

✅ **Seamless EMR integration**  
✅ **Custom UX**  
✅ **Workflow automation**  
✅ **Multi-system data**  
✅ **Real-time inference**

### Limitations

⚠️ Requires development resources  
⚠️ Authentication/security setup  
⚠️ Maintenance overhead

---

## 🔐 Security & Access Control

### Role-Based Access

```sql
-- CLINICAL_USER: Read-only access for clinicians
GRANT SELECT ON VIEW V_RECENT_ONCOLOGY_CASES TO ROLE CLINICAL_USER;
GRANT USAGE ON CORTEX SEARCH SERVICE CLINICAL_NOTES_SEARCH TO ROLE CLINICAL_USER;

-- ML_ENGINEER: Full access for model deployment and maintenance
GRANT ALL ON SCHEMA PEDIATRIC_ML.MODELS TO ROLE ML_ENGINEER;
GRANT USAGE ON COMPUTE POOL ML_INFERENCE_POOL TO ROLE ML_ENGINEER;
```

### PHI Protection

- ✅ **All data stays in Snowflake** (no external API calls)
- ✅ **Row-level security** (if configured at org level)
- ✅ **Column-level security** (if configured at org level)
- ✅ **Audit logging** (all queries tracked)
- ✅ **HIPAA compliance** (Snowflake Business Critical)

---

## 📊 Success Metrics by Pattern

### Intelligence Agent
- **Time to answer**: < 30 seconds
- **User satisfaction**: > 80% find relevant results
- **Adoption**: > 50% of clinical staff using weekly

### BI Dashboards
- **Dashboard views**: Track usage in Tableau/Power BI
- **Refresh frequency**: Daily or real-time
- **Data freshness**: < 1 hour lag

### Direct SQL
- **Query performance**: < 2 seconds for search
- **Result relevance**: > 70% clinically useful
- **Coverage**: Search across all notes

---

## 🚀 Getting Started Checklist

### For Non-Technical Clinicians
- [ ] Get Snowsight access with CLINICAL_USER role
- [ ] Complete Cortex Analyst training (30 min)
- [ ] Try example natural language queries
- [ ] Bookmark Snowsight URL
- [ ] Provide feedback on query results

### For Clinical Informaticists
- [ ] Connect Tableau/Power BI to Snowflake
- [ ] Import pre-built views
- [ ] Create team dashboards
- [ ] Schedule data refreshes
- [ ] Train clinical staff on dashboards

### For Data Analysts
- [ ] Learn Cortex Search syntax
- [ ] Review use case SQL scripts (04, 05, 06)
- [ ] Create custom queries for your needs
- [ ] Set up automated reports
- [ ] Monitor query performance

### For Development Teams
- [ ] Set up Snowflake connector in application
- [ ] Implement authentication
- [ ] Create API endpoints
- [ ] Build user interface
- [ ] Deploy and test integration

---

## 📚 Additional Resources

- **Cortex Search Documentation**: [docs.snowflake.com/cortex-search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
- **Cortex Analyst Guide**: [docs.snowflake.com/cortex-analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
- **Model Registry**: [docs.snowflake.com/model-registry](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry)
- **Example Queries**: See `04_use_case_semantic_search.sql`
- **Setup Guide**: See `QUICKSTART.md`

---

## ❓ FAQ

**Q: Which pattern should we start with?**  
A: Start with **Intelligence Agent** for non-technical users, **BI Dashboards** for clinical teams.

**Q: Can we use multiple patterns together?**  
A: Yes! Use Intelligence Agent for ad-hoc queries, dashboards for regular reporting, and SQL for custom analysis.

**Q: Does PHI leave Snowflake?**  
A: No. All processing happens within your Snowflake account. No data sent to external APIs.

**Q: How do we add more clinical scenarios?**  
A: Update the semantic model YAML, add new views, or create custom SQL queries.

**Q: What if search results aren't relevant?**  
A: Refine your query, adjust filters, or tune the Cortex Search service parameters.

**Q: How much does this cost?**  
A: Costs depend on compute usage (warehouse credits) and Cortex feature usage. Intelligence Agent requires Business Critical edition.

---

**Next Steps**: Choose your consumption pattern and follow the relevant setup guide!

