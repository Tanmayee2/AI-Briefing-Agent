-- 04_synthetic.sql: the parts TPC-H does not have (targets, pipeline, projects, tasks, meetings, notes).
-- Run BEFORE 05_anomalies.sql so targets and retention targets come from the clean baseline.
-- Randomness is hash-based, so every run produces the same data.

USE DATABASE cos;
USE WAREHOUSE cos_wh;

-- ---------------------------------------------------------------- targets
-- Revenue target = 103% of the average of the last 6 complete months, per region.
-- Retention target = the clean retention rate today.
CREATE OR REPLACE TABLE raw.targets AS
WITH a AS (SELECT as_of_date FROM analytics.v_as_of),
monthly AS (
  SELECT region, DATE_TRUNC('month', order_date) AS month_start, SUM(revenue) AS rev
  FROM analytics.v_daily_revenue
  GROUP BY 1, 2
),
base AS (
  SELECT m.region, AVG(m.rev) AS avg_rev
  FROM monthly m CROSS JOIN a
  WHERE m.month_start <  DATE_TRUNC('month', a.as_of_date)
    AND m.month_start >= DATEADD('month', -6, DATE_TRUNC('month', a.as_of_date))
  GROUP BY m.region
)
SELECT b.region,
       DATE_TRUNC('month', a.as_of_date) AS month_start,
       ROUND(b.avg_rev * 1.03, 2)        AS revenue_target,
       r.retention_rate                  AS retention_target
FROM base b CROSS JOIN a
JOIN analytics.v_retention r ON r.region = b.region;

-- ---------------------------------------------------------------- thresholds
CREATE OR REPLACE TABLE raw.thresholds (metric STRING, warn_value FLOAT, crit_value FLOAT, direction STRING);
INSERT INTO raw.thresholds VALUES
  ('rev_change_pct_14d', -5, -10, 'below'),
  ('stale_pipeline_pct', 10,  20, 'above'),
  ('overdue_task_count',  2,   4, 'above');

-- ---------------------------------------------------------------- pipeline (400 opportunities)
CREATE OR REPLACE TABLE raw.pipeline AS
WITH a AS (SELECT as_of_date FROM analytics.v_as_of),
g AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 400))),
x AS (SELECT n, 1 + MOD(ABS(HASH(n, 'cust')), 150000) AS cust_key FROM g)
SELECT 'OPP-' || LPAD(x.n::STRING, 4, '0') AS opp_id,
       x.cust_key,
       c.region,
       DECODE(MOD(ABS(HASH(x.n, 'stage')), 6),
              0, 'Prospect', 1, 'Qualified', 2, 'Proposal', 3, 'Negotiation', 4, 'Closed Won', 'Closed Lost') AS stage,
       20000 + MOD(ABS(HASH(x.n, 'amt')), 480000)                          AS amount,
       DATEADD('day', -MOD(ABS(HASH(x.n, 'cd')), 120), a.as_of_date)      AS created_date,
       DATEADD('day', 7 + MOD(ABS(HASH(x.n, 'ec')), 75), a.as_of_date)    AS expected_close,
       DATEADD('day', -MOD(ABS(HASH(x.n, 'ls')), 20), a.as_of_date)       AS last_stage_change,
       DECODE(MOD(ABS(HASH(x.n, 'own')), 6),
              0, 'Avery', 1, 'Jordan', 2, 'Priya', 3, 'Mateo', 4, 'Chen', 'Sam') AS owner
FROM x
JOIN raw.customers c ON c.cust_key = x.cust_key
CROSS JOIN a;

-- ---------------------------------------------------------------- projects and tasks (due dates relative to as-of)
CREATE OR REPLACE TABLE raw.projects AS
SELECT v.project_id, v.name, v.owner, v.region, v.status,
       DATEADD('day', v.due_offset, a.as_of_date) AS due_date,
       v.blocked_reason
FROM (VALUES
  ('P-101', 'Pricing portal v2 (EMEA)',     'Priya',  'EUROPE',      'At risk',  -12, 'Waiting on integration vendor fix'),
  ('P-102', 'Retention outreach program',   'Jordan', 'AMERICA',     'On track',  20, NULL),
  ('P-103', 'Asia supplier consolidation',  'Mateo',  'ASIA',        'On track',   9, NULL),
  ('P-104', 'Quarterly pricing review',     'Avery',  'AMERICA',     'On track',  14, NULL),
  ('P-105', 'Customer data cleanup',        'Chen',   'MIDDLE EAST', 'Delayed',   -3, 'Owner on leave'),
  ('P-106', 'Sales forecast model refresh', 'Sam',    'AFRICA',      'On track',  30, NULL)
) AS v(project_id, name, owner, region, status, due_offset, blocked_reason)
CROSS JOIN analytics.v_as_of a;

CREATE OR REPLACE TABLE raw.tasks AS
SELECT v.task_id, v.project_id, v.title, v.owner, v.status,
       DATEADD('day', v.due_offset, a.as_of_date) AS due_date
FROM (VALUES
  ('T-1001', 'P-101', 'Fix vendor API timeout in portal checkout', 'Priya',  'Open',  -9),
  ('T-1002', 'P-101', 'Re-test distributor login flow',            'Priya',  'Open',  -5),
  ('T-1003', 'P-101', 'Tell EU distributors about the workaround', 'Avery',  'Open',  -2),
  ('T-1004', 'P-101', 'Vendor status call',                        'Priya',  'Done', -14),
  ('T-1005', 'P-102', 'Call top 40 accounts',                      'Jordan', 'Done',  -8),
  ('T-1006', 'P-102', 'Write outreach summary',                    'Jordan', 'Open',  12),
  ('T-1007', 'P-103', 'Compare supplier lead times',               'Mateo',  'Open',   6),
  ('T-1008', 'P-104', 'Draft pricing options',                     'Avery',  'Open',  10),
  ('T-1009', 'P-105', 'Deduplicate customer records',              'Chen',   'Open',  -3),
  ('T-1010', 'P-106', 'Agree model inputs with finance',           'Sam',    'Done',  -3)
) AS v(task_id, project_id, title, owner, status, due_offset)
CROSS JOIN analytics.v_as_of a;

-- ---------------------------------------------------------------- meetings (today = as-of + 1)
CREATE OR REPLACE TABLE raw.meetings AS
SELECT v.meeting_id, v.title,
       DATEADD('hour', v.hr, DATEADD('day', v.day_off, a.as_of_date)::TIMESTAMP_NTZ) AS start_time,
       v.attendees, v.region, v.agenda
FROM (VALUES
  ('M-01', 'EMEA weekly pipeline review',    1, 10, 'Avery; Priya; EMEA regional lead', 'EUROPE', 'Review stalled negotiations and Q4 coverage'),
  ('M-02', 'Pricing portal vendor sync',     1, 14, 'Priya; vendor PM',                 'EUROPE', 'Fix date and distributor workaround'),
  ('M-03', 'Monthly KPI review with CFO',    2,  9, 'CFO; Avery; finance lead',         'ALL',    'Revenue vs target, retention, risks'),
  ('M-04', 'Top EU machinery account call',  2, 15, 'Avery; account executive',         'EUROPE', 'Account health and ordering delays'),
  ('M-05', 'Asia operations check-in',       3, 11, 'Mateo; operations lead',           'ASIA',   'Supplier lead times')
) AS v(meeting_id, title, day_off, hr, attendees, region, agenda)
CROSS JOIN analytics.v_as_of a;

-- ---------------------------------------------------------------- call notes (searched by Cortex Search)
-- N-001..N-004 explain the EUROPE machinery drop (the real driver).
-- N-005 is a decoy: an ASIA supplier delay that does not touch revenue.
CREATE OR REPLACE TABLE raw.notes AS
SELECT v.note_id,
       DATEADD('day', v.day_off, a.as_of_date) AS note_date,
       v.region, v.segment, v.author, v.note_text
FROM (VALUES
  ('N-001', -6,  'EUROPE',      'MACHINERY', 'Avery',  'Two large machinery distributors told us the new pricing portal rejects their bulk orders at checkout. They have paused ordering until it works.'),
  ('N-002', -4,  'EUROPE',      'MACHINERY', 'Priya',  'Escalated the pricing portal checkout errors to the integration vendor. The vendor plans a fix but has not committed to a date.'),
  ('N-003', -2,  'EUROPE',      'MACHINERY', 'Avery',  'A machinery distributor in Germany asked whether they can order by email until the portal is stable.'),
  ('N-004', -1,  'EUROPE',      NULL,        'Priya',  'Vendor fix date slipped by another week. The workaround has not been communicated to distributors yet.'),
  ('N-005', -5,  'ASIA',        NULL,        'Mateo',  'One supplier reported a short shipping delay. No customer orders are affected so far.'),
  ('N-006', -8,  'AMERICA',     NULL,        'Jordan', 'Retention outreach calls finished for the top 40 accounts. Sentiment was positive.'),
  ('N-007', -10, 'MIDDLE EAST', NULL,        'Chen',   'Data cleanup backlog is growing because the project owner is on leave.'),
  ('N-008', -3,  'AFRICA',      NULL,        'Sam',    'Forecast model refresh is on schedule. New inputs were agreed with finance.'),
  ('N-009', -7,  'AMERICA',     NULL,        'Avery',  'Quarterly pricing review kicked off. No price changes proposed yet.'),
  ('N-010', -12, 'EUROPE',      'BUILDING',  'Avery',  'Building segment customers in Europe renewed on schedule.')
) AS v(note_id, day_off, region, segment, author, note_text)
CROSS JOIN analytics.v_as_of a;

-- ---------------------------------------------------------------- views over the synthetic tables
CREATE OR REPLACE VIEW analytics.v_pipeline_summary AS
WITH a AS (SELECT as_of_date FROM analytics.v_as_of)
SELECT p.region,
       SUM(IFF(p.stage NOT IN ('Closed Won', 'Closed Lost'), p.amount, 0)) AS open_pipeline,
       COUNT_IF(p.stage NOT IN ('Closed Won', 'Closed Lost'))               AS open_opps,
       COUNT_IF(p.stage NOT IN ('Closed Won', 'Closed Lost')
                AND DATEDIFF('day', p.last_stage_change, a.as_of_date) > 30) AS stale_opps,
       ROUND(100 * SUM(IFF(p.stage NOT IN ('Closed Won', 'Closed Lost')
                           AND DATEDIFF('day', p.last_stage_change, a.as_of_date) > 30, p.amount, 0))
             / NULLIF(SUM(IFF(p.stage NOT IN ('Closed Won', 'Closed Lost'), p.amount, 0)), 0), 1) AS stale_pipeline_pct
FROM raw.pipeline p CROSS JOIN a
GROUP BY p.region;

CREATE OR REPLACE VIEW analytics.v_target_attainment AS
WITH a AS (SELECT as_of_date FROM analytics.v_as_of),
mtd AS (
  SELECT d.region, SUM(d.revenue) AS rev_mtd
  FROM analytics.v_daily_revenue d CROSS JOIN a
  WHERE d.order_date >= DATE_TRUNC('month', a.as_of_date)
  GROUP BY d.region
)
SELECT t.region, t.month_start, t.revenue_target, m.rev_mtd,
       ROUND(100 * m.rev_mtd / NULLIF(t.revenue_target * DAY(a.as_of_date) / DAY(LAST_DAY(a.as_of_date)), 0), 1) AS pct_of_pace
FROM raw.targets t
CROSS JOIN a
JOIN mtd m ON m.region = t.region
WHERE t.month_start = DATE_TRUNC('month', a.as_of_date);

CREATE OR REPLACE VIEW analytics.v_overdue_work AS
SELECT p.project_id, p.name AS project_name, p.region, p.status AS project_status, p.blocked_reason,
       t.task_id, t.title AS task_title, t.owner, t.due_date,
       DATEDIFF('day', t.due_date, a.as_of_date) AS days_overdue
FROM raw.tasks t
JOIN raw.projects p ON p.project_id = t.project_id
CROSS JOIN analytics.v_as_of a
WHERE t.status <> 'Done' AND t.due_date < a.as_of_date;

-- ---------------------------------------------------------------- Cortex Search over notes
CREATE OR REPLACE CORTEX SEARCH SERVICE ops.notes_search
  ON note_text
  ATTRIBUTES region, note_date
  WAREHOUSE = cos_wh
  TARGET_LAG = '1 day'
AS (SELECT note_id, note_text, region, note_date FROM raw.notes);
