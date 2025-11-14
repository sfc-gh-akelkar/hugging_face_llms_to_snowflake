"""
Pediatric Clinical Intelligence App
====================================
A Streamlit app combining chatbot and dashboarding for clinical search and analysis.

Runs in Snowflake (Streamlit in Snowflake) - all PHI stays within Snowflake.

Features:
- Natural language clinical search
- Patient similarity finder
- Treatment pattern analysis
- Entity extraction visualization
- Interactive dashboards
"""

import streamlit as st
import pandas as pd
import json
from snowflake.snowpark.context import get_active_session
import plotly.express as px
import plotly.graph_objects as go

# Get Snowflake session (automatically available in Streamlit in Snowflake)
session = get_active_session()

# ============================================================================
# PAGE CONFIG
# ============================================================================

st.set_page_config(
    page_title="Pediatric Clinical Intelligence",
    page_icon="🏥",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for Lurie Children's Hospital branding
st.markdown("""
<style>
    /* Lurie Children's color palette */
    :root {
        --lurie-blue: #0066B3;
        --lurie-dark-blue: #003C71;
        --lurie-light-blue: #4A90E2;
        --lurie-teal: #00A499;
        --lurie-orange: #F47920;
        --lurie-warm-gray: #F5F5F5;
        --lurie-medium-gray: #E0E0E0;
    }
    
    /* Main header styling */
    .main-header {
        font-size: 2.5rem;
        color: var(--lurie-blue);
        font-weight: 600;
        text-align: center;
        padding: 1.5rem;
        background: linear-gradient(135deg, var(--lurie-warm-gray) 0%, #ffffff 100%);
        border-radius: 10px;
        margin-bottom: 1.5rem;
        border-left: 5px solid var(--lurie-orange);
    }
    
    /* Sidebar styling */
    .css-1d391kg {
        background-color: var(--lurie-warm-gray);
    }
    
    /* Button styling */
    .stButton > button {
        background-color: var(--lurie-blue);
        color: white;
        border-radius: 8px;
        border: none;
        padding: 0.5rem 1.5rem;
        font-weight: 500;
        transition: all 0.3s ease;
    }
    
    .stButton > button:hover {
        background-color: var(--lurie-dark-blue);
        box-shadow: 0 4px 8px rgba(0, 102, 179, 0.3);
    }
    
    /* Metric cards */
    .css-1xarl3l {
        background-color: var(--lurie-warm-gray);
        border-left: 4px solid var(--lurie-teal);
        border-radius: 8px;
        padding: 1rem;
    }
    
    /* Info boxes */
    .stAlert {
        border-radius: 8px;
        border-left: 4px solid var(--lurie-blue);
    }
    
    /* Chat messages */
    .chat-message {
        padding: 1.2rem;
        border-radius: 10px;
        margin: 1rem 0;
        border-left: 4px solid var(--lurie-teal);
    }
    
    .user-message {
        background-color: #E3F2FD;
        border-left-color: var(--lurie-blue);
    }
    
    .assistant-message {
        background-color: var(--lurie-warm-gray);
        border-left-color: var(--lurie-orange);
    }
    
    /* Success message styling */
    .stSuccess {
        background-color: #E8F5E9;
        border-left: 4px solid var(--lurie-teal);
        border-radius: 8px;
    }
    
    /* Expander styling */
    .streamlit-expanderHeader {
        background-color: var(--lurie-warm-gray);
        border-radius: 8px;
        color: var(--lurie-dark-blue);
        font-weight: 500;
    }
    
    /* Tabs styling */
    .stTabs [data-baseweb="tab-list"] {
        gap: 8px;
    }
    
    .stTabs [data-baseweb="tab"] {
        background-color: var(--lurie-warm-gray);
        border-radius: 8px 8px 0 0;
        color: var(--lurie-dark-blue);
        font-weight: 500;
        padding: 12px 24px;
    }
    
    .stTabs [data-baseweb="tab"]:hover {
        background-color: var(--lurie-medium-gray);
    }
    
    .stTabs [aria-selected="true"] {
        background-color: var(--lurie-blue);
        color: white;
    }
    
    /* Text input styling */
    .stTextInput > div > div > input {
        border-radius: 8px;
        border: 2px solid var(--lurie-medium-gray);
        padding: 0.75rem;
    }
    
    .stTextInput > div > div > input:focus {
        border-color: var(--lurie-blue);
        box-shadow: 0 0 0 2px rgba(0, 102, 179, 0.1);
    }
    
    /* Selectbox styling */
    .stSelectbox > div > div {
        border-radius: 8px;
    }
    
    /* Container borders */
    .element-container {
        border-radius: 8px;
    }
    
    /* Dataframe styling */
    .dataframe {
        border: 1px solid var(--lurie-medium-gray);
        border-radius: 8px;
    }
    
    /* Plotly charts */
    .js-plotly-plot {
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
    }
</style>
""", unsafe_allow_html=True)

# Lurie Children's color palette for charts
LURIE_COLORS = {
    'primary': '#0066B3',      # Lurie Blue
    'secondary': '#00A499',    # Lurie Teal
    'accent': '#F47920',       # Lurie Orange
    'dark': '#003C71',         # Dark Blue
    'light': '#4A90E2',        # Light Blue
    'gray': '#F5F5F5'          # Warm Gray
}

LURIE_COLOR_SCALE = ['#0066B3', '#00A499', '#4A90E2', '#F47920', '#003C71']

# ============================================================================
# SIDEBAR - NAVIGATION
# ============================================================================

st.sidebar.title("🏥 Clinical Intelligence")
st.sidebar.markdown("---")

page = st.sidebar.radio(
    "Navigation",
    ["🔍 Clinical Search", "👥 Similar Patients", "📊 Analytics Dashboard", "💊 Entity Extraction"]
)

st.sidebar.markdown("---")
st.sidebar.markdown(
    """
    ### 🏥 About This App
    
    **Pediatric Clinical Intelligence**  
    *Powered by AI & Machine Learning*
    
    **Models & Services:**
    - 🔍 Snowflake Cortex Search  
      *Semantic clinical note search*
    - 🧬 BioBERT  
      *Medical entity extraction*
    - 🖼️ BiomedCLIP  
      *Image classification*
    
    ---
    
    **🔒 Security:**  
    ✅ All data stays in Snowflake  
    ✅ HIPAA compliant  
    ✅ No external API calls with PHI
    
    ---
    
    **📚 Resources:**
    - [Lurie Children's Research](https://research.luriechildrens.org/)
    - [Snowflake Cortex](https://docs.snowflake.com/cortex)
    """
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

@st.cache_data(ttl=3600)
def search_clinical_notes(query, note_type_filter=None, limit=10):
    """Search clinical notes using Cortex Search"""
    
    filter_clause = ""
    if note_type_filter and note_type_filter != "All":
        filter_clause = f', "filter": {{"@eq": {{"NOTE_TYPE": "{note_type_filter}"}}}}'
    
    sql = f"""
    SELECT PARSE_JSON(
        SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
            'CLINICAL_NOTES_SEARCH',
            '{{
                "query": "{query}",
                "columns": ["NOTE_TEXT", "PATIENT_ID", "NOTE_TYPE", "NOTE_DATE", "AUTHOR"],
                "limit": {limit}
                {filter_clause}
            }}'
        )
    )['results'] as results
    """
    
    result = session.sql(sql).collect()
    if result and result[0]['RESULTS']:
        # Parse the JSON results
        results_json = json.loads(result[0]['RESULTS'])
        return pd.DataFrame(results_json)
    return pd.DataFrame()

@st.cache_data(ttl=3600)
def get_patient_details(patient_id):
    """Get patient demographics and recent encounters"""
    sql = f"""
    SELECT 
        p.PATIENT_ID,
        p.MRN,
        p.AGE_YEARS,
        p.GENDER,
        p.RACE,
        COUNT(DISTINCT e.ENCOUNTER_ID) as encounter_count,
        MAX(e.ENCOUNTER_DATE) as last_encounter_date,
        LISTAGG(DISTINCT e.DEPARTMENT, ', ') as departments,
        LISTAGG(DISTINCT e.PRIMARY_DIAGNOSIS, '; ') as diagnoses
    FROM PEDIATRIC_ML.CLINICAL_DATA.PATIENTS p
    LEFT JOIN PEDIATRIC_ML.CLINICAL_DATA.ENCOUNTERS e ON p.PATIENT_ID = e.PATIENT_ID
    WHERE p.PATIENT_ID = {patient_id}
    GROUP BY p.PATIENT_ID, p.MRN, p.AGE_YEARS, p.GENDER, p.RACE
    """
    return session.sql(sql).to_pandas()

@st.cache_data(ttl=3600)
def get_department_stats():
    """Get statistics by department"""
    sql = """
    SELECT 
        e.DEPARTMENT,
        COUNT(DISTINCT e.PATIENT_ID) as patient_count,
        COUNT(DISTINCT e.ENCOUNTER_ID) as encounter_count,
        COUNT(DISTINCT cn.NOTE_ID) as note_count
    FROM PEDIATRIC_ML.CLINICAL_DATA.ENCOUNTERS e
    LEFT JOIN PEDIATRIC_ML.CLINICAL_DATA.CLINICAL_NOTES cn ON e.ENCOUNTER_ID = cn.ENCOUNTER_ID
    GROUP BY e.DEPARTMENT
    ORDER BY patient_count DESC
    """
    return session.sql(sql).to_pandas()

@st.cache_data(ttl=3600)
def get_diagnosis_distribution():
    """Get distribution of primary diagnoses"""
    sql = """
    SELECT 
        PRIMARY_DIAGNOSIS,
        COUNT(*) as count
    FROM PEDIATRIC_ML.CLINICAL_DATA.ENCOUNTERS
    GROUP BY PRIMARY_DIAGNOSIS
    ORDER BY count DESC
    LIMIT 10
    """
    return session.sql(sql).to_pandas()

def generate_ai_summary(query, search_results):
    """Generate AI summary of search results using Cortex Complete"""
    if search_results.empty:
        return "No results found for your query."
    
    # Take top 3 results
    top_results = search_results.head(3)
    context = "\n\n".join([
        f"Note {i+1}: {row['NOTE_TEXT'][:500]}"
        for i, row in top_results.iterrows()
    ])
    
    prompt = f"""Based on the following clinical notes, provide a concise summary answering the query: "{query}"

Clinical Notes:
{context}

Summary:"""
    
    sql = f"""
    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'llama3-70b',
        '{prompt.replace("'", "''")}'
    ) as summary
    """
    
    result = session.sql(sql).collect()
    return result[0]['SUMMARY'] if result else "Unable to generate summary."

# ============================================================================
# PAGE 1: CLINICAL SEARCH
# ============================================================================

if page == "🔍 Clinical Search":
    st.markdown('<h1 class="main-header">🔍 Clinical Search</h1>', unsafe_allow_html=True)
    
    st.markdown("""
    Search clinical notes using natural language. The system will find semantically similar cases
    even if they don't use the exact same words.
    """)
    
    # Search interface
    col1, col2 = st.columns([3, 1])
    
    with col1:
        search_query = st.text_input(
            "Enter your search query",
            placeholder="e.g., fever and neutropenia in leukemia patients",
            help="Use natural language to describe symptoms, diagnoses, or treatments"
        )
    
    with col2:
        note_type_filter = st.selectbox(
            "Note Type",
            ["All", "Progress Note", "H&P Note", "Discharge Summary", "Consultation Note"]
        )
    
    col3, col4 = st.columns([1, 4])
    with col3:
        num_results = st.slider("Number of results", 5, 50, 10)
    
    with col4:
        if st.button("🔍 Search", type="primary", use_container_width=True):
            if search_query:
                with st.spinner("Searching clinical notes..."):
                    results = search_clinical_notes(
                        search_query,
                        note_type_filter if note_type_filter != "All" else None,
                        num_results
                    )
                    
                    if not results.empty:
                        st.success(f"Found {len(results)} matching notes")
                        
                        # AI Summary
                        with st.expander("🤖 AI Summary", expanded=True):
                            summary = generate_ai_summary(search_query, results)
                            st.info(summary)
                        
                        # Results tabs
                        tab1, tab2 = st.tabs(["📋 Search Results", "📊 Analysis"])
                        
                        with tab1:
                            for idx, row in results.iterrows():
                                with st.container():
                                    col_a, col_b, col_c = st.columns([1, 2, 1])
                                    
                                    with col_a:
                                        st.metric("Patient ID", row['PATIENT_ID'])
                                    
                                    with col_b:
                                        st.caption(f"**{row['NOTE_TYPE']}** | {row['NOTE_DATE']} | {row['AUTHOR']}")
                                    
                                    with col_c:
                                        if st.button("View Details", key=f"detail_{idx}"):
                                            st.session_state[f'show_details_{idx}'] = True
                                    
                                    # Note preview
                                    note_preview = row['NOTE_TEXT'][:400] + "..." if len(row['NOTE_TEXT']) > 400 else row['NOTE_TEXT']
                                    st.text_area("Note Content", note_preview, height=150, key=f"note_{idx}")
                                    
                                    # Patient details if requested
                                    if st.session_state.get(f'show_details_{idx}', False):
                                        patient_info = get_patient_details(row['PATIENT_ID'])
                                        if not patient_info.empty:
                                            st.dataframe(patient_info, use_container_width=True)
                                    
                                    st.markdown("---")
                        
                        with tab2:
                            # Visualize results
                            st.subheader("Results by Note Type")
                            note_type_counts = results['NOTE_TYPE'].value_counts()
                            fig = px.pie(
                                values=note_type_counts.values,
                                names=note_type_counts.index,
                                color_discrete_sequence=LURIE_COLOR_SCALE
                            )
                            fig.update_layout(
                                font=dict(family="Arial, sans-serif", size=12),
                                paper_bgcolor='rgba(0,0,0,0)',
                                plot_bgcolor='rgba(0,0,0,0)'
                            )
                            st.plotly_chart(fig, use_container_width=True)
                            
                            st.subheader("Results Timeline")
                            results['NOTE_DATE'] = pd.to_datetime(results['NOTE_DATE'])
                            timeline_data = results.groupby(results['NOTE_DATE'].dt.date).size().reset_index()
                            timeline_data.columns = ['Date', 'Count']
                            fig2 = px.line(
                                timeline_data,
                                x='Date',
                                y='Count',
                                markers=True,
                                color_discrete_sequence=[LURIE_COLORS['primary']]
                            )
                            fig2.update_layout(
                                font=dict(family="Arial, sans-serif", size=12),
                                paper_bgcolor='rgba(0,0,0,0)',
                                plot_bgcolor='rgba(0,0,0,0)',
                                xaxis=dict(showgrid=True, gridcolor='#E0E0E0'),
                                yaxis=dict(showgrid=True, gridcolor='#E0E0E0')
                            )
                            st.plotly_chart(fig2, use_container_width=True)
                    
                    else:
                        st.warning("No results found. Try a different query or adjust filters.")
            else:
                st.error("Please enter a search query")

# ============================================================================
# PAGE 2: SIMILAR PATIENTS
# ============================================================================

elif page == "👥 Similar Patients":
    st.markdown('<h1 class="main-header">👥 Similar Patient Finder</h1>', unsafe_allow_html=True)
    
    st.markdown("""
    Find patients with similar clinical presentations for treatment planning and outcome prediction.
    """)
    
    # Patient input
    col1, col2 = st.columns([2, 1])
    
    with col1:
        patient_search = st.text_input(
            "Enter Patient MRN or ID",
            placeholder="e.g., MRN00000001 or Patient ID: 1"
        )
    
    with col2:
        max_similar = st.slider("Max similar patients", 5, 20, 10)
    
    if st.button("Find Similar Patients", type="primary"):
        if patient_search:
            with st.spinner("Finding similar patients..."):
                # Extract patient ID
                patient_id = None
                if patient_search.isdigit():
                    patient_id = int(patient_search)
                elif "MRN" in patient_search.upper():
                    mrn = patient_search.replace("MRN", "").strip()
                    sql = f"SELECT PATIENT_ID FROM PEDIATRIC_ML.CLINICAL_DATA.PATIENTS WHERE MRN = '{mrn}'"
                    result = session.sql(sql).collect()
                    if result:
                        patient_id = result[0]['PATIENT_ID']
                
                if patient_id:
                    # Get index patient details
                    index_patient = get_patient_details(patient_id)
                    
                    if not index_patient.empty:
                        st.subheader("Index Patient")
                        col_a, col_b, col_c, col_d = st.columns(4)
                        with col_a:
                            st.metric("MRN", index_patient['MRN'].values[0])
                        with col_b:
                            st.metric("Age", f"{index_patient['AGE_YEARS'].values[0]} years")
                        with col_c:
                            st.metric("Gender", index_patient['GENDER'].values[0])
                        with col_d:
                            st.metric("Encounters", index_patient['ENCOUNTER_COUNT'].values[0])
                        
                        st.markdown("---")
                        
                        # Get latest note for similarity search
                        sql_latest_note = f"""
                        SELECT NOTE_TEXT 
                        FROM PEDIATRIC_ML.CLINICAL_DATA.CLINICAL_NOTES
                        WHERE PATIENT_ID = {patient_id}
                        ORDER BY NOTE_DATE DESC
                        LIMIT 1
                        """
                        latest_note = session.sql(sql_latest_note).collect()
                        
                        if latest_note:
                            note_text = latest_note[0]['NOTE_TEXT']
                            
                            # Search for similar notes
                            similar_results = search_clinical_notes(note_text[:500], None, max_similar * 2)
                            
                            # Filter out index patient
                            similar_results = similar_results[similar_results['PATIENT_ID'] != patient_id]
                            
                            if not similar_results.empty:
                                st.subheader(f"Top {min(max_similar, len(similar_results))} Similar Patients")
                                
                                # Group by patient
                                similar_patients = similar_results.groupby('PATIENT_ID').first().reset_index()
                                similar_patients = similar_patients.head(max_similar)
                                
                                for idx, row in similar_patients.iterrows():
                                    with st.expander(f"Patient {row['PATIENT_ID']} - {row['NOTE_TYPE']}"):
                                        patient_details = get_patient_details(row['PATIENT_ID'])
                                        if not patient_details.empty:
                                            col_x, col_y = st.columns(2)
                                            with col_x:
                                                st.write(f"**MRN:** {patient_details['MRN'].values[0]}")
                                                st.write(f"**Age:** {patient_details['AGE_YEARS'].values[0]} years")
                                                st.write(f"**Gender:** {patient_details['GENDER'].values[0]}")
                                            with col_y:
                                                st.write(f"**Encounters:** {patient_details['ENCOUNTER_COUNT'].values[0]}")
                                                st.write(f"**Last Visit:** {patient_details['LAST_ENCOUNTER_DATE'].values[0]}")
                                        
                                        st.text_area("Similar Note", row['NOTE_TEXT'][:300], height=100, key=f"similar_{idx}")
                            else:
                                st.warning("No similar patients found")
                        else:
                            st.warning("No clinical notes found for this patient")
                    else:
                        st.error("Patient not found")
                else:
                    st.error("Invalid patient ID or MRN")
        else:
            st.error("Please enter a patient MRN or ID")

# ============================================================================
# PAGE 3: ANALYTICS DASHBOARD
# ============================================================================

elif page == "📊 Analytics Dashboard":
    st.markdown('<h1 class="main-header">📊 Clinical Analytics Dashboard</h1>', unsafe_allow_html=True)
    
    # Summary metrics
    st.subheader("Overview")
    
    sql_summary = """
    SELECT 
        COUNT(DISTINCT p.PATIENT_ID) as total_patients,
        COUNT(DISTINCT e.ENCOUNTER_ID) as total_encounters,
        COUNT(DISTINCT cn.NOTE_ID) as total_notes,
        MAX(cn.NOTE_DATE) as latest_note
    FROM PEDIATRIC_ML.CLINICAL_DATA.PATIENTS p
    LEFT JOIN PEDIATRIC_ML.CLINICAL_DATA.ENCOUNTERS e ON p.PATIENT_ID = e.PATIENT_ID
    LEFT JOIN PEDIATRIC_ML.CLINICAL_DATA.CLINICAL_NOTES cn ON e.ENCOUNTER_ID = cn.ENCOUNTER_ID
    """
    summary = session.sql(sql_summary).to_pandas()
    
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Total Patients", f"{summary['TOTAL_PATIENTS'].values[0]:,}")
    with col2:
        st.metric("Total Encounters", f"{summary['TOTAL_ENCOUNTERS'].values[0]:,}")
    with col3:
        st.metric("Clinical Notes", f"{summary['TOTAL_NOTES'].values[0]:,}")
    with col4:
        st.metric("Latest Note", summary['LATEST_NOTE'].values[0])
    
    st.markdown("---")
    
    # Department statistics
    col_a, col_b = st.columns(2)
    
    with col_a:
        st.subheader("Patients by Department")
        dept_stats = get_department_stats()
        fig_dept = px.bar(
            dept_stats,
            x='DEPARTMENT',
            y='PATIENT_COUNT',
            color='PATIENT_COUNT',
            color_continuous_scale=[[0, LURIE_COLORS['light']], [1, LURIE_COLORS['primary']]]
        )
        fig_dept.update_layout(
            showlegend=False,
            font=dict(family="Arial, sans-serif", size=12),
            paper_bgcolor='rgba(0,0,0,0)',
            plot_bgcolor='rgba(0,0,0,0)',
            xaxis=dict(showgrid=False),
            yaxis=dict(showgrid=True, gridcolor='#E0E0E0')
        )
        st.plotly_chart(fig_dept, use_container_width=True)
    
    with col_b:
        st.subheader("Top 10 Diagnoses")
        diagnosis_dist = get_diagnosis_distribution()
        fig_dx = px.pie(
            diagnosis_dist,
            values='COUNT',
            names='PRIMARY_DIAGNOSIS',
            hole=0.4,
            color_discrete_sequence=LURIE_COLOR_SCALE
        )
        fig_dx.update_layout(
            font=dict(family="Arial, sans-serif", size=12),
            paper_bgcolor='rgba(0,0,0,0)',
            plot_bgcolor='rgba(0,0,0,0)'
        )
        st.plotly_chart(fig_dx, use_container_width=True)
    
    # Age distribution
    st.subheader("Patient Age Distribution")
    sql_age = """
    SELECT AGE_YEARS, COUNT(*) as count
    FROM PEDIATRIC_ML.CLINICAL_DATA.PATIENTS
    GROUP BY AGE_YEARS
    ORDER BY AGE_YEARS
    """
    age_data = session.sql(sql_age).to_pandas()
    fig_age = px.histogram(
        age_data,
        x='AGE_YEARS',
        y='COUNT',
        nbins=18,
        color_discrete_sequence=[LURIE_COLORS['secondary']]
    )
    fig_age.update_layout(
        xaxis_title="Age (years)",
        yaxis_title="Patient Count",
        font=dict(family="Arial, sans-serif", size=12),
        paper_bgcolor='rgba(0,0,0,0)',
        plot_bgcolor='rgba(0,0,0,0)',
        xaxis=dict(showgrid=False),
        yaxis=dict(showgrid=True, gridcolor='#E0E0E0')
    )
    st.plotly_chart(fig_age, use_container_width=True)
    
    # Recent activity
    st.subheader("Recent Clinical Activity (Last 30 Days)")
    sql_activity = """
    SELECT 
        DATE(NOTE_DATE) as date,
        COUNT(*) as note_count
    FROM PEDIATRIC_ML.CLINICAL_DATA.CLINICAL_NOTES
    WHERE NOTE_DATE >= DATEADD(DAY, -30, CURRENT_DATE())
    GROUP BY DATE(NOTE_DATE)
    ORDER BY date
    """
    activity_data = session.sql(sql_activity).to_pandas()
    fig_activity = px.line(
        activity_data,
        x='DATE',
        y='NOTE_COUNT',
        markers=True,
        color_discrete_sequence=[LURIE_COLORS['accent']]
    )
    fig_activity.update_layout(
        xaxis_title="Date",
        yaxis_title="Notes Created",
        font=dict(family="Arial, sans-serif", size=12),
        paper_bgcolor='rgba(0,0,0,0)',
        plot_bgcolor='rgba(0,0,0,0)',
        xaxis=dict(showgrid=True, gridcolor='#E0E0E0'),
        yaxis=dict(showgrid=True, gridcolor='#E0E0E0')
    )
    st.plotly_chart(fig_activity, use_container_width=True)

# ============================================================================
# PAGE 4: ENTITY EXTRACTION
# ============================================================================

elif page == "💊 Entity Extraction":
    st.markdown('<h1 class="main-header">💊 Medical Entity Extraction</h1>', unsafe_allow_html=True)
    
    st.markdown("""
    Extract structured medical information (medications, symptoms, diagnoses) from clinical notes
    using BioBERT NER model.
    """)
    
    # Input method
    input_method = st.radio("Input Method", ["Paste Clinical Note", "Search Existing Note"])
    
    if input_method == "Paste Clinical Note":
        note_text = st.text_area(
            "Clinical Note Text",
            height=200,
            placeholder="Paste clinical note text here..."
        )
        
        if st.button("Extract Entities", type="primary") and note_text:
            with st.spinner("Extracting entities with BioBERT..."):
                # Call BioBERT model
                sql = f"""
                SELECT PEDIATRIC_ML.MODELS.BIOBERT_NER!PREDICT(
                    OBJECT_CONSTRUCT('inputs', '{note_text.replace("'", "''")}')
                ) as entities
                """
                try:
                    result = session.sql(sql).collect()
                    if result:
                        entities = json.loads(result[0]['ENTITIES'])
                        
                        st.success("Extraction complete!")
                        
                        # Display entities
                        if entities:
                            st.subheader("Extracted Entities")
                            
                            # Group by entity type
                            entity_df = pd.DataFrame(entities)
                            if not entity_df.empty and 'entity_group' in entity_df.columns:
                                for entity_type in entity_df['entity_group'].unique():
                                    with st.expander(f"📌 {entity_type}", expanded=True):
                                        type_entities = entity_df[entity_df['entity_group'] == entity_type]
                                        for _, ent in type_entities.iterrows():
                                            st.write(f"- **{ent['word']}** (confidence: {ent['score']:.2%})")
                            else:
                                st.info("No entities extracted")
                        else:
                            st.info("No entities found")
                except Exception as e:
                    st.error(f"Error calling BioBERT model: {str(e)}")
                    st.info("Make sure BioBERT model is deployed and accessible.")
    
    else:  # Search Existing Note
        search_term = st.text_input("Search for note", placeholder="e.g., leukemia chemotherapy")
        
        if st.button("Search") and search_term:
            results = search_clinical_notes(search_term, None, 5)
            
            if not results.empty:
                st.subheader("Select a note to analyze")
                
                selected_note_idx = st.selectbox(
                    "Choose note",
                    range(len(results)),
                    format_func=lambda i: f"Patient {results.iloc[i]['PATIENT_ID']} - {results.iloc[i]['NOTE_TYPE']} - {results.iloc[i]['NOTE_DATE']}"
                )
                
                selected_note = results.iloc[selected_note_idx]
                st.text_area("Note Content", selected_note['NOTE_TEXT'], height=200)
                
                if st.button("Extract Entities from This Note", type="primary"):
                    with st.spinner("Extracting entities..."):
                        st.info("BioBERT entity extraction would run here. Model must be deployed first.")
                        # Similar extraction logic as above

# ============================================================================
# FOOTER
# ============================================================================

st.sidebar.markdown("---")
st.sidebar.markdown(
    """
    <div style='text-align: center; color: #0066B3; font-size: 0.85rem;'>
        <strong>🏥 Ann & Robert H. Lurie Children's Hospital</strong><br>
        <span style='color: #666;'>Clinical Intelligence Platform</span><br>
        <span style='font-size: 0.75rem; color: #999;'>
            Powered by Snowflake Cortex & HuggingFace Models<br>
            All PHI remains secure in Snowflake | HIPAA Compliant
        </span>
    </div>
    """,
    unsafe_allow_html=True
)

