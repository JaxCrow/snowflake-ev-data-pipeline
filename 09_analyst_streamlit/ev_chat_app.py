import json

import streamlit as st
from snowflake.snowpark.context import get_active_session

try:
    import _snowflake
except ImportError:
    _snowflake = None


SEMANTIC_MODEL_FILE = "@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS/ev_semantic_model.yaml"
ANALYST_ENDPOINT = "/api/v2/cortex/analyst/message"


def call_analyst(question: str) -> dict:
    if _snowflake is None:
        return {"ok": False, "error": "_snowflake module is unavailable in this runtime."}

    body = {
        "semantic_model_file": SEMANTIC_MODEL_FILE,
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": question}],
            }
        ],
    }

    response = _snowflake.send_snow_api_request(
        "POST",
        ANALYST_ENDPOINT,
        {},
        {},
        body,
        {},
        30000,
    )

    status = response.get("status", 500)
    if status >= 400:
        raw_message = response.get("content", "")
        return {
            "ok": False,
            "error": f"Cortex Analyst request failed with status {status}. {raw_message}",
            "raw": response,
        }

    content = response.get("content")
    parsed = json.loads(content) if isinstance(content, str) else content
    return {"ok": True, "data": parsed}


def extract_text_and_sql(payload: dict) -> tuple[str, str]:
    text_parts = []
    sql_statement = ""

    for item in payload.get("message", {}).get("content", []):
        if item.get("type") == "text":
            text_parts.append(item.get("text", ""))
        if item.get("type") == "sql":
            sql_statement = item.get("statement", "")

    answer_text = "\n\n".join([p for p in text_parts if p])
    return answer_text, sql_statement


def fetch_pipeline_snapshot(session) -> dict:
    return session.sql(
        """
        SELECT
            (SELECT COUNT(*) FROM EV_PROJECT_DB.BRONZE.RAW_EV_DATA) AS BRONZE_RAW,
            (SELECT COUNT(*) FROM EV_PROJECT_DB.SILVER.CLEAN_EV_DATA_DT) AS SILVER_CLEAN,
            (SELECT COUNT(*) FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS) AS GOLD_FACT,
            (SELECT COALESCE(MAX(LOAD_TIMESTAMP), NULL) FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS) AS LAST_GOLD_LOAD_TS
        """
    ).collect()[0]


def is_forecast_request(question: str) -> bool:
    q = question.lower()
    keywords = ["forecast", "pronostic", "proyeccion", "projection", "predict", "predic"]
    return any(k in q for k in keywords)


def run_forecast(session, question: str):
    base_df = session.sql(
        """
        SELECT MODEL_YEAR, COUNT(*) AS REGISTRATIONS
        FROM EV_PROJECT_DB.GOLD.FACT_EV_REGISTRATIONS
        WHERE MODEL_YEAR IS NOT NULL
        GROUP BY MODEL_YEAR
        ORDER BY MODEL_YEAR
        """
    ).to_pandas()

    if base_df.empty or len(base_df) < 3:
        return {
            "ok": False,
            "message": "Not enough historical model-year points for forecasting.",
            "history": base_df,
            "forecast": None,
        }

    years = [int(y) for y in base_df["MODEL_YEAR"].tolist()]
    values = [float(v) for v in base_df["REGISTRATIONS"].tolist()]

    n = len(years)
    x_mean = sum(years) / n
    y_mean = sum(values) / n
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(years, values))
    denominator = sum((x - x_mean) ** 2 for x in years)
    slope = 0.0 if denominator == 0 else numerator / denominator
    intercept = y_mean - slope * x_mean

    horizon = 3
    last_year = max(years)
    forecast_rows = []
    for step in range(1, horizon + 1):
        y = last_year + step
        pred = max(0, int(round(intercept + slope * y)))
        forecast_rows.append({"MODEL_YEAR": y, "FORECAST_REGISTRATIONS": pred})

    forecast_df = __import__("pandas").DataFrame(forecast_rows)

    answer = (
        "Forecast generated using linear trend over registrations by MODEL_YEAR "
        f"with horizon={horizon} years."
    )

    return {
        "ok": True,
        "message": answer,
        "history": base_df,
        "forecast": forecast_df,
    }


st.set_page_config(page_title="EV Market Chat", layout="wide")
st.title("EV Market Chat")
st.caption("Cortex Analyst over curated EV data in Snowflake Gold layer.")

session = get_active_session()
snapshot = fetch_pipeline_snapshot(session)

with st.sidebar:
    st.subheader("Pipeline Status")
    st.metric("Bronze Rows", int(snapshot["BRONZE_RAW"]))
    st.metric("Silver Rows", int(snapshot["SILVER_CLEAN"]))
    st.metric("Gold Rows", int(snapshot["GOLD_FACT"]))
    st.caption(f"Last Gold Load: {snapshot['LAST_GOLD_LOAD_TS']}")

    st.subheader("Suggested Questions")
    suggestions = [
        "Top manufacturers by EV registrations",
        "BEV vs PHEV distribution",
        "Average electric range by model year",
        "Top utility providers by EV registrations",
        "Top legislative districts by EV registrations",
        "List the top counties with their county names and county codes",
        "Forecast EV registrations for next 3 years",
    ]
    for q in suggestions:
        if st.button(q, use_container_width=True):
            st.session_state["pending_question"] = q

if "chat_history" not in st.session_state:
    st.session_state["chat_history"] = []

for msg in st.session_state["chat_history"]:
    with st.chat_message(msg["role"]):
        st.markdown(msg["text"])
        if msg.get("sql"):
            with st.expander("Generated SQL"):
                st.code(msg["sql"], language="sql")
        if msg.get("df") is not None:
            st.dataframe(msg["df"], use_container_width=True)

question = st.chat_input("Ask about EV metrics, trends, counties, and market composition")
if not question and st.session_state.get("pending_question"):
    question = st.session_state.pop("pending_question")

if question:
    st.session_state["chat_history"].append({"role": "user", "text": question})
    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("assistant"):
        if is_forecast_request(question):
            with st.spinner("Generating forecast..."):
                forecast_result = run_forecast(session, question)

            if not forecast_result["ok"]:
                msg = forecast_result["message"]
                st.warning(msg)
                st.session_state["chat_history"].append({"role": "assistant", "text": msg})
            else:
                st.markdown(forecast_result["message"])
                st.subheader("Historical registrations by model year")
                st.dataframe(forecast_result["history"], use_container_width=True)
                st.subheader("Forecast (next 3 years)")
                st.dataframe(forecast_result["forecast"], use_container_width=True)
                st.line_chart(
                    forecast_result["forecast"].set_index("MODEL_YEAR"),
                    use_container_width=True,
                )
                st.session_state["chat_history"].append(
                    {
                        "role": "assistant",
                        "text": forecast_result["message"],
                        "df": forecast_result["forecast"],
                    }
                )
        else:
            with st.spinner("Thinking with Cortex Analyst..."):
                result = call_analyst(question)

            if not result["ok"]:
                error_text = f"Analyst error: {result.get('error', 'Unknown error')}"
                st.error(error_text)
                st.session_state["chat_history"].append(
                    {"role": "assistant", "text": error_text}
                )
            else:
                answer_text, generated_sql = extract_text_and_sql(result["data"])
                if not answer_text:
                    answer_text = "I generated a SQL query for this question."
                st.markdown(answer_text)

                result_df = None
                if generated_sql:
                    with st.expander("Generated SQL"):
                        st.code(generated_sql, language="sql")
                    try:
                        result_df = session.sql(generated_sql).to_pandas()
                        st.dataframe(result_df, use_container_width=True)
                    except Exception as query_exc:
                        st.warning(f"Could not run generated SQL: {query_exc}")

                st.session_state["chat_history"].append(
                    {
                        "role": "assistant",
                        "text": answer_text,
                        "sql": generated_sql,
                        "df": result_df,
                    }
                )
