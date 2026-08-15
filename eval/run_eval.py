#!/usr/bin/env python3
"""Score saved agent outputs against eval/cases.yaml.

Each output is a JSON file named <case_id>.json:
  {"markdown": "...", "claims": [{"value": -15.2, "verified": true}, ...], "latency_s": 41.2, "credits": 0.07}
(claims come from the json block in the answer; "verified" comes from agent/verify_claims.py).

Metrics per case: factual_accuracy, evidence_grounding, completion, latency_s, credits.
Usefulness of recommendations is scored by hand (1-5) in the results CSV, not here.

Usage:
  python eval/run_eval.py --outputs eval/outputs --out eval/results/baseline.csv
  python eval/run_eval.py --outputs eval/outputs --truth eval/truth.json   # skip Snowflake, use saved ground truth
  python eval/run_eval.py --run --outputs eval/outputs                     # call the agent for every case first
  python eval/run_eval.py --selftest
"""
import argparse
import csv
import json
import os
import pathlib
import re
import sys
import time

SECTIONS = ["Business health", "What changed", "Risks and blockers", "Recommended actions", "Meeting preparation"]


def within(claimed, actual, tolerance_abs=None, tolerance_pct=None):
    if claimed is None or actual is None:
        return False
    tol = max(tolerance_abs or 0.0, abs(actual) * (tolerance_pct or 0.0) / 100.0)
    if tol == 0.0:
        tol = 0.5
    try:
        return abs(float(claimed) - float(actual)) <= tol
    except (TypeError, ValueError):
        return False


def section_text(markdown, name):
    """Text under '## name' up to the next '## ' heading, or None if the heading is missing."""
    lines = markdown.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.strip().lower().startswith("##") and name.lower() in line.lower():
            start = i + 1
            break
    if start is None:
        return None
    out = []
    for line in lines[start:]:
        if line.strip().startswith("## "):
            break
        out.append(line)
    return "\n".join(out)


def count_actions(markdown):
    body = section_text(markdown, "Recommended actions") or ""
    return sum(1 for line in body.splitlines() if re.match(r"^\s*\d+[.)]\s", line))


def score_case(case, output, truth):
    md = output.get("markdown", "") or ""
    low = md.lower()
    claims = output.get("claims") or []
    expected = case.get("expected_values") or {}

    accuracy = None
    if expected:
        hits = 0
        for key, spec in expected.items():
            actual = truth.get(key)
            if any(within(c.get("value"), actual, spec.get("tolerance_abs"), spec.get("tolerance_pct")) for c in claims):
                hits += 1
        accuracy = hits / len(expected)

    grounding = None
    if claims:
        grounding = sum(1 for c in claims if c.get("verified") is True) / len(claims)
    elif expected:
        grounding = 0.0

    checks = []
    if case.get("output_kind") == "briefing":
        for name in SECTIONS:
            checks.append(section_text(md, name) is not None)
        checks.append(count_actions(md) == 3)
    for term in case.get("must_mention", []) or []:
        checks.append(term.lower() in low)
    any_terms = case.get("must_mention_any", []) or []
    if any_terms:
        checks.append(any(t.lower() in low for t in any_terms))
    for term in case.get("must_not_mention", []) or []:
        checks.append(term.lower() not in low)
    completion = (sum(checks) / len(checks)) if checks else None

    return {"case_id": case["id"], "factual_accuracy": accuracy, "evidence_grounding": grounding,
            "completion": completion, "latency_s": output.get("latency_s"), "credits": output.get("credits"),
            "usefulness_1to5": ""}  # fill in by hand


def ask_agent(prompt):
    """Call ops.exec_briefing_agent and return {"markdown": str, "claims": [...], "credits": float|None}.

    Left for Cortex Code to fill in (see docs/cortex-code-prompts.md). Options:
      - the Cortex Agents REST API (agent:run) with a token for your account, or
      - the DATA_AGENT_RUN SQL function in SNOWFLAKE.CORTEX (check its syntax in the docs).
    Parse the final ```json claims block with agent/verify_claims.py:extract_claims.
    """
    raise NotImplementedError("implement ask_agent() for your account")


def resolve_truth(cases, truth_file):
    truth = {}
    if truth_file and os.path.exists(truth_file):
        truth.update(json.load(open(truth_file)))
    needed = {k: v for c in cases for k, v in (c.get("expected_values") or {}).items() if k not in truth}
    if needed:
        import snowflake.connector  # only needed when ground truth is not precomputed
        conn = snowflake.connector.connect(connection_name=os.environ.get("SNOWFLAKE_CONNECTION_NAME", "default"),
                                           database="COS", warehouse="COS_WH")
        try:
            for key, spec in needed.items():
                cur = conn.cursor()
                cur.execute(spec["sql"])
                row = cur.fetchone()
                truth[key] = float(row[0]) if row and row[0] is not None else None
        finally:
            conn.close()
    return truth


def _fmt(v):
    return "" if v is None else ("%.2f" % v if isinstance(v, float) else str(v))


def _selftest():
    case = {"id": "t1", "output_kind": "briefing",
            "expected_values": {"eu": {"tolerance_abs": 0.5}},
            "must_mention": ["machinery"], "must_mention_any": ["likely"], "must_not_mention": ["asia fell"]}
    md = "\n".join(["# Briefing"] + ["## " + s + "\ntext" if s != "Recommended actions"
                    else "## Recommended actions\n1. Fix portal\n2. Call buyers\n3. Review deals" for s in SECTIONS]
                   ) + "\nLikely driver: machinery orders paused."
    out = {"markdown": md, "claims": [{"value": -15.2, "verified": True}, {"value": 3, "verified": False}]}
    s = score_case(case, out, {"eu": -15.18})
    assert s["factual_accuracy"] == 1.0, s
    assert s["evidence_grounding"] == 0.5, s
    assert s["completion"] == 1.0, s
    bad = score_case(case, {"markdown": "## Business health\nasia fell", "claims": []}, {"eu": -15.18})
    assert bad["factual_accuracy"] == 0.0 and bad["evidence_grounding"] == 0.0 and bad["completion"] < 0.5, bad
    assert count_actions("## Recommended actions\n1. a\n2. b\n3. c\n## Next\n1. x") == 3
    assert count_actions("## Recommended actions\n- a\n- b") == 0
    assert section_text("## A\nx\n## B\ny", "B").strip() == "y"
    assert section_text("## A\nx", "Z") is None
    print("run_eval selftest: all checks passed")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--cases", default="eval/cases.yaml")
    p.add_argument("--outputs", default="eval/outputs", help="directory of <case_id>.json outputs")
    p.add_argument("--truth", default=None, help="optional JSON of precomputed ground-truth values")
    p.add_argument("--out", default="eval/results/latest.csv")
    p.add_argument("--run", action="store_true", help="call ask_agent() for each case and save outputs first")
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args()
    if a.selftest:
        _selftest()
        return
    try:
        import yaml
    except ImportError:
        sys.exit("pip install pyyaml")
    cases = yaml.safe_load(open(a.cases))["cases"]
    out_dir = pathlib.Path(a.outputs)
    out_dir.mkdir(parents=True, exist_ok=True)
    if a.run:
        for c in cases:
            t0 = time.time()
            result = ask_agent(c["prompt"])
            result["latency_s"] = round(time.time() - t0, 1)
            (out_dir / (c["id"] + ".json")).write_text(json.dumps(result, indent=2))
    truth = resolve_truth(cases, a.truth)
    rows = []
    for c in cases:
        f = out_dir / (c["id"] + ".json")
        if not f.exists():
            print("skip %s: no output file" % c["id"])
            continue
        rows.append(score_case(c, json.loads(f.read_text()), truth))
    if not rows:
        sys.exit("no outputs scored")
    pathlib.Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    with open(a.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    for m in ("factual_accuracy", "evidence_grounding", "completion", "latency_s", "credits"):
        vals = [r[m] for r in rows if isinstance(r[m], (int, float))]
        print("%-20s %s" % (m, _fmt(sum(vals) / len(vals)) if vals else "n/a"))
    print("wrote", a.out)


if __name__ == "__main__":
    main()
