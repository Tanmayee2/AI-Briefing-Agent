# Cortex Code prompts

Paste these into a Cortex Code session (`cortex -c <connection>`) from the repo root. After each one, review the output, run it, and record what you had to correct in `docs/cortex-code-log.md`.

## 1. Check and run the data scripts
```
Run sql/02_raw_tpch.sql through sql/05_anomalies.sql in order against database COS using warehouse COS_WH.
After each file, report row counts and any error. If a statement fails, show the error, propose a fix,
and ask before editing the file.
```

## 2. Semantic view
```
Create a semantic view named COS.ANALYTICS.KPI_SEMANTIC_VIEW over these views in COS.ANALYTICS:
v_region_14d, v_region_segment_14d, v_retention, v_pipeline_summary, v_target_attainment, v_overdue_work.
Define metrics for revenue, order count, revenue change percent, retention rate, open pipeline,
stale pipeline percent, percent of pace, and days overdue. Add dimensions for region and segment, with synonyms
(for example "EMEA" for EUROPE, "APAC" for ASIA). Add a verified query for "why did EUROPE revenue fall".
Explain each metric definition so I can review it before you create anything.
```
Review by hand: metric formulas, join paths, synonyms. Log every correction.

## 3. Check the agent specification
```
Read sql/08_agent.sql and compare the specification against the current CREATE AGENT documentation.
List any field names or tool types that do not match, fix them, then run the statement and run
SHOW AGENTS IN SCHEMA OPS.
```

## 4. Finish the agent call in ops.run_briefing
```
In sql/09_task.sql the procedure ops.run_briefing has a TODO where the agent is called.
Find the supported way to call the Cortex Agent ops.exec_briefing_agent from SQL (check DATA_AGENT_RUN in
SNOWFLAKE.CORTEX) and implement it. If a Task on a trial account cannot make the call, write a Python script
in agent/ that calls the Agents REST API instead, keeps the DRAFT-only behavior, and calls
agent/verify_claims.py afterwards.
```

## 5. Implement ask_agent for the evaluation
```
Implement ask_agent() in eval/run_eval.py. It should send the prompt to ops.exec_briefing_agent,
return the final markdown, extract the claims json block with agent/verify_claims.py:extract_claims,
and return {"markdown": ..., "claims": [...]}. Do not change the scoring functions.
```

## 6. Debug a bad briefing
```
Briefing <id> in ops.briefings states a number that does not match the data. Use agent/verify_claims.py
output and the claim SQL to find where the agent went wrong (tool choice, semantic view, or instructions).
Propose one change and explain how I can test it with eval/run_eval.py.
```

## 7. Document the work
```
Update docs/cortex-code-log.md with what you produced in this session and which parts I corrected.
Be specific: file, statement, what was wrong, how it was fixed.
```
