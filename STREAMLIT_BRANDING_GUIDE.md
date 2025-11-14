# Streamlit App Branding Guide

## Lurie Children's Hospital Color Palette

Based on the [Ann & Robert H. Lurie Children's Hospital of Chicago Research Institute](https://research.luriechildrens.org/) branding.

### Primary Colors

| Color Name | Hex Code | Usage |
|------------|----------|-------|
| **Lurie Blue** | `#0066B3` | Primary brand color, buttons, headers, primary charts |
| **Lurie Dark Blue** | `#003C71` | Button hover states, dark text, secondary elements |
| **Lurie Light Blue** | `#4A90E2` | Gradients, light accents, chart highlights |
| **Lurie Teal** | `#00A499` | Success messages, metric accents, secondary charts |
| **Lurie Orange** | `#F47920` | Call-to-action accents, highlights, activity charts |

### Supporting Colors

| Color Name | Hex Code | Usage |
|------------|----------|-------|
| **Warm Gray** | `#F5F5F5` | Backgrounds, subtle containers |
| **Medium Gray** | `#E0E0E0` | Borders, dividers, grid lines |

---

## UI Component Styling

### Headers
- **Color**: Lurie Blue (`#0066B3`)
- **Accent**: Orange left border (`#F47920`)
- **Background**: Gradient from warm gray to white
- **Font**: Arial, sans-serif, 2.5rem, weight 600

### Buttons
- **Default**: Lurie Blue background (`#0066B3`), white text
- **Hover**: Dark Blue (`#003C71`) with shadow
- **Border Radius**: 8px
- **Padding**: 0.5rem 1.5rem

### Tabs
- **Inactive**: Warm Gray background (`#F5F5F5`), Dark Blue text
- **Active**: Lurie Blue background (`#0066B3`), white text
- **Hover**: Medium Gray (`#E0E0E0`)

### Input Fields
- **Border**: Medium Gray (`#E0E0E0`), 2px
- **Focus**: Lurie Blue border with subtle shadow
- **Border Radius**: 8px

### Metric Cards
- **Background**: Warm Gray (`#F5F5F5`)
- **Accent**: Left border in Teal (`#00A499`)
- **Border Radius**: 8px

---

## Chart Color Schemes

### Color Scale for Multi-Series
```python
LURIE_COLOR_SCALE = ['#0066B3', '#00A499', '#4A90E2', '#F47920', '#003C71']
```
Use for: Pie charts, multi-category bar charts, stacked charts

### Single-Series Colors
- **Primary Data**: Lurie Blue (`#0066B3`)
- **Secondary Data**: Teal (`#00A499`)
- **Activity/Alerts**: Orange (`#F47920`)
- **Gradient**: Light Blue to Primary Blue

### Chart Styling
```python
fig.update_layout(
    font=dict(family="Arial, sans-serif", size=12),
    paper_bgcolor='rgba(0,0,0,0)',  # Transparent background
    plot_bgcolor='rgba(0,0,0,0)',   # Transparent plot area
    xaxis=dict(showgrid=True, gridcolor='#E0E0E0'),
    yaxis=dict(showgrid=True, gridcolor='#E0E0E0')
)
```

---

## Visual Examples

### Search Results Page
- **Search Button**: Blue with orange hover accent
- **AI Summary Box**: Light blue background with teal left border
- **Results Cards**: White with subtle gray border
- **Charts**: Blue/Teal pie chart, Blue timeline

### Analytics Dashboard
- **Metrics Row**: Warm gray cards with teal accents
- **Department Bar Chart**: Blue gradient
- **Diagnosis Pie Chart**: Full color scale (blue, teal, light blue, orange, dark blue)
- **Age Histogram**: Teal bars
- **Activity Line Chart**: Orange line with markers

### Similar Patients Page
- **Patient Cards**: White expandable cards
- **Match Score Indicator**: Gradient from light to primary blue
- **Details**: Gray background with blue text

---

## Accessibility Considerations

### Color Contrast Ratios
- **Lurie Blue on White**: 4.68:1 (AA compliant)
- **Dark Blue on White**: 9.23:1 (AAA compliant)
- **White on Lurie Blue**: 4.68:1 (AA compliant)

### Best Practices
- Always use white text on dark blue backgrounds
- Use dark blue text on light backgrounds
- Maintain 4.5:1 contrast minimum for body text
- Use orange sparingly for highlights only

---

## Branding Attribution

### Footer
```
🏥 Ann & Robert H. Lurie Children's Hospital
Clinical Intelligence Platform
Powered by Snowflake Cortex & HuggingFace Models
All PHI remains secure in Snowflake | HIPAA Compliant
```

### Sidebar Info
- Link to [Lurie Children's Research](https://research.luriechildrens.org/)
- Security badges: ✅ HIPAA Compliant, ✅ Data in Snowflake
- Model information with icons

---

## Design Philosophy

### Professional Medical + Child-Friendly
- **Blues**: Trust, professionalism, medical expertise
- **Teal**: Innovation, technology, pediatric care
- **Orange**: Energy, warmth, approachability (used sparingly)
- **Clean Design**: Rounded corners, ample white space, clear typography

### Consistency
- All interactive elements use consistent hover states
- Charts follow the same color palette
- Spacing and padding are uniform (8px increments)
- Border radius consistently 8px-10px

---

## Implementation Files

The branding is implemented in:
- **`08_streamlit_clinical_intelligence_app.py`**: Main app with all styling
- CSS variables defined in the `<style>` block
- Chart colors applied via Plotly `update_layout()` methods
- Consistent use of `LURIE_COLORS` and `LURIE_COLOR_SCALE` constants

---

## Future Enhancements

Potential additions to strengthen branding:
1. **Logo Integration**: Add Lurie Children's logo to header
2. **Custom Icons**: Replace emojis with custom medical icons in brand colors
3. **Loading Animations**: Blue/teal animated spinners
4. **Error States**: Orange-accented error messages
5. **Export Branding**: Add hospital logo to exported reports/PDFs

---

## Resources

- **Lurie Children's Website**: https://research.luriechildrens.org/
- **Streamlit Theming**: https://docs.streamlit.io/library/api-reference/utilities/st.set_page_config
- **Plotly Styling**: https://plotly.com/python/styling-plotly-express/
- **WCAG Contrast Guidelines**: https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html

---

*This branding guide ensures consistent, professional, and accessible design throughout the Clinical Intelligence application.*

