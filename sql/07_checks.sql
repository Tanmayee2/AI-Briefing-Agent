-- 07_checks.sql: deterministic facts (snapshot, thresholds, risks) and the lookups the agent can call.
-- Facts are computed here in SQL; the agent explains them, it does not calculate them.
-- Procedures take an as-of date so you can backfill history (see ops.backfill_snapshots).
-- NOTE: written without access to a live account. Run it, and let Cortex Code fix any syntax issues.

USE DATABASE cos;
USE WAREHOUSE cos_wh;

CREATE OR REPLACE PROCEDURE ops.snapshot_kpis(p_as_of DATE)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  asof DATE;
BEGIN
  asof := p_as_of;
  IF (asof IS NULL) THEN
    SELECT MAX(order_date) INTO :asof FROM raw.orders;
  END IF;

  DELETE FROM ops.kpi_snapshot WHERE as_of_date = :asof;

  -- Revenue: last 14 days vs the 14 before, per region.
  INSERT INTO ops.kpi_snapshot (as_of_date, metric, dimension, value)
  WITH w AS (
    SELECT c.region,
      SUM(IFF(o.order_date >  DATEADD('day', -14, :asof) AND o.order_date <= :asof, o.total_price, 0)) AS last14,
      SUM(IFF(o.order_date <= DATEADD('day', -14, :asof) AND o.order_date >  DATEADD('day', -28, :asof), o.total_price, 0)) AS prior14
    FROM raw.orders o
    JOIN raw.customers c ON c.cust_key = o.cust_key
    WHERE o.order_date > DATEADD('day', -28, :asof) AND o.order_date <= :asof
    GROUP BY c.region
  )
  SELECT :asof, 'rev_last_14d', region, last14 FROM w
  UNION ALL
  SELECT :asof, 'rev_prior_14d', region, prior14 FROM w
  UNION ALL
  SELECT :asof, 'rev_change_pct_14d', region, ROUND(100 * (last14 - prior14) / NULLIF(prior14, 0), 1) FROM w;

  -- Pipeline: share of open pipeline value with no stage change for more than 30 days.
  INSERT INTO ops.kpi_snapshot (as_of_date, metric, dimension, value)
  SELECT :asof, 'stale_pipeline_pct', region,
         ROUND(100 * SUM(IFF(DATEDIFF('day', last_stage_change, :asof) > 30, amount, 0)) / NULLIF(SUM(amount), 0), 1)
  FROM raw.pipeline
  WHERE stage NOT IN ('Closed Won', 'Closed Lost')
  GROUP BY region;

  -- Delivery: overdue open tasks per project region.
  INSERT INTO ops.kpi_snapshot (as_of_date, metric, dimension, value)
  SELECT :asof, 'overdue_task_count', p.region, COUNT(*)
  FROM raw.tasks t
  JOIN raw.projects p ON p.project_id = t.project_id
  WHERE t.status <> 'Done' AND t.due_date < :asof
  GROUP BY p.region;

  -- Threshold breaches become (or stay) open risks.
  MERGE INTO ops.risk_register r
  USING (
    SELECT s.metric || ':' || s.dimension AS risk_id, s.metric, s.dimension, s.value,
           CASE WHEN (t.direction = 'below' AND s.value <= t.crit_value)
                  OR (t.direction = 'above' AND s.value >= t.crit_value) THEN 'CRITICAL' ELSE 'WARNING' END AS severity
    FROM ops.kpi_snapshot s
    JOIN raw.thresholds t ON t.metric = s.metric
    WHERE s.as_of_date = :asof
      AND ((t.direction = 'below' AND s.value <= t.warn_value)
        OR (t.direction = 'above' AND s.value >= t.warn_value))
  ) b ON r.risk_id = b.risk_id
  WHEN MATCHED THEN UPDATE SET last_seen = :asof, severity = b.severity, status = 'OPEN'
  WHEN NOT MATCHED THEN INSERT (risk_id, title, metric, dimension, severity, first_seen, last_seen, status)
    VALUES (b.risk_id, b.metric || ' outside threshold in ' || b.dimension, b.metric, b.dimension,
            b.severity, :asof, :asof, 'OPEN');

  -- Risks not seen at this as-of date are resolved.
  UPDATE ops.risk_register SET status = 'RESOLVED' WHERE status = 'OPEN' AND last_seen < :asof;

  RETURN 'snapshot saved for ' || :asof::STRING;
END;
$$;

-- Build history so "what changed since the last briefing" works on day one.
CREATE OR REPLACE PROCEDURE ops.backfill_snapshots(p_days NUMBER)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  maxd DATE;
BEGIN
  SELECT MAX(order_date) INTO :maxd FROM raw.orders;
  FOR k IN 0 TO :p_days DO
    CALL ops.snapshot_kpis(DATEADD('day', -(:p_days - :k), :maxd));
  END FOR;
  RETURN 'backfilled ' || :p_days::STRING || ' days ending ' || :maxd::STRING;
END;
$$;

-- ---------------------------------------------------------------- lookups exposed to the agent as custom tools
-- Custom tools cannot take object parameters, so these take strings and return JSON text.

CREATE OR REPLACE PROCEDURE ops.get_open_risks()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  res STRING;
BEGIN
  SELECT COALESCE(TO_JSON(ARRAY_AGG(OBJECT_CONSTRUCT(
           'risk_id', risk_id, 'title', title, 'severity', severity,
           'first_seen', first_seen, 'last_seen', last_seen))), '[]')
    INTO :res
    FROM ops.risk_register
   WHERE status = 'OPEN';
  RETURN res;
END;
$$;

CREATE OR REPLACE PROCEDURE ops.get_kpi_deltas(p_as_of_date STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  res STRING;
BEGIN
  WITH cur AS (
    SELECT * FROM ops.kpi_snapshot WHERE as_of_date = TO_DATE(:p_as_of_date)
  ),
  prev AS (
    SELECT * FROM ops.kpi_snapshot
    WHERE as_of_date = (SELECT MAX(as_of_date) FROM ops.kpi_snapshot WHERE as_of_date < TO_DATE(:p_as_of_date))
  )
  SELECT COALESCE(TO_JSON(ARRAY_AGG(OBJECT_CONSTRUCT(
           'metric', c.metric, 'dimension', c.dimension, 'value', c.value,
           'previous', p.value, 'change', c.value - p.value))), '[]')
    INTO :res
    FROM cur c
    LEFT JOIN prev p ON p.metric = c.metric AND p.dimension = c.dimension;
  RETURN res;
END;
$$;

CREATE OR REPLACE PROCEDURE ops.get_prior_briefing(p_as_of_date STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  res STRING DEFAULT 'No prior briefing.';
BEGIN
  SELECT briefing_md INTO :res
    FROM ops.briefings
   WHERE as_of_date < TO_DATE(:p_as_of_date)
   ORDER BY as_of_date DESC, briefing_id DESC
   LIMIT 1;
  RETURN res;
END;
$$;
