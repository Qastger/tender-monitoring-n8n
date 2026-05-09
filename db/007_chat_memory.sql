-- =============================================================
-- Этап 6: Таблица для хранения истории чата AI-агента
-- Используется нодой Postgres Chat Memory в n8n
-- =============================================================

CREATE TABLE IF NOT EXISTS n8n_chat_histories (
  id          SERIAL PRIMARY KEY,
  session_id  VARCHAR(255) NOT NULL,
  message     JSONB NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_session
  ON n8n_chat_histories(session_id);

CREATE INDEX IF NOT EXISTS idx_chat_created
  ON n8n_chat_histories(created_at);
