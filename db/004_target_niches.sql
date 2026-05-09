-- =============================================================
-- Этап 3-4: Таблицы для анализа ниш, поставщиков и мониторинга
-- =============================================================

-- 1. Целевые ниши (регион × КТРУ с низкой конкуренцией)
CREATE TABLE IF NOT EXISTS target_niches (
  id                  SERIAL PRIMARY KEY,
  region_code         INTEGER       NOT NULL,
  ktru_code           VARCHAR(50)   NOT NULL,
  total_contracts     INTEGER       NOT NULL DEFAULT 0,
  unique_suppliers    INTEGER       NOT NULL DEFAULT 0,
  competition_ratio   NUMERIC(10,2),           -- contracts/suppliers (выше = меньше конкуренции)
  median_ratio        NUMERIC(10,2),           -- медиана ratio по этому КТРУ во всех регионах
  winner_inn          VARCHAR(12),             -- ИНН топ-победителя
  winner_concentration NUMERIC(5,1),           -- % побед топ-поставщика
  avg_dumping         NUMERIC(5,1),            -- средняя глубина демпинга (%)
  status              VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending / verified / toxic / risky
  refreshed_at        TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(region_code, ktru_code)
);

CREATE INDEX IF NOT EXISTS idx_niches_status ON target_niches(status);
CREATE INDEX IF NOT EXISTS idx_niches_ktru   ON target_niches(ktru_code);
CREATE INDEX IF NOT EXISTS idx_niches_ratio  ON target_niches(competition_ratio DESC);

-- 2. Кандидаты-поставщики (привязаны к КТРУ)
CREATE TABLE IF NOT EXISTS supplier_candidates (
  id                  SERIAL PRIMARY KEY,
  inn                 VARCHAR(12)   NOT NULL,
  ktru_code           VARCHAR(50)   NOT NULL,
  contracts_count     INTEGER       NOT NULL DEFAULT 0,
  total_volume        NUMERIC(20,2),           -- суммарный объём контрактов
  regions_count       INTEGER       NOT NULL DEFAULT 0,
  okpd2_groups        INTEGER       NOT NULL DEFAULT 0,  -- кол-во уникальных ОКПД2-групп (4 символа)
  is_likely_producer  BOOLEAN       DEFAULT true,
  refreshed_at        TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(inn, ktru_code)
);

CREATE INDEX IF NOT EXISTS idx_suppliers_ktru     ON supplier_candidates(ktru_code);
CREATE INDEX IF NOT EXISTS idx_suppliers_producer  ON supplier_candidates(is_likely_producer) WHERE is_likely_producer = true;
CREATE INDEX IF NOT EXISTS idx_suppliers_volume    ON supplier_candidates(total_volume DESC);

-- 3. Активные извещения (для мониторинга)
CREATE TABLE IF NOT EXISTS active_purchases (
  purchase_number     VARCHAR(30)   PRIMARY KEY,
  region_code         INTEGER,
  ktru_codes          TEXT[],
  max_price           NUMERIC(20,2),           -- НМЦК
  subject             TEXT,
  collecting_end      TIMESTAMPTZ,             -- дедлайн подачи заявок
  customer_inn        VARCHAR(12),
  first_seen_at       TIMESTAMPTZ DEFAULT NOW(),
  status              VARCHAR(20) DEFAULT 'new'  -- new / reviewed / bid / skip
);

CREATE INDEX IF NOT EXISTS idx_purchases_status ON active_purchases(status);
CREATE INDEX IF NOT EXISTS idx_purchases_ktru   ON active_purchases USING GIN(ktru_codes);

-- =============================================================
-- Функция: Обновить target_niches из contracts (Этап 1 + 2A)
-- Вызывается из n8n Postgres node
-- =============================================================
CREATE OR REPLACE FUNCTION refresh_target_niches()
RETURNS TABLE(inserted INT, updated INT) AS $$
DECLARE
  v_inserted INT := 0;
  v_updated  INT := 0;
BEGIN
  -- Шаг 1: Заполнить/обновить ниши (конкуренция)
  WITH niche_raw AS (
    SELECT
      c.region_code,
      k.code AS ktru_code,
      COUNT(DISTINCT c.reg_num) AS total_contracts,
      COUNT(DISTINCT s.inn) AS unique_suppliers
    FROM contracts c,
         unnest(c.ktru) k(code),
         unnest(c.suppliers) s(inn)
    WHERE c.published_at >= NOW() - INTERVAL '12 months'
      AND c.price >= 10000
      AND c.price <= 200000
      AND c.region_code IS NOT NULL
      AND array_length(c.ktru, 1) > 0
      AND array_length(c.suppliers, 1) > 0
    GROUP BY c.region_code, k.code
    HAVING COUNT(DISTINCT c.reg_num) >= 5
  ),
  niche_with_ratio AS (
    SELECT
      region_code,
      ktru_code,
      total_contracts,
      unique_suppliers,
      total_contracts::numeric / NULLIF(unique_suppliers, 0) AS competition_ratio
    FROM niche_raw
  ),
  medians AS (
    SELECT
      ktru_code,
      PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY competition_ratio
      ) AS median_ratio
    FROM niche_with_ratio
    GROUP BY ktru_code
    HAVING COUNT(DISTINCT region_code) >= 3
  ),
  filtered AS (
    SELECT n.*, m.median_ratio
    FROM niche_with_ratio n
    JOIN medians m ON n.ktru_code = m.ktru_code
    WHERE n.unique_suppliers <= 5
      AND n.competition_ratio > m.median_ratio * 1.5
  ),
  upserted AS (
    INSERT INTO target_niches (region_code, ktru_code, total_contracts, unique_suppliers,
                               competition_ratio, median_ratio, status, refreshed_at)
    SELECT region_code, ktru_code, total_contracts, unique_suppliers,
           competition_ratio, median_ratio, 'pending', NOW()
    FROM filtered
    ON CONFLICT (region_code, ktru_code) DO UPDATE SET
      total_contracts   = EXCLUDED.total_contracts,
      unique_suppliers  = EXCLUDED.unique_suppliers,
      competition_ratio = EXCLUDED.competition_ratio,
      median_ratio      = EXCLUDED.median_ratio,
      refreshed_at      = NOW()
    RETURNING (xmax = 0) AS is_insert
  )
  SELECT
    COUNT(*) FILTER (WHERE is_insert),
    COUNT(*) FILTER (WHERE NOT is_insert)
  INTO v_inserted, v_updated
  FROM upserted;

  -- Шаг 2: Обновить winner_concentration (Этап 2A)
  WITH winner_stats AS (
    SELECT
      tn.region_code,
      tn.ktru_code,
      s.inn,
      COUNT(*) AS wins,
      COUNT(*)::numeric / SUM(COUNT(*)) OVER(PARTITION BY tn.region_code, tn.ktru_code) * 100 AS win_pct
    FROM target_niches tn
    JOIN contracts c ON c.region_code = tn.region_code
    JOIN unnest(c.ktru) k(code) ON k.code = tn.ktru_code
    JOIN unnest(c.suppliers) s(inn) ON true
    WHERE c.published_at >= NOW() - INTERVAL '12 months'
      AND c.price >= 10000 AND c.price <= 200000
    GROUP BY tn.region_code, tn.ktru_code, s.inn
  ),
  top_winners AS (
    SELECT DISTINCT ON (region_code, ktru_code)
      region_code, ktru_code, inn AS winner_inn, win_pct
    FROM winner_stats
    ORDER BY region_code, ktru_code, win_pct DESC
  )
  UPDATE target_niches tn SET
    winner_inn = tw.winner_inn,
    winner_concentration = tw.win_pct,
    -- Автоматически помечаем токсичные (> 70% концентрация)
    status = CASE
      WHEN tw.win_pct > 70 THEN 'toxic'
      ELSE tn.status
    END
  FROM top_winners tw
  WHERE tn.region_code = tw.region_code
    AND tn.ktru_code = tw.ktru_code;

  RETURN QUERY SELECT v_inserted, v_updated;
END;
$$ LANGUAGE plpgsql;
