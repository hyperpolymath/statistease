#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# validate-workflow-yaml.sh — every .github/workflows/*.yml must PARSE.
#
# WHY THIS EXISTS
# ---------------
# A malformed workflow is not a red check. GitHub Actions rejects it at PARSE
# time, which produces zero jobs and NO CHECK RUN AT ALL — the gate silently
# ceases to exist while the board still reads green. `gh pr checks` shows
# nothing wrong. The only visible tell is that `gh run list` starts printing the
# workflow's PATH instead of its NAME.
#
# This repo has hit that twice in one day, from the same cause both times: a
# sweep that appends `actions: read` after every `permissions:` line. Four
# workflows declare permissions in the SCALAR form —
#
#     permissions: read-all
#
# — and hanging a mapping key under a scalar is invalid YAML:
#
#     permissions: read-all
#       actions: read        # "mapping values are not allowed here"
#
# It was fixed in PR #64 and reintroduced by PR #68, because the sweep matched
# `permissions:` as TEXT rather than as a YAML node. The insertion is redundant
# regardless: `read-all` already grants every read scope, `actions: read`
# included.
#
# So this check is deliberately dumb and total: parse every workflow, fail on
# any that does not. It cannot be satisfied by a sweep that only looks at text.

set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "validate-workflow-yaml: python3 not found — cannot verify workflows" >&2
  exit 1
fi

python3 - "$@" <<'PY'
import glob, sys

try:
    import yaml
except ImportError:
    print("validate-workflow-yaml: PyYAML not installed — cannot verify workflows",
          file=sys.stderr)
    sys.exit(1)

files = sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml"))
if not files:
    print("validate-workflow-yaml: no workflow files found", file=sys.stderr)
    sys.exit(1)

bad = []
for f in files:
    try:
        doc = yaml.safe_load(open(f))
    except Exception as e:
        bad.append((f, str(e).splitlines()[0]))
        continue
    # A workflow that parses but has no jobs is equally inert.
    if not isinstance(doc, dict) or not doc.get("jobs"):
        bad.append((f, "parses but declares no jobs — would run nothing"))

if bad:
    print("ERROR: unparseable or inert workflow(s) — these produce NO check run,")
    print("       not a red X, so CI would look green while the gate is dead:\n")
    for f, err in bad:
        print(f"  {f}\n      {err}")
    print("\nIf this is `actions: read` under `permissions: read-all`, delete the")
    print("added line: `read-all` already grants every read scope.")
    sys.exit(1)

print(f"validate-workflow-yaml: all {len(files)} workflows parse and declare jobs")
PY
