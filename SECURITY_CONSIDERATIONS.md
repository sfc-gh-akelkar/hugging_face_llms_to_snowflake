
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

This solution is designed to work within a HIPAA-compliant Snowflake environment:

**Key Requirements Met:**
- ✅ **Business Associate Agreement (BAA)**: Must have Snowflake BAA in place
- ✅ **Data Stays in Snowflake**: PHI never leaves your environment
- ✅ **Encryption**: Automatic AES-256 at rest, TLS 1.2+ in transit
- ✅ **Access Controls**: Leverages your existing Snowflake RBAC
- ✅ **Audit Logging**: All queries logged in Snowflake query history

**Your Responsibility:**
- Ensure Snowflake BAA is signed with Snowflake
- Configure user access controls per your organizational policies
- Implement appropriate data governance for your PHI

### Additional Regulations
- **HITECH**: Enhanced breach notification (organizational responsibility)
- **State Privacy Laws**: CCPA, state-specific requirements (organizational responsibility)

---

## Snowflake Security Configuration

### 1. Account-Level Security

**Note**: Account-level security settings (MFA, password policies, network policies) are assumed to be configured following organizational best practices. This section focuses on application-specific security.

### 2. Application Security

**Note**: Row-level security, column-level masking, de-identification, and data access policies are assumed to be configured at the organizational level following your institution's governance framework.

This solution inherits all existing security controls in your Snowflake environment.

---

## Model Security

Models imported from HuggingFace are:
- Downloaded and stored entirely within your Snowflake account
- Deployed as Snowpark Container Services in your compute pools
- Subject to your existing Snowflake access controls and governance

**Best Practice**: Review HuggingFace model cards for any security considerations specific to each model before importing.

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

