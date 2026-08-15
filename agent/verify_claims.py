#!/usr/bin/env python3
"""Re-run the SQL behind each claim in a briefing and record whether it matches.

Claim SQL is written by a model, so it is untrusted: only a single SELECT (or WITH ... SELECT)
is allowed, and comments, extra statements and write keywords are rejected. For defence in depth,
run this under a read-only role (--role).

Usage:
  python agent/verify_claims.py --briefing-id 12 --ingest     # parse the json block from the briefing, then verify
  python agent/verify_claims.py --briefing-id 12              # verify claims already in ops.claims
  python agent/verify_claims.py --selftest                    # offline tests, no Snowflake needed

Connection: reads a named connection from ~/.snowflake/config.toml or connections.toml
(env SNOWFLAKE_CONNECTION_NAME, default "default"), shared with the Snowflake CLI.
"""
import argparse
import json
import os
import re
import sys

BLOCKED = ["insert", "update", "delete", "merge", "drop", "alter", "create", "grant", "revoke",
           "call", "copy", "put", "truncate", "execute", "undrop", "remove", "unset", "use", "into"]


def is_safe_select(sql):
    """Return (ok, reason). Accepts exactly one SELECT/WITH statement with no comments."""
    if not sql or not sql.strip():
        return False, "empty"
    s = sql.strip()
    if s.endswith(";"):
        s = s[:-1].rstrip()
    stripped = re.sub(r"'(?:[^']|'')*'", "''", s)  # ignore text inside string literals
    if ";" in stripped:
        return False, "multiple statements"
    if "--" in stripped or "/*" in stripped:
        return False, "comments not allowed"
    if not re.match(r"(?is)^\s*(select|with)\b", stripped):
        return False, "must start with SELECT or WITH"
    m = re.search(r"\b(" + "|".join(BLOCKED) + r")\b", stripped, re.I)
    if m:
        return False, "blocked keyword: " + m.group(1).lower()
    return True, "ok"


def within_tolerance(claimed, actual, rel_pct=0.5, abs_floor=0.05):
    """True if claimed is within rel_pct percent of actual, or within abs_floor (for rounded values)."""
    if claimed is None or actual is None:
        return False
    tol = max(abs_floor, abs(actual) * rel_pct / 100.0)
    return abs(float(claimed) - float(actual)) <= tol


def extract_claims(markdown):
    """Return the claims list from the last fenced json block that has a 'claims' key."""
    blocks = re.findall(r"```json\s*(.*?)```", markdown or "", flags=re.S | re.I)
    for raw in reversed(blocks):
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict) and isinstance(data.get("claims"), list):
            return data["claims"]
    return []


def connect(role=None):
    import snowflake.connector  # imported lazily so --selftest needs nothing installed
    kwargs = dict(connection_name=os.environ.get("SNOWFLAKE_CONNECTION_NAME", "default"),
                  database="COS", warehouse="COS_WH")
    if role:
        kwargs["role"] = role
    return snowflake.connector.connect(**kwargs)


def ingest(conn, briefing_id):
    cur = conn.cursor()
    cur.execute("SELECT briefing_md FROM ops.briefings WHERE briefing_id = %s", (briefing_id,))
    row = cur.fetchone()
    if not row:
        sys.exit("briefing %s not found" % briefing_id)
    claims = extract_claims(row[0])
    for c in claims:
        cur.execute(
            "INSERT INTO ops.claims (briefing_id, claim_text, metric, claimed_value, claim_sql) "
            "VALUES (%s, %s, %s, %s, %s)",
            (briefing_id, c.get("text"), c.get("metric"), c.get("value"), c.get("sql")))
    return len(claims)


def verify(conn, briefing_id):
    cur = conn.cursor()
    cur.execute("SELECT claim_id, claimed_value, claim_sql FROM ops.claims "
                "WHERE briefing_id = %s AND verified IS NULL", (briefing_id,))
    results = []
    for claim_id, claimed, sql in cur.fetchall():
        ok, why = is_safe_select(sql)
        actual, qid, verified = None, None, False
        if ok:
            run = conn.cursor()
            try:
                run.execute(sql)
                row = run.fetchone()
                qid = run.sfqid
                actual = float(row[0]) if row and row[0] is not None else None
                verified = within_tolerance(claimed, actual)
            except Exception as exc:  # a failing query means the claim is not supported
                why = "query failed: %s" % exc
        upd = conn.cursor()
        upd.execute("UPDATE ops.claims SET verified = %s, verified_value = %s, query_id = %s, "
                    "checked_at = CURRENT_TIMESTAMP() WHERE claim_id = %s",
                    (verified, actual, qid, claim_id))
        results.append((claim_id, verified, why))
    return results


def _selftest():
    assert is_safe_select("SELECT 1")[0]
    assert is_safe_select("select rev_change_pct from analytics.v_region_14d where region = 'EUROPE';")[0]
    assert is_safe_select("WITH a AS (SELECT 1 AS x) SELECT x FROM a")[0]
    assert is_safe_select("SELECT 'drop table x; --' AS note")[0]          # inside a string literal
    assert not is_safe_select("SELECT 1; DROP TABLE raw.orders")[0]
    assert not is_safe_select("DELETE FROM raw.orders")[0]
    assert not is_safe_select("SELECT 1 -- hidden")[0]
    assert not is_safe_select("SELECT * INTO t FROM raw.orders")[0]
    assert not is_safe_select("CALL ops.approve_briefing(1)")[0]
    assert not is_safe_select("")[0]
    assert within_tolerance(-15.2, -15.18)
    assert not within_tolerance(-10.0, -15.18)
    assert within_tolerance(1_000_000, 1_004_000)        # 0.4% relative
    assert not within_tolerance(1_000_000, 1_020_000)    # 2% relative
    assert not within_tolerance(None, 5)
    md = 'text\n```json\n{"claims":[{"id":"C1","value":-15.2,"sql":"SELECT 1"}]}\n```\n'
    assert extract_claims(md)[0]["id"] == "C1"
    assert extract_claims("no block here") == []
    assert extract_claims("```json\nnot json\n```") == []
    print("verify_claims selftest: all checks passed")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--briefing-id", type=int)
    p.add_argument("--ingest", action="store_true", help="parse the claims json block from the briefing first")
    p.add_argument("--role", help="read-only role to run claim SQL under")
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args()
    if a.selftest:
        _selftest()
        return
    if a.briefing_id is None:
        p.error("--briefing-id is required")
    conn = connect(a.role)
    try:
        if a.ingest:
            print("ingested %d claims" % ingest(conn, a.briefing_id))
        results = verify(conn, a.briefing_id)
        for claim_id, verified, why in results:
            print("claim %s: %s (%s)" % (claim_id, "VERIFIED" if verified else "FAILED", why))
        failed = [r for r in results if not r[1]]
        print("%d verified, %d failed" % (len(results) - len(failed), len(failed)))
        sys.exit(1 if failed else 0)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
