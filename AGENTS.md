# AGENTS.md

Guidance for AI coding agents working in this repo.

For what this repo is, its layout, commands, how to add a system, submodule
usage, and every known Data Caterer 0.19.1 gotcha and its workaround, read
`README.md` (top-level) and `data-caterer/README.md` first — this file only
adds what those don't cover.

## Agent-specific notes

- There is no test suite. `make validate-plan SYS=<sys>` is a fast lint
  (rules in `data-caterer/script/validate/plan-rules.yaml`, applied by
  `validate_plan.py` in a one-off `python:3.12-slim` container — see
  CLAUDE.md's "Writing or editing a plan file") — it catches known-bad
  patterns but is not verification. Treat `make seed SYS=<sys>` against the real
  `datacatering/data-caterer:0.19.1` image as the real test: after any plan or
  postprocess change, run it and check the output CSVs in `data/<sys>/`
  (gitignored) for correct row counts and zero orphan foreign keys.
- Never take Data Caterer's documented behavior on trust — every workaround
  already in this repo (see the READMEs above) was found by testing directly
  against the real image, and new plan changes should be verified the same
  way, not assumed correct from the docs.
- No commit message or PR description in this repo should carry any
  Claude/Anthropic attribution (no `Co-Authored-By: Claude ...` trailer, no
  `Claude-Session` link, no "Generated with Claude Code" footer) — see
  `CLAUDE.md`.
