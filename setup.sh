#!/usr/bin/env bash
# Links this seed module into a parent repo that has it added as a git
# submodule (under any path/name), so the parent's own `make seed
# SYS=banking` can find it.
#
# This resolves its own real location via BASH_SOURCE, not the caller's
# current directory or any hardcoded name -- so it works no matter what
# directory name or nesting depth this repo is checked out under, e.g.
# as a git submodule added at a path other than "seed-data-banking".
#
# Creates <target-repo-root>/.seed-modules/banking, a symlink pointing at
# this submodule's real directory. From there, the parent repo's `make
# seed SYS=banking` target runs `make -C .seed-modules/banking seed`
# (this repo's own generation target -- see Makefile) and copies its
# output into the parent repo's data/banking/. See README.md's "As a
# submodule" section for the parent-side Makefile snippet.
#
# Usage (run once, from the target repo root, after `git submodule add`):
#   ./path/to/seed-data-banking/setup.sh [target-repo-root]
# target-repo-root defaults to the current directory.
set -euo pipefail

SYS="banking"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$(cd "${1:-.}" && pwd)"

mkdir -p "$TARGET_ROOT/.seed-modules"
ln -sfn "$(realpath --relative-to="$TARGET_ROOT/.seed-modules" "$SCRIPT_DIR")" "$TARGET_ROOT/.seed-modules/$SYS"

echo "Linked .seed-modules/$SYS -> $SCRIPT_DIR"
echo "Run: make seed SYS=$SYS   (from $TARGET_ROOT)"
