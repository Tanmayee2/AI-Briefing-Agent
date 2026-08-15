-- 02_raw_tpch.sql: copy TPC-H into cos.raw with dates shifted so the newest order is yesterday.
-- The sample database is read-only, so we work on copies. Re-run this file to get a clean baseline.

USE DATABASE cos;
USE WAREHOUSE cos_wh;

-- One-row table that remembers the shift, so every table moves by the same amount.
CREATE OR REPLACE TABLE raw.date_shift AS
SELECT MAX(o_orderdate) AS max_orig_date,
       DATEDIFF('day', MAX(o_orderdate), DATEADD('day', -1, CURRENT_DATE())) AS shift_days
FROM snowflake_sample_data.tpch_sf1.orders;

-- Customers with region and segment (no address or phone: keep PII out of the demo).
CREATE OR REPLACE TABLE raw.customers AS
SELECT c.c_custkey    AS cust_key,
       c.c_name       AS cust_name,
       c.c_mktsegment AS segment,
       n.n_name       AS nation,
       r.r_name       AS region
FROM snowflake_sample_data.tpch_sf1.customer c
JOIN snowflake_sample_data.tpch_sf1.nation n ON n.n_nationkey = c.c_nationkey
JOIN snowflake_sample_data.tpch_sf1.region r ON r.r_regionkey = n.n_regionkey;

-- Last 730 days of orders, shifted forward.
CREATE OR REPLACE TABLE raw.orders AS
SELECT o.o_orderkey                              AS order_key,
       o.o_custkey                               AS cust_key,
       DATEADD('day', s.shift_days, o.o_orderdate) AS order_date,
       o.o_totalprice                            AS total_price,
       o.o_orderstatus                           AS status,
       o.o_orderpriority                         AS priority
FROM snowflake_sample_data.tpch_sf1.orders o
CROSS JOIN raw.date_shift s
WHERE o.o_orderdate > DATEADD('day', -730, s.max_orig_date);

-- Sanity check: expect roughly 450k orders ending yesterday.
SELECT COUNT(*) AS order_rows, MIN(order_date) AS first_day, MAX(order_date) AS last_day FROM raw.orders;
