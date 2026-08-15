-- 09_task.sql: run_briefing procedure and the scheduled task. The task only ever creates a DRAFT.
-- One step is left for Cortex Code: calling the agent (marked TODO below).

USE DATABASE cos;
USE WAREHOUSE cos_wh;

CREATE OR REPLACE PROCEDURE ops.save_briefing(p_as_of DATE, p_md STRING)
RETURNS NUMBER
LANGUAGE SQL
AS
$$
DECLARE
  bid NUMBER;
BEGIN
  INSERT INTO ops.briefings (as_of_date, status, briefing_md) VALUES (:p_as_of, 'DRAFT', :p_md);
  SELECT MAX(briefing_id) INTO :bid FROM ops.briefings WHERE as_of_date = :p_as_of;
  RETURN bid;
END;
$$;

CREATE OR REPLACE PROCEDURE ops.run_briefing(p_as_of DATE)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  asof DATE;
  draft STRING;
  bid NUMBER;
BEGIN
  asof := p_as_of;
  IF (asof IS NULL) THEN
    SELECT MAX(order_date) INTO :asof FROM raw.orders;
  END IF;

  -- 1. Deterministic facts first: KPI snapshot, thresholds, risk register.
  CALL ops.snapshot_kpis(:asof);

  -- 2. TODO (Cortex Code): call the agent ops.exec_briefing_agent with the prompt
  --    'Prepare the executive briefing as of <asof>' and put its text in :draft.
  --    The CREATE AGENT reference lists DATA_AGENT_RUN in SNOWFLAKE.CORTEX as a related SQL function;
  --    check its syntax there. If a Task cannot reach the agent from a trial account, run steps 1, 3 and 4
  --    from a local script that calls the Agents REST API instead.
  draft := '# Briefing as of ' || :asof::STRING || CHR(10) || CHR(10) || 'TODO: agent output goes here.';

  -- 3. Save as DRAFT. Claims in the draft are then checked with agent/verify_claims.py.
  CALL ops.save_briefing(:asof, :draft);

  RETURN 'draft saved for ' || :asof::STRING;
END;
$$;

-- Build history first (five days), then run the live day.
-- CALL ops.backfill_snapshots(5);
-- CALL ops.run_briefing(NULL);

-- Tasks are created suspended. Test with EXECUTE TASK, resume only for the demo window.
CREATE OR REPLACE TASK ops.daily_briefing
  WAREHOUSE = cos_wh
  SCHEDULE = 'USING CRON 0 7 * * 1-5 America/Indianapolis'
AS
  CALL ops.run_briefing(NULL);

-- EXECUTE TASK ops.daily_briefing;
-- ALTER TASK ops.daily_briefing RESUME;
-- ALTER TASK ops.daily_briefing SUSPEND;   -- always suspend again when you are done
