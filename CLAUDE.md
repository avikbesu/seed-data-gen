# Repo conventions

## Attribution

Do not add any Claude/Anthropic attribution to git commit messages or
pull request descriptions — no `Co-Authored-By: Claude ...` trailer, no
`Claude-Session` link, no "Generated with Claude Code" footer. Commits
and PRs in this repo read as authored solely by the human contributor.

## Repo highlights

For full agent-facing guidance (build/run/verify, layout, gotchas), see
`AGENTS.md`. The essentials:

- Relationally-intact sample datasets via [Data Caterer
  0.19.1](https://data.catering/0.19.1/), driven entirely by Docker — no
  other dependency. Meant to be dropped into other repos as a git
  submodule (see README.md's "As a submodule" section).
- Each dataset is a "system": `config/generator/plan/<sys>.yaml` plus an
  optional `postprocess/csv/<sys>.sh` (and, for `banking`,
  `postprocess/sql/<sys>.sql` for `FORMAT=sql`). Two exist today:
  `banking` and `retail`. Adding one is just dropping in a new plan file.
  `config/generator/common/datasources.yaml` is a separate, global
  registry of which output formats this repo supports at all (currently
  `csv`/`sql`) and each one's required `options` keys — every step in
  every plan must declare all of them, regardless of system.
- Run/verify with `make seed SYS=banking|retail`. No test suite —
  verification means generating against the real image and checking row
  counts and zero orphan foreign keys.
- The plans document seven real Data Caterer 0.19.1 bugs found by direct
  testing, not the docs (see `data-caterer/README.md` and each plan
  file's header comment) — assume nothing about documented behavior
  without checking the real image.
- `make seed SYS=banking FORMAT=sql` generates the same data into an
  ephemeral Postgres and `pg_dump`s it, from the same `banking.yaml`
  `dataSources` entry (no duplicated fields/`foreignKeys`) via
  `connection.type`/`options: {csv:, sql:}` placeholders that
  `data-caterer/script/seed.sh` + `hoist.awk` resolve at render time. See
  `banking.yaml`'s header comment before editing anything under `options:`.
- `data/`, `data-caterer/application.conf`, and
  `data-caterer/plan/.rendered/` are gitignored/regenerated every run —
  never commit them.

## Writing or editing a plan file

Before writing to `config/generator/plan/<sys>.yaml`, apply this
checklist — each item encodes a confirmed Data Caterer 0.19.1 bug or a
convention both existing plans follow (full rationale in
`CONTRIBUTING.md`'s "Writing a plan file" section):

- No YAML anchors/aliases (`&`/`*`) — Data Caterer's parser rejects them.
  Write repeated field lists out in full.
- No more than one `foreignKeys` entry targeting the same step — only
  the first populates real values. Use a matching `incremental` sequence
  for a 1:1 instead.
- No `cardinality` under `foreignKeys` — it's a no-op. Use
  `count.perField` to expand a child's row count.
- No weighted `oneOf` (`"value->0.35"`) — always returns the last
  alternative. Use a hidden `<field>_bucket` double (`omit: true`,
  `min: 0.0`, `max: 1.0`) plus a `sql` `CASE` on cumulative thresholds.
- No `sql` string literal that exactly matches another field's name in
  the same step — it gets corrupted at generation time.
- No `type: "boolean"` field driven by `oneOf` — `oneOf` always yields a
  string column regardless of declared type; type it `"string"`.
- No field's `sql` referencing another field in the same step that's
  populated via `foreignKeys` — evaluated before the FK pass runs.
- Every `foreignKeys[].source`/`generate[]` entry's `dataSource`, `step`,
  `fields` must all be real (declared elsewhere in the same plan).
  `foreignKeys:` itself is optional.
- `dataSources[]` needs `name` + `steps` only — don't hand-write
  `connection.type`, it's resolved from `@@CONN_TYPE@@` at render time.
- Every step's `options` needs a sub-block per format declared in
  `config/generator/common/datasources.yaml` (currently `csv`/`sql`),
  each with that format's required keys — unconditional on every plan,
  not just ones that support `FORMAT=sql`.
- Every output `path` under `/opt/app/data/<sys>/`; no
  `sinkOptions.seed`.

After editing, run `make validate-plan SYS=<sys>` (lints the rule-based
subset above) and then a real `make seed SYS=<sys>` (the only way to
confirm row counts and FK resolution — no test suite substitutes for
it). `make install-hooks` enables a pre-commit hook that runs
`validate-plan` automatically.
