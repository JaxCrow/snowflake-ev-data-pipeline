-- ============================================================
-- 09_ANALYST_STREAMLIT.sql
-- Semantic model deployment + Streamlit app creation
-- ============================================================

-- Upload semantic model and Streamlit files to stage
-- (Run from workspace or CLI)
-- PUT file://ev_semantic_model.yaml @EV_PROJECT_DB.GOLD.SEMANTIC_MODELS AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://ev_chat_app.py @EV_PROJECT_DB.GOLD.SEMANTIC_MODELS AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://environment.yml @EV_PROJECT_DB.GOLD.SEMANTIC_MODELS AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Or from workspace:
-- COPY FILES INTO @EV_PROJECT_DB.GOLD.SEMANTIC_MODELS
-- FROM 'snow://workspace/USER$JAXDAMON.PUBLIC.DEFAULT$/versions/live'
-- FILES=('ev_semantic_model.yaml', 'ev_chat_app.py', 'environment.yml');

-- Create Streamlit app
CREATE OR REPLACE STREAMLIT EV_PROJECT_DB.GOLD.EV_MARKET_CHAT
  ROOT_LOCATION = '@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS'
  MAIN_FILE = 'ev_chat_app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH';
