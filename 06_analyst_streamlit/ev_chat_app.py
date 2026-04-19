import streamlit as st
import json
import pandas as pd
from snowflake.snowpark.context import get_active_session
import _snowflake

SEMANTIC_MODEL = "@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS/ev_semantic_model.yaml"

st.set_page_config(page_title="EV Market Analytics", page_icon="⚡", layout="wide")
st.title("⚡ EV Market Analytics — Chat with Your Data")
st.caption("Ask questions about electric vehicle registrations, manufacturers, market trends, and more.")

SUGGESTED_QUESTIONS = [
    "What is the YoY growth trend in EV registrations?",
    "Which regions have the highest EV adoption rates?",
    "What is our market penetration by vehicle type (BEV vs PHEV)?",
    "Compare Tesla vs other manufacturers in market share by state",
    "What percentage of EVs are eligible for CAFV incentives?",
    "Which vehicle models are trending?",
    "What is the market share by manufacturer?",
]

if "messages" not in st.session_state:
    st.session_state.messages = []

def send_message(prompt):
    history = []
    for m in st.session_state.messages:
        expected_role = "user" if len(history) % 2 == 0 else "analyst"
        if m["role"] != expected_role:
            continue
        if m["role"] == "user":
            history.append({"role": "user", "content": [{"type": "text", "text": m["content"]}]})
        else:
            raw = m.get("raw_content", [])
            if not raw or not isinstance(raw, list):
                raw = [{"type": "text", "text": m.get("content", "")}]
            history.append({"role": "analyst", "content": raw})
    if history and history[-1]["role"] != "analyst":
        history.pop()
    request_body = {
        "messages": [
            *history,
            {"role": "user", "content": [{"type": "text", "text": prompt}]},
        ],
        "semantic_model_file": SEMANTIC_MODEL,
    }
    resp = _snowflake.send_snow_api_request(
        "POST",
        "/api/v2/cortex/analyst/message",
        {},
        {},
        request_body,
        {},
        30000,
    )
    content = resp["content"]
    if isinstance(content, str):
        parsed = json.loads(content)
    else:
        parsed = content
    if isinstance(parsed, list):
        parsed = parsed[0] if parsed else {}
    return parsed

def safe_json(val):
    if isinstance(val, dict) or isinstance(val, list):
        return val
    if isinstance(val, str) and val.strip():
        try:
            return json.loads(val)
        except (json.JSONDecodeError, ValueError):
            return val
    return val

def process_response(resp):
    if isinstance(resp, list):
        resp = resp[0] if resp else {}
    if isinstance(resp, str):
        resp = safe_json(resp)
    if isinstance(resp, str):
        return {"text": resp, "sql": None, "suggestions": [], "raw_content": []}

    message = resp.get("message", resp)
    message = safe_json(message)
    if isinstance(message, str):
        return {"text": message, "sql": None, "suggestions": [], "raw_content": []}

    content = message.get("content", [])
    content = safe_json(content)
    if isinstance(content, str):
        return {"text": content, "sql": None, "suggestions": [], "raw_content": []}

    text_parts = []
    sql_statement = None
    suggestions = []

    for block in content:
        if isinstance(block, str):
            text_parts.append(block)
            continue
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text":
            text_parts.append(block.get("text", ""))
        elif block.get("type") == "sql":
            sql_statement = block.get("statement", "")
        elif block.get("type") == "suggestions":
            suggestions = block.get("suggestions", [])

    return {
        "text": "\n\n".join(text_parts),
        "sql": sql_statement,
        "suggestions": suggestions,
        "raw_content": content,
    }

session = get_active_session()

with st.sidebar:
    st.header("📊 Key Insights")

    col1, col2 = st.columns(2)
    total = session.sql("SELECT COUNT(*) FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS").collect()[0][0]
    bev_pct = session.sql(
        "SELECT ROUND(COUNT(CASE WHEN EV_TYPE LIKE 'Battery%' THEN 1 END)*100.0/COUNT(*),1) FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS"
    ).collect()[0][0]
    col1.metric("Total EVs", f"{total:,}")
    col2.metric("BEV Share", f"{bev_pct}%")

    col3, col4 = st.columns(2)
    cafv = session.sql(
        "SELECT ROUND(COUNT(CASE WHEN CAFV_ELIGIBILITY='Clean Alternative Fuel Vehicle Eligible' THEN 1 END)*100.0/COUNT(*),1) FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS"
    ).collect()[0][0]
    makes = session.sql("SELECT COUNT(DISTINCT MAKE) FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS").collect()[0][0]
    col3.metric("CAFV Eligible", f"{cafv}%")
    col4.metric("Manufacturers", makes)

    st.divider()
    st.header("💡 Try These Questions")
    for q in SUGGESTED_QUESTIONS:
        if st.button(q, key=q, use_container_width=True):
            st.session_state.pending_question = q

for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])
        if msg.get("sql"):
            with st.expander("View SQL"):
                st.code(msg["sql"], language="sql")
        if msg.get("df") is not None and not msg["df"].empty:
            st.dataframe(msg["df"], use_container_width=True)

pending = st.session_state.pop("pending_question", None)
prompt = st.chat_input("Ask a question about EV market data...") or pending

if prompt:
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("analyst"):
        with st.spinner("Analyzing..."):
            resp = send_message(prompt)
            result = process_response(resp)

        if result["text"]:
            st.markdown(result["text"])

        df = pd.DataFrame()
        if result["sql"]:
            with st.expander("View SQL", expanded=False):
                st.code(result["sql"], language="sql")
            try:
                df = session.sql(result["sql"]).to_pandas()
                st.dataframe(df, use_container_width=True)
                if len(df.columns) >= 2 and len(df) > 1:
                    numeric_cols = df.select_dtypes(include=["number"]).columns.tolist()
                    non_numeric_cols = [c for c in df.columns if c not in numeric_cols]
                    if numeric_cols and non_numeric_cols:
                        try:
                            chart_df = df.set_index(non_numeric_cols[0])[numeric_cols[:3]]
                            st.bar_chart(chart_df)
                        except Exception:
                            pass
            except Exception as e:
                st.error(f"Error executing query: {e}")

        if result["suggestions"]:
            st.info("Here are some suggestions:")
            for s in result["suggestions"]:
                st.markdown(f"- {s}")

        st.session_state.messages.append({
            "role": "analyst",
            "content": result["text"],
            "sql": result.get("sql"),
            "df": df,
            "raw_content": result["raw_content"],
        })
