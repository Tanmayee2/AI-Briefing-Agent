-- 03_views.sql: analytics views built only on the order data.
-- "As of" is the newest order date, not today's date, because the sample data is frozen.

USE DATABASE cos;
USE WAREHOUSE cos_wh;

CREATE OR REPLACE VIEW analytics.v_as_of AS
SELECT MAX(order_date) AS as_of_date FROM raw.orders;

CREATE OR REPLACE VIEW analytics.v_orders_enriched AS
SELECT o.order_key, o.order_date, o.total_price, o.cust_key,
       c.region, c.segment, c.nation
FROM raw.orders o
JOIN raw.customers c ON c.cust_key = o.cust_key;

CREATE OR REPLACE VIEW analytics.v_daily_revenue AS
SELECT order_date, region, segment,
       SUM(total_price) AS revenue,
       COUNT(*)         AS orders
FROM analytics.v_orders_enriched
GROUP BY order_date, region, segment;

-- Revenue in the last 14 days vs the 14 days before, by region.
CREATE OR REPLACE VIEW analytics.v_region_14d AS
WITH a AS (SELECT as_of_date FROM analytics.v_as_of),
s AS (
  SELECT d.region,
    SUM(IFF(d.order_date > DATEADD('day', -14, a.as_of_date), d.revenue, 0)) AS rev_last_14d,
    SUM(IFF(d.order_date <= DATEADD('day', -14, a.as_of_date)
        AND d.order_date >  DATEADD('day', -28, a.as_of_date), d.revenue, 0)) AS rev_prior_14d,
    SUM(IFF(d.order_date > DATEADD('day', -14, a.as_of_date), d.orders, 0)) AS orders_last_14d,
    SUM(IFF(d.order_date <= DATEADD('day', -14, a.as_of_date)
        AND d.order_date >  DATEADD('day', -28, a.as_of_date), d.orders, 0)) AS orders_prior_14d
  FROM analytics.v_daily_revenue d CROSS JOIN a
  GROUP BY d.region
)
SELECT region, rev_last_14d, rev_prior_14d, orders_last_14d, orders_prior_14d,
       ROUND(100 * (rev_last_14d - rev_prior_14d) / NULLIF(rev_prior_14d, 0), 1) AS rev_change_pct
FROM s;

-- Same split one level down: region x segment (where the drop is hiding).
CREATE OR REPLACE VIEW analytics.v_region_segment_14d AS
WITH a AS (SELECT as_of_date FROM analytics.v_as_of),
s AS (
  SELECT d.region, d.segment,
    SUM(IFF(d.order_date > DATEADD('day', -14, a.as_of_date), d.revenue, 0)) AS rev_last_14d,
    SUM(IFF(d.order_date <= DATEADD('day', -14, a.as_of_date)
        AND d.order_date >  DATEADD('day', -28, a.as_of_date), d.revenue, 0)) AS rev_prior_14d,
    SUM(IFF(d.order_date > DATEADD('day', -14, a.as_of_date), d.orders, 0)) AS orders_last_14d,
    SUM(IFF(d.order_date <= DATEADD('day', -14, a.as_of_date)
        AND d.order_date >  DATEADD('day', -28, a.as_of_date), d.orders, 0)) AS orders_prior_14d
  FROM analytics.v_daily_revenue d CROSS JOIN a
  GROUP BY d.region, d.segment
)
SELECT region, segment, rev_last_14d, rev_prior_14d, orders_last_14d, orders_prior_14d,
       ROUND(100 * (rev_last_14d - rev_prior_14d) / NULLIF(rev_prior_14d, 0), 1) AS rev_change_pct
FROM s;

-- Retention: of customers active in the prior 180-day window, the share active again in the latest 180 days.
CREATE OR REPLACE VIEW analytics.v_retention AS
WITH a AS (SELECT as_of_date FROM analytics.v_as_of),
cur AS (
  SELECT DISTINCT o.cust_key FROM raw.orders o CROSS JOIN a
  WHERE o.order_date > DATEADD('day', -180, a.as_of_date)
),
prev AS (
  SELECT DISTINCT o.cust_key FROM raw.orders o CROSS JOIN a
  WHERE o.order_date <= DATEADD('day', -180, a.as_of_date)
    AND o.order_date >  DATEADD('day', -360, a.as_of_date)
)
SELECT c.region,
       COUNT(p.cust_key)  AS prior_active_customers,
       COUNT(cu.cust_key) AS retained_customers,
       ROUND(COUNT(cu.cust_key) / NULLIF(COUNT(p.cust_key), 0), 4) AS retention_rate
FROM prev p
JOIN raw.customers c ON c.cust_key = p.cust_key
LEFT JOIN cur cu ON cu.cust_key = p.cust_key
GROUP BY c.region;

-- Quick look
SELECT * FROM analytics.v_region_14d ORDER BY region;
