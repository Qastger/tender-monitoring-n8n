-- =============================================================
-- Этап 2: Аналитическая таблица статистики контрактов
-- Агрегация по: регион × классификатор (КТРУ/ОКПД2) × месяц
-- Используется Этапом 3 для поиска аномалий в новых извещениях
-- =============================================================

CREATE TABLE IF NOT EXISTS contract_stats (
  id                SERIAL PRIMARY KEY,
  region_code       INTEGER       NOT NULL,           -- КЛАДР код 1-99
  classifier_type   VARCHAR(10)   NOT NULL,           -- 'ktru' или 'okpd2'
  classifier_code   VARCHAR(50)   NOT NULL,           -- код КТРУ или ОКПД2
  period_month      DATE          NOT NULL,           -- первый день месяца
  contracts_count   INTEGER       NOT NULL DEFAULT 0, -- кол-во уникальных контрактов
  total_sum         NUMERIC(20,2),                    -- суммарная цена (RUB)
  avg_price         NUMERIC(20,2),                    -- средняя цена контракта
  stddev_price      NUMERIC(20,2),                    -- стандартное отклонение цены
  unique_suppliers  INTEGER       NOT NULL DEFAULT 0, -- кол-во уникальных поставщиков
  unique_customers  INTEGER       NOT NULL DEFAULT 0, -- кол-во уникальных заказчиков
  refreshed_at      TIMESTAMPTZ   DEFAULT NOW(),
  UNIQUE(region_code, classifier_type, classifier_code, period_month)
);

-- Индекс для быстрого поиска по региону и классификатору (Этап 3)
CREATE INDEX IF NOT EXISTS idx_stats_region_cls
  ON contract_stats(region_code, classifier_type, classifier_code);

-- Индекс для фильтрации по периоду
CREATE INDEX IF NOT EXISTS idx_stats_period
  ON contract_stats(period_month);

-- Индекс для сортировки по сумме (Google Sheets выгрузка)
CREATE INDEX IF NOT EXISTS idx_stats_total_sum
  ON contract_stats(total_sum DESC NULLS LAST);
