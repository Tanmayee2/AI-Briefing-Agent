-- 05_anomalies.sql: inject the planted problems. Run AFTER 04_synthetic.sql.
-- To return to a clean baseline, re-run 02 -> 03 -> 04.
--
-- A1  EUROPE x MACHINERY orders drop ~75% over the last 14 days (about 15% of EUROPE revenue)   <- this file
-- A2  Four large EUROPE opportunities stuck in Negotiation for 35 days                           <- this file
-- A3  Project "Pricing portal v2 (EMEA)" overdue, blocked on a vendor                            <- 04_synthetic.sql
-- A4  Notes N-001..N-004 tie European machinery distributors to pricing portal errors            <- 04_synthetic.sql
-- A5  Decoy note N-005 (ASIA supplier delay, no revenue impact)                                  <- 04_synthetic.sql
-- A6  Control: ASIA stays within thresholds                                                      <- nothing to inject

USE DATABASE cos;
USE WAREHOUSE cos_wh;

-- A1: remove 75% of recent EUROPE x MACHINERY orders (deterministic via hash).
DELETE FROM raw.orders o
USING raw.customers c, analytics.v_as_of a
WHERE c.cust_key = o.cust_key
  AND c.region = 'EUROPE'
  AND c.segment = 'MACHINERY'
  AND o.order_date > DATEADD('day', -14, a.as_of_date)
  AND MOD(ABS(HASH(o.order_key)), 100) < 75;

-- A2: make four open EUROPE opportunities big and stale.
UPDATE raw.pipeline
SET stage = 'Negotiation',
    amount = 450000 + MOD(ABS(HASH(opp_id)), 100000),
    last_stage_change = DATEADD('day', -35, (SELECT as_of_date FROM analytics.v_as_of))
WHERE opp_id IN (
  SELECT opp_id FROM raw.pipeline
  WHERE region = 'EUROPE' AND stage NOT IN ('Closed Won', 'Closed Lost')
  ORDER BY opp_id
  LIMIT 4
);

-- Check: EUROPE should show roughly -15% and MACHINERY roughly -75%; ASIA should be near 0.
SELECT region, rev_change_pct FROM analytics.v_region_14d ORDER BY region;
SELECT region, segment, rev_change_pct FROM analytics.v_region_segment_14d WHERE region = 'EUROPE' ORDER BY segment;
SELECT region, stale_opps, stale_pipeline_pct FROM analytics.v_pipeline_summary ORDER BY region;
