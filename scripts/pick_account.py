#!/usr/bin/env python3
"""Print Claude config dirs, best first, for `claude -p` (01-script.sh).

Reads the harness's persisted per-account usage (it polls every login
already; hitting the usage endpoint ourselves gets 429s) from
<harness>/.clawd-harness.sessions.json. One line per ORG (several dirs can
share one subscription pool), fresh readings before stale ones, least
weekly usage first, pools at >= HOT% dropped. No file / no accounts ->
prints nothing and the caller falls back to the default ~/.claude login.

  python3 pick_account.py [harness_dir]
"""
import json, os, sys, time

HOT = 97.0          # the harness's SUB_HOT: ~3% left is not a pool
STALE_S = 12 * 3600 # a reading older than this ranks last (still usable)

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "..")
path = os.path.join(root, ".clawd-harness.sessions.json")
try:
    accounts = json.load(open(path)).get("accounts", [])
except Exception:
    sys.exit(0)

best = {}
for a in accounts:
    u = a.get("usage") or {}
    pct, at, d = u.get("pct"), u.get("goodAt") or 0, a.get("config_dir")
    if not d or pct is None or not a.get("ready") or not os.path.isdir(d):
        continue
    org = a.get("org") or d
    if org not in best or at > best[org][1]:
        best[org] = (pct, at, d, a.get("name"))

now = time.time()
rows = sorted(best.values(), key=lambda r: (now - r[1] > STALE_S, r[0]))
for pct, at, d, name in rows:
    if pct < HOT:
        print(d)
    else:
        print(f"skip {name}: {pct:.0f}% used", file=sys.stderr)
