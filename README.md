# AI Executive Briefing Agent (Snowflake)

A daily "chief of staff" that prepares an evidence-backed briefing from business metrics, project updates and call notes. It drafts only; a person approves before anything is delivered.

## Design 
SQL computes the facts (KPI snapshot, deltas, threshold breaches, risks). The Cortex Agent investigates and explains, using a semantic view for numbers, Cortex Search for call notes, and small lookups for memory. Every key number is a claim with SQL that is re-run and compared. The result is saved as `DRAFT`.

## Data
TPC-H SF1 (revenue backbone) plus synthetic targets, pipeline, projects, tasks, meetings and notes. Six planted scenarios (A1 to A6) are described in `sql/05_anomalies.sql`. The sample data is frozen, so "as of" means the latest order date.

## Run order
1. Sign up for the Cortex Code. Install the CLI and connect.
2. In a worksheet or with Cortex Code, run `sql/01_setup.sql` to `sql/05_anomalies.sql` in order.
3. Create the semantic view.
4. Run `sql/06_ops_tables.sql`, `sql/07_checks.sql`, `sql/08_agent.sql`.
5. `CALL ops.backfill_snapshots(5);` to build history, then test the agent in Snowsight.
6. Finish the agent call in `sql/09_task.sql`, then `CALL ops.run_briefing(NULL);`.
7. Verify claims: `python agent/verify_claims.py --briefing-id <id> --ingest`.
8. Approve: `CALL ops.approve_briefing(<id>);`.
9. Evaluate: implement `ask_agent()`, then `python eval/run_eval.py --run`.


## Skills
`.cortex/skills/` holds `daily-executive-briefing`, `investigate-kpi-anomaly` and `prepare-for-meeting`. Cortex Code discovers project skills automatically; confirm with `/skill list`. Keep their text consistent with the agent instructions in `sql/08_agent.sql`.


## Folder map
```
sql/        01..09 numbered scripts      agent/   verify_claims.py
.cortex/skills/   three workflows        eval/    cases.yaml, run_eval.py
docs/       Cortex Code prompts and log  AGENTS.md  rules for Cortex Code
```
