-- =============================================================
-- Промежуточная таблица: результаты проверки демпинга
-- Хранит данные о НМЦК vs цена контракта для расчёта avg_dumping
-- =============================================================

CREATE TABLE IF NOT EXISTS dumping_checks (
  purchase_number VARCHAR(30)  PRIMARY KEY,
  niche_id        INTEGER      REFERENCES target_niches(id) ON DELETE CASCADE,
  max_price       NUMERIC(20,2),  -- НМЦК из API
  contract_price  NUMERIC(20,2),  -- цена контракта из БД
  dumping_pct     NUMERIC(5,1),   -- (max_price - contract_price) / max_price * 100
  checked_at      TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dc_niche ON dumping_checks(niche_id);
