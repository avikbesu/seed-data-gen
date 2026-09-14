#!/usr/bin/env bash
# Rule-based validator for config/generator/plan/*.yaml files. Rules live in
# plan-rules.yaml (declarative -- see its header comment) and are applied by
# validate_plan.py, run in a one-off official Python container (no host
# dependency beyond Docker, per CONTRIBUTING.md's "Dependencies" section
# -- the script uses only the standard library, so nothing is pip-installed).
#
# Usage:
#   data-caterer/script/validate-plan.sh                 # every tracked plan
#   data-caterer/script/validate-plan.sh <plan-file>...   # specific plan(s)
set -euo pipefail

# Pinned to the 3.12 minor line (not a full patch pin like the
# data-caterer/postgres images use) -- this script only needs a recent
# stdlib, so isn't sensitive to the exact patch version.
PYTHON_IMAGE="python:3.12-slim"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

cd "$repo_root"

if [ "$#" -eq 0 ]; then
  set -- config/generator/plan/*.yaml
fi

args=(--rules data-caterer/script/plan-rules.yaml)
for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "validate-plan: no such file: $f" >&2
    exit 1
  fi
  args+=(--file "$f")
done

docker run --rm \
  -v "$repo_root":/workspace:ro \
  -w /workspace \
  "$PYTHON_IMAGE" \
  python3 data-caterer/script/validate_plan.py "${args[@]}"
