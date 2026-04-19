-- ================================================================
-- STREAMLIT APP — Chat Interface for Business Users
-- ================================================================

CREATE OR REPLACE STREAMLIT EV_PROJECT_DB.GOLD.EV_MARKET_CHAT
  ROOT_LOCATION = '@EV_PROJECT_DB.GOLD.SEMANTIC_MODELS'
  MAIN_FILE = 'ev_chat_app.py'
  QUERY_WAREHOUSE = COMPUTE_WH
  TITLE = 'EV Market Analytics Chat';
