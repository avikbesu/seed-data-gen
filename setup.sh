#!/usr/bin/env bash
# Generates the banking sample dataset and, if a destination path is
# given, copies the result there (replacing whatever was at that path).
#
# Every path below is resolved relative to this script's own location
# (via BASH_SOURCE), not to the caller's current directory or any
# hardcoded name -- so this works no matter what directory name or
# nesting depth this repo is checked out under, e.g. as a git submodule
# added at a path other than "seed-data-banking". A parent repo should
# locate this script by identity (its git remote), not by a fixed path --
# see README.md's "As a submodule" section for the pattern.
#
# Usage:
#   ./setup.sh                  # generate into ./data/banking only
#   ./setup.sh /path/to/dest    # also copy the result to dest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

make seed-banking

dest="${1:-}"
if [ -n "$dest" ]; then
	mkdir -p "$(dirname "$dest")"
	rm -rf "$dest"
	cp -r "$SCRIPT_DIR/data/banking" "$dest"
fi
