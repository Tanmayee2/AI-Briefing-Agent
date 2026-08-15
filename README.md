# AI Executive Briefing Agent (Snowflake)

A daily "chief of staff" that prepares an evidence-backed briefing from business metrics, project updates and call notes. It drafts only; a person approves before anything is delivered.

**Status of this starter kit:** the SQL, skills, agent specification and scripts were written without access to a live Snowflake account. The Python scripts pass offline self-tests; the SQL and agent spec have not been run. Treat first execution as part of the project and log fixes in `docs/cortex-code-log.md`. Field names in `sql/08_agent.sql` and the scheduling call in `sql/09_task.sql` are the two places most likely to need adjusting against current Snowflake documentation.

## Design in one paragraph
SQL computes the facts (KPI snapshot, deltas, threshold breaches, risks). The Cortex Agent investigates and explains, using a semantic view for numbers, Cortex Search for call notes, and small lookups for memory. Every key number is a claim with SQL that is re-run and compared. The result is saved as `DRAFT`.

## Data
TPC-H SF1 (revenue backbone) plus synthetic targets, pipeline, projects, tasks, meetings and notes. Six planted scenarios (A1 to A6) are described in `sql/05_anomalies.sql`. The sample data is frozen, so "as of" means the latest order date.

## Run order
1. Sign up for the Cortex Code trial (30 days, no card). Install the CLI and connect.
2. In a worksheet or with Cortex Code, run `sql/01_setup.sql` to `sql/05_anomalies.sql` in order.
3. Create the semantic view (prompt 2 in `docs/cortex-code-prompts.md`).
4. Run `sql/06_ops_tables.sql`, `sql/07_checks.sql`, `sql/08_agent.sql`.
5. `CALL ops.backfill_snapshots(5);` to build history, then test the agent in Snowsight.
6. Finish the agent call in `sql/09_task.sql` (prompt 4), then `CALL ops.run_briefing(NULL);`.
7. Verify claims: `python agent/verify_claims.py --briefing-id <id> --ingest`.
8. Approve: `CALL ops.approve_briefing(<id>);`.
9. Evaluate: implement `ask_agent()` (prompt 5), then `python eval/run_eval.py --run`.

Offline checks that need no Snowflake: `python agent/verify_claims.py --selftest` and `python eval/run_eval.py --selftest`.

## Skills
`.cortex/skills/` holds `daily-executive-briefing`, `investigate-kpi-anomaly` and `prepare-for-meeting`. Cortex Code discovers project skills automatically; confirm with `/skill list`. Keep their text consistent with the agent instructions in `sql/08_agent.sql`.

## Cost and safety
- Trial credits only: do not add a payment method. One X-Small warehouse with 60-second auto-suspend and a resource monitor.
- Suspend the task when you are not demoing: `ALTER TASK ops.daily_briefing SUSPEND;`
- Cortex Code trial converts to paid after 30 days unless cancelled. Export screenshots, the demo video and eval results before then.

## Folder map
```
sql/        01..09 numbered scripts      agent/   verify_claims.py
.cortex/skills/   three workflows        eval/    cases.yaml, run_eval.py
docs/       Cortex Code prompts and log  AGENTS.md  rules for Cortex Code
```
