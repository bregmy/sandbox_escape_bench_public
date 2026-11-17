#!/usr/bin/env python3
"""Write results/eval_logs/MANIFEST.csv: one row per .eval log.

Columns record the header fields of each log (scenario, control, budget, model) and which
script produced it.

Script attribution uses run-log evidence only:
  * run_<scenario>.log / run_hostpath_etc_B4-8.log print a header line
    "######## <scenario> control=<Bx> (tokens=... msgs=...) ########" and a
    "DONE <scenario>: <controls> @ ..." line. These match the output of run_scenario_full.sh.
    A log is attributed to that script only when such a header exists for its (scenario, control).
  * Privileged logs have no run log. They are labelled "inferred" (the privileged sweep uses
    the header format of run_privileged_full.sh and has no B5 log, as that script expects).
  * Everything else is labelled "not recorded".

Usage: .venv/bin/python make_log_manifest.py results/eval_logs
"""
import csv
import glob
import hashlib
import os
import re
import sys

from inspect_ai.log import read_eval_log

logdir = sys.argv[1] if len(sys.argv) > 1 else "results/eval_logs"

# (scenario, control) -> run log(s) that print a header for it
evidence: dict[tuple[str, str], list[str]] = {}
done_lines: dict[str, str] = {}
for rl in sorted(glob.glob(os.path.join(logdir, "run_*.log"))):
    text = open(rl, errors="ignore").read()
    for m in re.finditer(r"^\s*#+ (\w+) control=(B\d) \(tokens=\d+ msgs=\d+\)", text, re.M):
        evidence.setdefault((m.group(1), m.group(2)), []).append(os.path.basename(rl))
    for m in re.finditer(r"^\s*DONE (\w+): (.+)$", text, re.M):
        done_lines[os.path.basename(rl)] = m.group(0).strip()

rows = []
for path in sorted(glob.glob(os.path.join(logdir, "*.eval"))):
    log = read_eval_log(path)
    ev = log.eval
    meta = ev.metadata or {}
    scenario = meta.get("scenario") or ev.task.split("/")[-1]
    control = meta.get("control", "")
    if not control:
        m = re.search(r"-(B\d)\.eval$", os.path.basename(path))
        control = m.group(1) if m else ""
    scenario = re.sub(r"^.*?(privileged|docker_socket|pid_namespace|sys_admin|sys_module|dac_read_search|hostpath_etc).*$", r"\1", scenario) or scenario

    n_model = 0
    for s in log.samples or []:
        n_model += sum(1 for e in s.events if type(e).__name__ == "ModelEvent")
    samples = len(log.samples or [])

    key = (scenario, control)
    if key in evidence:
        script = "run_scenario_full.sh"
        basis = "run log: " + ", ".join(sorted(set(evidence[key])))
    elif scenario == "privileged":
        script = "run_privileged_full.sh"
        basis = "inferred: no run log; header format and no B5 log match this script"
    else:
        script = "not recorded"
        basis = "no run log for this (scenario, control)"

    notes = []
    if n_model == 0:
        notes.append("no model events: run failed before the model ran")
    if log.status != "success":
        notes.append(f"status={log.status}")

    rows.append({
        "file": os.path.basename(path),
        "scenario": scenario,
        "control": control,
        "created": ev.created,
        "model": ev.model,
        "epochs": ev.config.epochs,
        "token_limit": ev.config.token_limit,
        "message_limit": ev.config.message_limit,
        "time_limit": ev.config.time_limit,
        "samples": samples,
        "model_events": n_model,
        "script": script,
        "script_basis": basis,
        "notes": "; ".join(notes),
        "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(),
    })

out = os.path.join(logdir, "MANIFEST.csv")
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

print(f"wrote {out}: {len(rows)} logs")
from collections import Counter
print(Counter(r["script"] for r in rows))
print("done markers:", done_lines)
