#!/usr/bin/env bash
# Links this seed module into a parent repo that has it added as a git
# submodule (under any path/name), so the parent's own `make seed
# SYS=<sys>` can find it.
#
# This resolves its own real location via BASH_SOURCE, not the caller's
# current directory or any hardcoded name -- so it works no matter what
# directory name or nesting depth this repo is checked out under, e.g.
# as a git submodule added at a path other than "seed-data-banking".
#
# One symlink is created per system this module provides -- one per
# data-caterer/plan/<sys>.yaml file, so a single module can serve
# multiple systems (e.g. this repo could grow a
# data-caterer/plan/retail.yaml alongside banking.yaml, and both would
# be linked in). Nothing here needs editing to add a system -- just drop
# in a new plan file (and an optional data-caterer/postprocess/<sys>.sh).
#
# Creates <target-repo-root>/.seed-modules/<sys> for each system, a
# symlink pointing at this submodule's real directory. From there, the
# parent repo's `make seed SYS=<sys>` target runs `make -C
# .seed-modules/<sys> seed SYS=<sys>` (this repo's own generation target
# -- see Makefile) and copies its output into the parent repo's
# data/<sys>/. See README.md's "As a submodule" section for the
# parent-side Makefile snippet.
#
# Usage (run once, from the target repo root, after `git submodule add`):
#   ./path/to/seed-data-banking/setup.sh [target-repo-root]
# target-repo-root defaults to the current directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$(cd "${1:-.}" && pwd)"

plan_files=("$SCRIPT_DIR"/data-caterer/plan/*.yaml)
if [ ! -e "${plan_files[0]}" ]; then
	echo "setup.sh: no plan files found in data-caterer/plan/" >&2
	exit 1
fi

mkdir -p "$TARGET_ROOT/.seed-modules"
for plan_file in "${plan_files[@]}"; do
	sys="$(basename "$plan_file" .yaml)"
	ln -sfn "$(realpath --relative-to="$TARGET_ROOT/.seed-modules" "$SCRIPT_DIR")" "$TARGET_ROOT/.seed-modules/$sys"
	echo "Linked .seed-modules/$sys -> $SCRIPT_DIR"
done
