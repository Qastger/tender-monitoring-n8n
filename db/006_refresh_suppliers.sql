-- =============================================================
-- Функция: Поиск поставщиков для перспективных ниш
-- Ищет по ВСЕМ регионам за последние 3 месяца
-- Ранжирует по кол-ву контрактов и географии
-- =============================================================

CREATE OR REPLACE FUNCTION refresh_supplier_candidates()
RETURNS TABLE(inserted INT, updated INT) AS $$
DECLARE
  v_inserted INT := 0;
  v_updated  INT := 0;
BEGIN
  -- Находим поставщиков для всех КТРУ из перспективных ниш
  WITH niche_ktru AS (
    SELECT DISTINCT ktru_code
    FROM target_niches
    WHERE status = 'pending'
      AND avg_dumping IS NOT NULL
  ),
  upserted AS (
    INSERT INTO supplier_candidates
      (inn, ktru_code, contracts_count, total_volume, regions_count, refreshed_at)
    SELECT
      s.inn,
      nk.ktru_code,
      COUNT(DISTINCT c.reg_num),
      COALESCE(SUM(c.price), 0),
      COUNT(DISTINCT c.region_code),
      NOW()
    FROM niche_ktru nk,
         contracts c,
         unnest(c.ktru) k(code),
         unnest(c.suppliers) s(inn)
    WHERE k.code = nk.ktru_code
      AND c.published_at >= NOW() - INTERVAL '3 months'
      AND c.price BETWEEN 10000 AND 200000
    GROUP BY s.inn, nk.ktru_code
    HAVING COUNT(DISTINCT c.reg_num) >= 2
    ON CONFLICT (inn, ktru_code) DO UPDATE SET
      contracts_count = EXCLUDED.contracts_count,
      total_volume    = EXCLUDED.total_volume,
      regions_count   = EXCLUDED.regions_count,
      refreshed_at    = NOW()
    RETURNING (xmax = 0) AS is_insert
  )
  SELECT
    COUNT(*) FILTER (WHERE is_insert),
    COUNT(*) FILTER (WHERE NOT is_insert)
  INTO v_inserted, v_updated
  FROM upserted;

  -- Помечаем ниши с найденными поставщиками как verified
  UPDATE target_niches tn SET
    status = 'verified'
  WHERE tn.status = 'pending'
    AND tn.avg_dumping IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM supplier_candidates sc
      WHERE sc.ktru_code = tn.ktru_code
    );

  RETURN QUERY SELECT v_inserted, v_updated;
END;
$$ LANGUAGE plpgsql;
