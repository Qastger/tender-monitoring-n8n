-- =============================================================
-- Этап 1: Основная таблица контрактов
-- Маппинг из реального ответа GosPlan API /fz44/contracts
-- Нотация API: полностью snake_case (не CamelCase как ожидалось)
-- =============================================================

CREATE TABLE IF NOT EXISTS contracts (
  reg_num          VARCHAR(50)   PRIMARY KEY,           -- reg_num
  purchase_number  VARCHAR(50),                         -- purchase_number
  plan_number      VARCHAR(50),                         -- plan_number
  position_number  VARCHAR(50),                         -- position_number
  subject          TEXT,                                -- subject
  price            NUMERIC(20,2),                       -- price (не contractSum!)
  currency_code    VARCHAR(10),                         -- currency_code
  stage            VARCHAR(10),                         -- stage: E, ET, EC, IN
  customer         VARCHAR(12),                         -- customer (ИНН, не объект)
  suppliers        TEXT[],                              -- suppliers[] (массив ИНН)
  ktru             TEXT[],                              -- ktru[] (КТРУ коды)
  okpd2            TEXT[],                              -- okpd2[] (ОКПД2 коды)
  region_code      INTEGER,                             -- region (КЛАДР 1-99)
  published_at     TIMESTAMPTZ,                         -- published_at
  updated_at       TIMESTAMPTZ,                         -- updated_at
  exe_start        DATE,                                -- exe_start
  exe_end          DATE,                                -- exe_end
  source           JSONB,                               -- весь объект JSON
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- Индексы для аналитики (Этап 2) и поиска аномалий (Этап 3)
CREATE INDEX IF NOT EXISTS idx_contracts_published_at  ON contracts(published_at);
CREATE INDEX IF NOT EXISTS idx_contracts_ktru          ON contracts USING GIN(ktru);
CREATE INDEX IF NOT EXISTS idx_contracts_okpd2         ON contracts USING GIN(okpd2);
CREATE INDEX IF NOT EXISTS idx_contracts_region        ON contracts(region_code);
CREATE INDEX IF NOT EXISTS idx_contracts_customer      ON contracts(customer);
CREATE INDEX IF NOT EXISTS idx_contracts_suppliers     ON contracts USING GIN(suppliers);
CREATE INDEX IF NOT EXISTS idx_contracts_stage         ON contracts(stage);
CREATE INDEX IF NOT EXISTS idx_contracts_exe_end       ON contracts(exe_end);
CREATE INDEX IF NOT EXISTS idx_contracts_price         ON contracts(price);
