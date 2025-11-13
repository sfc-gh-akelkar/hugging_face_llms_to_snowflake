# Security and Compliance Considerations for PHI Processing

## Overview
This document outlines security, privacy, and compliance considerations for deploying HuggingFace models in Snowflake to process Protected Health Information (PHI) for a pediatric hospital.

---

## 🔒 CRITICAL SECURITY ADVANTAGE: All Data Stays in Snowflake

### PHI Never Leaves Your Snowflake Account

**This is the most important security feature of this solution:**

✅ **Clinical data** → Loaded into Snowflake tables  
✅ **Model inference** → Runs in Snowpark Container Services (within your Snowflake account)  
✅ **Model storage** → Stored in Snowflake Model Registry  
✅ **Results** → Written to Snowflake tables  
✅ **APIs** → REST endpoints within Snowflake (if enabled)  

**❌ PHI is NEVER sent to:**
- External ML services
- HuggingFace APIs
- Third-party inference endpoints
- External model serving platforms

### How Models Are Deployed

When you import via Snowsight UI:
1. Snowflake downloads model files from HuggingFace **on your behalf**
2. Model is stored in **your Snowflake Model Registry**
3. Container image is built **within Snowflake infrastructure**
4. Service runs in **Snowpark Container Services** (your compute pool)
5. All inference happens **inside your Snowflake account**

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────┐
│         YOUR SNOWFLAKE ACCOUNT (BAA Covered)        │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Clinical Data (PHI)                         │  │
│  │  - PATIENTS table                            │  │
│  │  - CLINICAL_NOTES table                      │  │
│  └──────────────┬───────────────────────────────┘  │
│                 │                                   │
│                 ▼                                   │
│  ┌──────────────────────────────────────────────┐  │
│  │  Model Inference (SPCS)                      │  │
│  │  - Runs in your compute pool                 │  │
│  │  - No external API calls                     │  │
│  │  - All processing in-account                 │  │
│  └──────────────┬───────────────────────────────┘  │
│                 │                                   │
│                 ▼                                   │
│  ┌──────────────────────────────────────────────┐  │
│  │  Results (PHI)                               │  │
│  │  - Embeddings                                │  │
│  │  - Extracted entities                        │  │
│  │  - Similarity scores                         │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ← ← ← ALL DATA STAYS HERE ← ← ←                   │
└─────────────────────────────────────────────────────┘

External (HuggingFace):
  - Used ONLY for initial model download (no PHI involved)
  - Public model files only (not patient data)
  - One-time operation during import
```

### HIPAA Compliance Impact

This architecture means:
- ✅ **Data residency**: PHI stays in US/your region
- ✅ **BAA coverage**: Snowflake BAA covers entire data flow
- ✅ **Access control**: Standard Snowflake RBAC applies
- ✅ **Audit logging**: All operations in Snowflake query history
- ✅ **Encryption**: Automatic AES-256 at rest, TLS 1.2+ in transit
- ✅ **No third-party processors**: No additional BAAs needed

---

---

## Regulatory Compliance

### HIPAA Compliance
**Requirement**: All PHI must be protected according to HIPAA Security Rule

#### Administrative Safeguards
- ✅ **Business Associate Agreement (BAA)**: Ensure Snowflake BAA is signed
- ✅ **Access Controls**: Implement role-based access control (RBAC)
- ✅ **Audit Controls**: Enable query history and access logging
- ✅ **Workforce Training**: Train users on HIPAA requirements
- ✅ **Incident Response**: Establish breach notification procedures

#### Physical Safeguards
- ✅ **Snowflake Business Critical Edition**: Required for PHI
- ✅ **Data Residency**: Ensure data stays in required geographic region
- ✅ **Facility Access Controls**: Managed by Snowflake

#### Technical Safeguards
- ✅ **Encryption at Rest**: Snowflake SSE (enabled by default)
- ✅ **Encryption in Transit**: TLS 1.2+ (enforced by Snowflake)
- ✅ **Access Controls**: Multi-factor authentication required
- ✅ **Audit Logging**: Query history retained per compliance requirements
- ✅ **Automatic Logoff**: Session timeout configured

### Additional Regulations
- **HITECH**: Enhanced breach notification requirements
- **21 CFR Part 11**: If used for FDA submissions
- **State Privacy Laws**: CCPA (California), similar state laws
- **COPPA**: Additional protections for children < 13

---

## Snowflake Security Configuration

### 1. Account-Level Security

**Note**: Account-level security settings (MFA, password policies, network policies) are assumed to be configured following organizational best practices. This section focuses on application-specific security.

### 2. Database-Level Security

```sql
-- Enable change tracking for audit
ALTER DATABASE PEDIATRIC_ML 
    SET DATA_RETENTION_TIME_IN_DAYS = 7;
    
-- Note: Encryption is automatic in Snowflake
-- All data is encrypted at rest (AES-256) and in transit (TLS 1.2+)

-- Tag PII/PHI columns
CREATE TAG PHI_TAG;
CREATE TAG PII_TAG;

ALTER TABLE CLINICAL_DATA.PATIENTS 
    MODIFY COLUMN MRN SET TAG PHI_TAG = 'MRN';
ALTER TABLE CLINICAL_DATA.PATIENTS 
    MODIFY COLUMN FIRST_NAME SET TAG PII_TAG = 'Name';
ALTER TABLE CLINICAL_DATA.CLINICAL_NOTES 
    MODIFY COLUMN NOTE_TEXT SET TAG PHI_TAG = 'Clinical Notes';
```

### 3. Row-Level Security

```sql
-- Create row access policy for patient data
CREATE OR REPLACE ROW ACCESS POLICY PATIENT_ACCESS_POLICY
AS (patient_id NUMBER) RETURNS BOOLEAN ->
    CASE
        WHEN CURRENT_ROLE() = 'ACCOUNTADMIN' THEN TRUE
        WHEN CURRENT_ROLE() = 'ML_ENGINEER' THEN TRUE
        WHEN CURRENT_ROLE() = 'CLINICAL_USER' AND
             EXISTS (
                 SELECT 1 FROM USER_PATIENT_ACCESS
                 WHERE USER_NAME = CURRENT_USER()
                     AND PATIENT_ID = patient_id
             ) THEN TRUE
        ELSE FALSE
    END;

-- Apply policy to patient tables
ALTER TABLE CLINICAL_DATA.PATIENTS
    ADD ROW ACCESS POLICY PATIENT_ACCESS_POLICY ON (PATIENT_ID);

ALTER TABLE CLINICAL_DATA.CLINICAL_NOTES
    ADD ROW ACCESS POLICY PATIENT_ACCESS_POLICY ON (PATIENT_ID);
```

### 4. Column-Level Security

```sql
-- Masking policy for sensitive data
CREATE OR REPLACE MASKING POLICY MRN_MASK AS (val VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'CLINICAL_USER') THEN val
        WHEN CURRENT_ROLE() = 'ML_ENGINEER' THEN 'MRN-' || RIGHT(val, 4)
        ELSE '***-MASKED-***'
    END;

-- Apply masking policy
ALTER TABLE CLINICAL_DATA.PATIENTS 
    MODIFY COLUMN MRN SET MASKING POLICY MRN_MASK;

-- Masking for names
CREATE OR REPLACE MASKING POLICY NAME_MASK AS (val VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'CLINICAL_USER') THEN val
        ELSE LEFT(val, 1) || '***'
    END;

ALTER TABLE CLINICAL_DATA.PATIENTS 
    MODIFY COLUMN FIRST_NAME SET MASKING POLICY NAME_MASK;
ALTER TABLE CLINICAL_DATA.PATIENTS 
    MODIFY COLUMN LAST_NAME SET MASKING POLICY NAME_MASK;
```

---

## Data Handling Best Practices

### De-identification
For PoC and non-clinical use, de-identify data:

```sql
-- Create de-identified view
CREATE OR REPLACE SECURE VIEW CLINICAL_DATA.V_DEIDENTIFIED_NOTES AS
SELECT 
    NOTE_ID,
    HASH(PATIENT_ID) AS PATIENT_HASH,  -- One-way hash
    NOTE_DATE,
    NOTE_TYPE,
    DEPARTMENT,
    -- Remove PHI from text using regex (basic example)
    REGEXP_REPLACE(
        REGEXP_REPLACE(NOTE_TEXT, '\\d{3}-\\d{2}-\\d{4}', '[SSN]'),  -- SSNs
        '\\d{10}', '[PHONE]'  -- Phone numbers
    ) AS DEIDENTIFIED_TEXT
FROM CLINICAL_DATA.CLINICAL_NOTES;
```

### Data Minimization
Only process minimum necessary data:

```sql
-- Limit columns in ML views
CREATE OR REPLACE VIEW ML_RESULTS.V_ML_SAFE_NOTES AS
SELECT 
    NOTE_ID,
    HASH(PATIENT_ID) AS PATIENT_HASH,
    NOTE_TYPE,
    DEPARTMENT,
    NOTE_TEXT  -- Only for ML engineers
FROM CLINICAL_DATA.CLINICAL_NOTES
WHERE NOTE_DATE >= DATEADD(YEAR, -2, CURRENT_DATE());  -- Only recent notes
```

### Purpose Limitation
Restrict model usage to approved purposes:

```sql
-- Track model usage
CREATE TABLE ML_RESULTS.MODEL_USAGE_LOG (
    LOG_ID NUMBER AUTOINCREMENT,
    USER_NAME VARCHAR DEFAULT CURRENT_USER(),
    MODEL_NAME VARCHAR,
    PURPOSE VARCHAR,
    QUERY_TEXT VARCHAR,
    EXECUTION_TIME TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    APPROVED BOOLEAN DEFAULT FALSE
);

-- Log all model inference calls
CREATE OR REPLACE PROCEDURE LOG_MODEL_USAGE(
    model_name VARCHAR,
    purpose VARCHAR,
    query_text VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO ML_RESULTS.MODEL_USAGE_LOG (MODEL_NAME, PURPOSE, QUERY_TEXT)
    VALUES (:model_name, :purpose, :query_text);
    
    RETURN 'Usage logged';
END;
$$;
```

---

## Model Security

### Model Provenance
Track model sources and versions:

```sql
CREATE TABLE MODELS.MODEL_REGISTRY_AUDIT (
    MODEL_ID NUMBER AUTOINCREMENT,
    MODEL_NAME VARCHAR,
    MODEL_SOURCE VARCHAR,  -- e.g., 'HuggingFace'
    MODEL_VERSION VARCHAR,
    HUGGINGFACE_REPO VARCHAR,
    IMPORT_DATE TIMESTAMP_NTZ,
    IMPORTED_BY VARCHAR,
    CHECKSUM VARCHAR,  -- Verify model integrity
    APPROVED_FOR_PHI BOOLEAN DEFAULT FALSE,
    APPROVAL_DATE DATE,
    APPROVED_BY VARCHAR
);
```

### Model Validation
Ensure models don't leak PHI:

1. **Input Validation**: Sanitize inputs before model processing
2. **Output Filtering**: Check outputs for PHI leakage
3. **Differential Privacy**: Consider noise injection for aggregate queries
4. **Model Monitoring**: Track for unexpected behavior

```sql
-- Check for PHI in model outputs
CREATE OR REPLACE FUNCTION CONTAINS_PHI(text VARCHAR)
RETURNS BOOLEAN
LANGUAGE PYTHON
RUNTIME_VERSION = '3.9'
HANDLER = 'check_phi'
AS
$$
import re

def check_phi(text):
    '''
    Basic PHI detection (extend with more patterns)
    '''
    if not text:
        return False
    
    # Check for SSN pattern
    if re.search(r'\d{3}-\d{2}-\d{4}', text):
        return True
    
    # Check for phone numbers
    if re.search(r'\d{3}-\d{3}-\d{4}', text):
        return True
    
    # Check for dates (potential DOB)
    if re.search(r'\d{1,2}/\d{1,2}/\d{4}', text):
        return True
    
    return False
$$;
```

---

## Access Control Matrix

### Roles and Permissions

| Role | Access Level | Permissions | MRN Visible | PHI Access |
|------|-------------|-------------|-------------|------------|
| ACCOUNTADMIN | Full | All | Yes | Yes |
| CLINICAL_USER | Read | Query clinical data | Yes | Yes |
| ML_ENGINEER | Read/Write | Import models, run inference | Masked | Limited |
| DATA_SCIENTIST | Read | Query aggregated results | No | No |
| AUDITOR | Read | View logs and audit trails | No | No |

### Implementation

```sql
-- Clinical user role
CREATE ROLE CLINICAL_USER;
GRANT USAGE ON DATABASE PEDIATRIC_ML TO ROLE CLINICAL_USER;
GRANT USAGE ON SCHEMA CLINICAL_DATA TO ROLE CLINICAL_USER;
GRANT SELECT ON ALL TABLES IN SCHEMA CLINICAL_DATA TO ROLE CLINICAL_USER;
GRANT USAGE ON WAREHOUSE ML_INFERENCE_WH TO ROLE CLINICAL_USER;

-- ML engineer role (limited PHI access)
CREATE ROLE ML_ENGINEER;
GRANT USAGE ON DATABASE PEDIATRIC_ML TO ROLE ML_ENGINEER;
GRANT ALL ON SCHEMA MODELS TO ROLE ML_ENGINEER;
GRANT ALL ON SCHEMA ML_RESULTS TO ROLE ML_ENGINEER;
GRANT SELECT ON SCHEMA CLINICAL_DATA TO ROLE ML_ENGINEER;  -- Read-only
GRANT USAGE ON ALL WAREHOUSES TO ROLE ML_ENGINEER;

-- Data scientist role (aggregate only)
CREATE ROLE DATA_SCIENTIST;
GRANT USAGE ON DATABASE PEDIATRIC_ML TO ROLE DATA_SCIENTIST;
GRANT SELECT ON SCHEMA ML_RESULTS TO ROLE DATA_SCIENTIST;
GRANT USAGE ON WAREHOUSE ML_INFERENCE_WH TO ROLE DATA_SCIENTIST;

-- Auditor role
CREATE ROLE AUDITOR;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE AUDITOR;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ML_RESULTS TO ROLE AUDITOR;
```

---

## Audit and Monitoring

### Query History

```sql
-- Monitor PHI access
CREATE OR REPLACE VIEW SECURITY.V_PHI_ACCESS_AUDIT AS
SELECT 
    query_id,
    user_name,
    role_name,
    start_time,
    end_time,
    query_text,
    execution_status,
    rows_produced,
    warehouse_name
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text ILIKE '%CLINICAL_NOTES%'
    OR query_text ILIKE '%PATIENTS%'
ORDER BY start_time DESC;

-- Alert on suspicious activity
CREATE OR REPLACE ALERT SUSPICIOUS_PHI_ACCESS
    WAREHOUSE = ML_INFERENCE_WH
    SCHEDULE = '60 MINUTE'
IF (
    SELECT COUNT(*) 
    FROM SECURITY.V_PHI_ACCESS_AUDIT
    WHERE start_time >= DATEADD(HOUR, -1, CURRENT_TIMESTAMP())
        AND rows_produced > 10000  -- Large data export
) > 0
THEN CALL SEND_ALERT_EMAIL('security@hospital.org', 'Large PHI access detected');
```

### Access Logs

```sql
-- Track who accessed what data
CREATE TABLE SECURITY.DATA_ACCESS_LOG (
    access_id NUMBER AUTOINCREMENT,
    user_name VARCHAR,
    role_name VARCHAR,
    table_name VARCHAR,
    access_time TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    rows_accessed NUMBER,
    purpose VARCHAR,
    PRIMARY KEY (access_id)
);

-- Log access automatically (via stream)
CREATE STREAM SECURITY.ACCESS_STREAM ON TABLE CLINICAL_DATA.CLINICAL_NOTES;

CREATE TASK SECURITY.LOG_ACCESS_TASK
    WAREHOUSE = ML_INFERENCE_WH
    SCHEDULE = '5 MINUTE'
WHEN
    SYSTEM$STREAM_HAS_DATA('SECURITY.ACCESS_STREAM')
AS
    INSERT INTO SECURITY.DATA_ACCESS_LOG (
        user_name, role_name, table_name, rows_accessed
    )
    SELECT 
        CURRENT_USER(),
        CURRENT_ROLE(),
        'CLINICAL_NOTES',
        COUNT(*)
    FROM SECURITY.ACCESS_STREAM;

ALTER TASK SECURITY.LOG_ACCESS_TASK RESUME;
```

---

## Incident Response

### Breach Notification Procedure

1. **Detection**: Automated alerts, user reports, audit reviews
2. **Assessment**: Determine scope, affected patients, data types
3. **Containment**: Revoke access, disable affected accounts
4. **Notification**: 
   - Internal: CISO, Legal, Compliance
   - External: Patients (within 60 days), HHS, media if > 500 patients
5. **Remediation**: Fix vulnerabilities, update procedures
6. **Documentation**: Complete incident report

### Contact Information
```
Security Team: security@hospital.org
CISO: ciso@hospital.org
Privacy Officer: privacy@hospital.org
HHS Breach Portal: https://ocrportal.hhs.gov/ocr/breach/wizard_breach.jsf
```

---

## Checklist for Production Deployment

### Pre-Deployment
- [ ] Snowflake BAA signed
- [ ] Network policies configured
- [ ] MFA enabled for all users
- [ ] Row-level security implemented
- [ ] Column masking applied
- [ ] Audit logging enabled
- [ ] Incident response plan documented
- [ ] Security training completed

### Post-Deployment
- [ ] Regular access reviews (quarterly)
- [ ] Audit log reviews (monthly)
- [ ] Penetration testing (annually)
- [ ] Vulnerability scanning (quarterly)
- [ ] User access recertification (semi-annually)
- [ ] Model performance monitoring
- [ ] Compliance audits

### Ongoing Monitoring
- [ ] Daily: Automated alerts
- [ ] Weekly: Access log review
- [ ] Monthly: Query pattern analysis
- [ ] Quarterly: Compliance assessment
- [ ] Annually: Full security audit

---

## Additional Resources

### Snowflake Documentation
- [Snowflake HIPAA Compliance](https://docs.snowflake.com/en/user-guide/security-compliance)
- [Data Governance](https://docs.snowflake.com/en/user-guide/governance)
- [Access Control](https://docs.snowflake.com/en/user-guide/security-access-control)

### Regulatory Resources
- [HHS HIPAA](https://www.hhs.gov/hipaa/index.html)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [HITRUST CSF](https://hitrustalliance.net/hitrust-csf/)

### Training
- Snowflake Security Workshop
- HIPAA Training for Healthcare Workers
- Data Privacy Awareness Training

---

## Disclaimer

**This document provides general guidance only and does not constitute legal or compliance advice. Consult with your organization's legal, privacy, and security teams before deploying any system that processes PHI. Requirements vary by organization, jurisdiction, and use case.**

---

Last Updated: November 2025  
Version: 1.0  
Owner: ML Engineering Team  
Reviewers: CISO, Privacy Officer, Legal

