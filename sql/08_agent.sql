-- 08_agent.sql: the Cortex Agent object.
-- Before running:
--   1. Create the semantic view over cos.analytics (ask Cortex Code; see docs/cortex-code-prompts.md)
--      and set its fully qualified name below (placeholder: COS.ANALYTICS.KPI_SEMANTIC_VIEW).
--   2. 04_synthetic.sql must have created ops.notes_search, and 07_checks.sql the procedures.
-- The specification field names follow the CREATE AGENT reference; confirm them there if the statement is rejected.
-- Keep the instruction text in sync with the three skills in .cortex/skills/.

USE DATABASE cos;
USE WAREHOUSE cos_wh;

CREATE OR REPLACE AGENT ops.exec_briefing_agent
  COMMENT = 'Daily executive briefing agent: investigates KPIs and drafts an evidence-backed briefing'
  PROFILE = '{"display_name": "Chief of Staff"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  orchestration: |
    You prepare executive briefings from business data. Use tools in this order:
    1. get_kpi_deltas and get_open_risks for what changed and what is still unresolved.
    2. kpi_analyst for any number you will state. Never state a number you did not get from a tool.
    3. notes_search only to explain a movement you have already confirmed with numbers.
    4. get_prior_briefing to avoid repeating yesterday's content without saying what changed.
    "As of" is the latest order date, not today's date. Split anomalies by region, then segment, before naming a cause.
  response: |
    Write a briefing with exactly five H2 sections: Business health, What changed, Risks and blockers,
    Recommended actions (exactly three, ranked), Meeting preparation.
    Label causes "likely" unless two independent sources agree (for example numbers plus notes).
    On a quiet day say "no material change" instead of inventing a story.
    Finish with a fenced json block: {"claims":[{"id":"C1","metric":"...","value":0,"text":"...","sql":"SELECT ..."}]}
    where each claim's sql returns the stated value as its first column.
    Never send or schedule anything externally.

tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: kpi_analyst
      description: Answers revenue, pipeline, retention, target and overdue-work questions over the KPI views.
  - tool_spec:
      type: cortex_search
      name: notes_search
      description: Searches account call notes and incident logs for context on a confirmed movement.
  - tool_spec:
      type: generic
      name: get_open_risks
      description: Returns unresolved risks carried over from earlier briefings as JSON.
      input_schema:
        type: object
        properties: {}
  - tool_spec:
      type: generic
      name: get_kpi_deltas
      description: Returns each KPI for the as-of date with its previous value and change, as JSON.
      input_schema:
        type: object
        properties:
          p_as_of_date:
            type: string
            description: As-of date in YYYY-MM-DD format.
        required: [p_as_of_date]
  - tool_spec:
      type: generic
      name: get_prior_briefing
      description: Returns the most recent earlier briefing text, or a note that none exists.
      input_schema:
        type: object
        properties:
          p_as_of_date:
            type: string
            description: As-of date in YYYY-MM-DD format.
        required: [p_as_of_date]

tool_resources:
  kpi_analyst:
    semantic_view: COS.ANALYTICS.KPI_SEMANTIC_VIEW
  notes_search:
    name: COS.OPS.NOTES_SEARCH
    max_results: 5
  get_open_risks:
    type: procedure
    identifier: COS.OPS.GET_OPEN_RISKS
    execution_environment:
      type: warehouse
      warehouse: COS_WH
  get_kpi_deltas:
    type: procedure
    identifier: COS.OPS.GET_KPI_DELTAS
    execution_environment:
      type: warehouse
      warehouse: COS_WH
  get_prior_briefing:
    type: procedure
    identifier: COS.OPS.GET_PRIOR_BRIEFING
    execution_environment:
      type: warehouse
      warehouse: COS_WH
$$;

SHOW AGENTS IN SCHEMA ops;
