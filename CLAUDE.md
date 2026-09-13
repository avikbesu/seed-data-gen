# Repo conventions

- Do not add any Claude/Anthropic attribution to git commit messages or pull
  request descriptions (no `Co-Authored-By: Claude ...` trailer, no
  `Claude-Session` link, no "Generated with Claude Code" footer). Commits and
  PRs in this repo should read as authored solely by the human contributor.

## Repo highlights

For full agent-facing guidance (build/run/verify, layout, gotchas), see
`AGENTS.md`. The essentials:

- Relationally-intact sample datasets via [Data Caterer
  0.19.1](https://data.catering/0.19.1/), driven entirely by Docker — no
  other dependency. Meant to be dropped into other repos as a git
  submodule (see README.md's "As a submodule" section).
- Each dataset is a "system": `data-caterer/plan/<sys>.yaml` plus an
  optional `postprocess/csv/<sys>.sh` (and, for `banking`,
  `postprocess/sql/<sys>.sql` for `FORMAT=sql`). Two exist: `banking`
  and `retail`. Adding one is just dropping in a new plan file.
- Run/verify with `make seed SYS=banking|retail`. No test suite —
  verification means generating against the real image and checking row
  counts and zero orphan foreign keys.
- The plans document seven real Data Caterer 0.19.1 bugs found by direct
  testing, not the docs (see `data-caterer/README.md` and each plan
  file's header comment) — assume nothing about documented behavior
  without checking the real image.
- `make seed SYS=banking FORMAT=sql` generates the same data into an
  ephemeral Postgres and `pg_dump`s it, from the SAME `banking.yaml`
  `dataSources` entry (no duplicated fields/`foreignKeys`) via
  `connection.type`/`options: {csv:, sql:}` placeholders that
  `data-caterer/script/seed.sh` + `hoist.awk` resolve at render time. See
  `banking.yaml`'s header comment before editing anything under `options:`.
- `data/`, `data-caterer/application.conf`, and
  `data-caterer/plan/.rendered/` are gitignored/regenerated every run —
  never commit them.
