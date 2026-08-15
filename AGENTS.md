# Project rules for Cortex Code

This repo builds a daily executive briefing agent on Snowflake (database `COS`).

## Safety
- Treat schema `raw` as read-only except in the numbered setup scripts in `sql/`.
- Use only warehouse `COS_WH` (X-Small). Do not create or resize warehouses.
- Do not select personal data. Customer names are pseudonyms; never output addresses or phone numbers.
- Never send email, post messages or call external services. Briefings stay `DRAFT` until a person approves them.
- Never run `DROP`, `TRUNCATE` or `ALTER ... RESUME` on the task without asking first.

## Working style
- "As of" is the latest order date in `raw.orders`, not today's date.
- Numbers come from SQL. Do not compute metrics in prose.
- When you generate SQL, show it, run it on a small sample first, and report row counts.
- After any change to `sql/`, update `docs/cortex-code-log.md` with what you produced and what had to be corrected.

## Layout
- `sql/` numbered setup scripts (run in order). `.cortex/skills/` the three workflows. `agent/` verification script.
- `eval/` cases and scorer. `docs/` prompts and the Cortex Code log.
