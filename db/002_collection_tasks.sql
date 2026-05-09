-- =============================================================
-- Этап 1: Трекер прогресса сбора (round-robin пагинация)
-- 99 регионов × 14 месяцев (2025-01..2026-02) = 1 386 задач
-- Порядок: ORDER BY current_skip, region_code, month_start
--   → сначала все комбо при skip=0, потом все при skip=100, и т.д.
-- =============================================================

CREATE TABLE IF NOT EXISTS collection_tasks (
  id                SERIAL PRIMARY KEY,
  region_code       INTEGER       NOT NULL,    -- КЛАДР код 1-99
  month_start       DATE          NOT NULL,    -- первый день месяца
  month_end         DATE          NOT NULL,    -- последний день месяца
  current_skip      INTEGER       NOT NULL DEFAULT 0,
  status            VARCHAR(20)   NOT NULL DEFAULT 'pending',  -- pending / done
  records_collected INTEGER       NOT NULL DEFAULT 0,
  updated_at        TIMESTAMPTZ            DEFAULT NOW(),
  UNIQUE (region_code, month_start)
);

-- Индекс для быстрого выбора следующей задачи (round-robin)
CREATE INDEX IF NOT EXISTS idx_tasks_status_priority
  ON collection_tasks(status, current_skip, region_code, month_start)
  WHERE status = 'pending';

-- =============================================================
-- Seed: заполнить все 1 386 комбинаций (если таблица пуста)
-- Запускать один раз вручную или через n8n при старте
-- =============================================================
INSERT INTO collection_tasks (region_code, month_start, month_end)
SELECT
  r.n AS region_code,
  d.month_start::date,
  (d.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end
FROM generate_series(1, 99) AS r(n)
CROSS JOIN (
  SELECT generate_series(
    '2025-01-01'::date,
    '2026-02-01'::date,
    INTERVAL '1 month'
  ) AS month_start
) AS d
ON CONFLICT (region_code, month_start) DO NOTHING;

-- Проверка
-- SELECT status, count(*), sum(records_collected) FROM collection_tasks GROUP BY status;
