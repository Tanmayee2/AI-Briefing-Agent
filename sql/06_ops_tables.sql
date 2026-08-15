-- 06_ops_tables.sql: memory, evidence and approval tables.

USE DATABASE cos;
USE WAREHOUSE cos_wh;

-- Every saved briefing. Nothing is delivered unless status = 'APPROVED'.
CREATE TABLE IF NOT EXISTS ops.briefings (
  briefing_id  NUMBER AUTOINCREMENT,
  as_of_date   DATE,
  status       STRING DEFAULT 'DRAFT',      -- DRAFT | APPROVED | REJECTED
  briefing_md  STRING,
  created_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  approved_at  TIMESTAMP_NTZ,
  approved_by  STRING
);

-- One row per metric, per dimension (region), per as-of date. Deltas are computed from this, not by the model.
CREATE TABLE IF NOT EXISTS ops.kpi_snapshot (
  as_of_date DATE,
  metric     STRING,
  dimension  STRING,
  value      FLOAT
);

-- Risks that persist across days until the metric is back inside its threshold.
CREATE TABLE IF NOT EXISTS ops.risk_register (
  risk_id    STRING,
  title      STRING,
  metric     STRING,
  dimension  STRING,
  severity   STRING,      -- WARNING | CRITICAL
  first_seen DATE,
  last_seen  DATE,
  status     STRING DEFAULT 'OPEN'   -- OPEN | RESOLVED
);

-- Evidence: every key number in a briefing, the SQL behind it, and whether a re-run matched.
CREATE TABLE IF NOT EXISTS ops.claims (
  claim_id       NUMBER AUTOINCREMENT,
  briefing_id    NUMBER,
  claim_text     STRING,
  metric         STRING,
  claimed_value  FLOAT,
  claim_sql      STRING,
  query_id       STRING,
  verified       BOOLEAN,
  verified_value FLOAT,
  checked_at     TIMESTAMP_NTZ
);

-- Approval gate.
CREATE OR REPLACE PROCEDURE ops.approve_briefing(p_id NUMBER)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
  UPDATE ops.briefings
     SET status = 'APPROVED', approved_at = CURRENT_TIMESTAMP(), approved_by = CURRENT_USER()
   WHERE briefing_id = :p_id AND status = 'DRAFT';
  RETURN 'approved briefing ' || :p_id::STRING;
END;
$$;

CREATE OR REPLACE PROCEDURE ops.reject_briefing(p_id NUMBER)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
  UPDATE ops.briefings SET status = 'REJECTED' WHERE briefing_id = :p_id AND status = 'DRAFT';
  RETURN 'rejected briefing ' || :p_id::STRING;
END;
$$;
