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
# SYS is derived from this repo's own plan file, not hardcoded --
# data-caterer/plan/banking.yaml means SYS=banking. A future
# seed-data-<sys> module just needs its own data-caterer/plan/<sys>.yaml;
# this script doesn't need editing.
#
# Creates <target-repo-root>/.seed-modules/<sys>, a symlink pointing at
# this submodule's real directory. From there, the parent repo's `make
# seed SYS=<sys>` target runs `make -C .seed-modules/<sys> seed` (this
# repo's own generation target -- see Makefile) and copies its output
# into the parent repo's data/<sys>/. See README.md's "As a submodule"
# section for the parent-side Makefile snippet.
#
# Usage (run once, from the target repo root, after `git submodule add`):
#   ./path/to/seed-data-banking/setup.sh [target-repo-root]
# target-repo-root defaults to the current directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$(cd "${1:-.}" && pwd)"

plan_files=("$SCRIPT_DIR"/data-caterer/plan/*.yaml)
if [ "${#plan_files[@]}" -ne 1 ]; then
	echo "setup.sh: expected exactly one plan file in data-caterer/plan/, found ${#plan_files[@]}" >&2
	exit 1
fi
SYS="$(basename "${plan_files[0]}" .yaml)"

mkdir -p "$TARGET_ROOT/.seed-modules"
ln -sfn "$(realpath --relative-to="$TARGET_ROOT/.seed-modules" "$SCRIPT_DIR")" "$TARGET_ROOT/.seed-modules/$SYS"

echo "Linked .seed-modules/$SYS -> $SCRIPT_DIR"
echo "Run: make seed SYS=$SYS   (from $TARGET_ROOT)"
