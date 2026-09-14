# Contributing

## Core rule: verify against the real image

Every workaround in this repo exists because Data Caterer 0.19.1's actual
behavior — tested directly against `datacatering/data-caterer:0.19.1` —
differed from its documentation or from what seemed like it should work.
See `data-caterer/README.md` and each plan file's header comment for the
confirmed list.

Before relying on any Data Caterer feature not already verified here:

1. Write the minimal plan that exercises it.
2. Run it against the real image (`make seed SYS=<sys>`, or a throwaway
   test plan).
3. Check the actual output — row counts, FK resolution, generated values
   — not just that the run exited `0`.

If it doesn't behave as documented, record the finding (see below);
don't leave it as an undocumented one-off workaround.

## Adding or changing a system

- Drop in `config/generator/plan/<sys>/plan.yaml`. `make seed SYS=<sys>`
  picks it up immediately for `FORMAT=csv` — no other changes needed.
- After any plan change, verify row counts and FK resolution directly.
  Don't assume `foreignKeys` / `count.perField` behave the same way for a
  new relationship shape just because they did for an existing one — see
  the bugs already catalogued for how easily this breaks.
- If the plan needs fix-up Data Caterer can't express in-plan, add
  `config/generator/plan/<sys>/postprocess/csv.sh`, run automatically
  after generation with the output directory as `$1`. A system with
  nothing to fix up simply has no such script.
- To add `FORMAT=sql` support, follow `banking`: one `dataSources`
  entry, `connection.type: "@@CONN_TYPE@@"`, and each step's
  `options: {csv: {...}, sql: {...}}`. Never duplicate the `dataSources`
  entry — Data Caterer's YAML parser does not support anchors/aliases.
  If the existing generic `jdbc { "@@SYS@@" {...} }` block in
  `config/generator/common/application.conf.template` (between its
  `@@JDBC_BLOCK_START@@`/`@@JDBC_BLOCK_END@@` markers) isn't generic
  enough for the new system, adjust it there, and add a fixup under
  `config/generator/plan/<sys>/postprocess/sql.sql` if needed.
- Every step's `options` must declare a sub-block for every format
  listed in `config/generator/common/datasources.yaml` (currently `csv`
  and `sql`, unconditionally — not just for systems that opt into
  `FORMAT=sql`), each containing that format's `required_keys`. This is
  a global registry, not a per-system one: adding a genuinely new output
  format goes in `datasources.yaml` and immediately becomes required on
  every existing plan too, not just new ones.
- Run `make validate-plan SYS=<sys>` before committing — see "Writing a
  plan file" below.

## Writing a plan file

Checklist distilled from the confirmed Data Caterer 0.19.1 bugs above and
the conventions both existing plans follow. `make validate-plan` (see
below) enforces everything on this list except the italicized items,
which still need a real `make seed` run per "Core rule" above.

- Never use YAML anchors/aliases (`&`/`*`) — Data Caterer's parser
  rejects them.
- Never target the same step from more than one `foreignKeys` entry —
  only the first populates real values (bug 1). Use a matching
  `incremental` sequence for 1:1s instead.
- Never rely on `cardinality` under `foreignKeys` to expand row count —
  it's a no-op (bug 2). Use `count.perField` instead.
- Never use weighted `oneOf` (`"value->0.35"`) — it always returns the
  last alternative (bug 4). Use a hidden `<field>_bucket` double
  (`omit: true`, `min: 0.0`, `max: 1.0`) plus a `sql` `CASE` on
  cumulative thresholds.
- Don't let a `sql` string literal exactly match another field's name in
  the same step — it gets corrupted (bug 6). Rename one of them.
- Type a field `"boolean"` only when it's a real boolean — `oneOf`
  always yields a string column regardless of declared type. Type those
  fields `"string"` instead.
- Every `<field>_bucket` helper: `type: "double"`, `omit: true`,
  `min: 0.0`, `max: 1.0`.
- Every output `path` must be under `/opt/app/data/<sys>/`, matching the
  volume mount in `config/docker/docker-compose.seed.yaml`.
- Every step's `options` must have a sub-block per format in
  `config/generator/common/datasources.yaml`, each with that format's
  required keys (currently `options.csv: {path, header}` and
  `options.sql: {dbtable}`) — unconditional, every plan.
- Every `foreignKeys[].source`/`generate[]` entry's `dataSource`, `step`,
  and `fields` must reference things that are actually declared
  elsewhere in the plan. `foreignKeys:` itself stays optional — nothing
  requires a plan to have one.
- `dataSources[]` entries need `name` and `steps`; `connection.type`
  doesn't need to be written by hand (`@@CONN_TYPE@@` is resolved at
  render time; a plan may omit `connection` entirely).
- Don't set `sinkOptions.seed` — every run should produce a fresh
  dataset.
- *A field's `sql` can't see another field in the same step once that
  field is populated via `foreignKeys` (bug 5) — don't reference an
  FK-target field from a sibling's `sql`.*
- *Verify row counts and FK resolution directly after any change — see
  "Core rule" above.*

## Validating plan files

`make validate-plan` (or `make validate-plan SYS=<sys>` for one system)
checks the rule-based subset of the checklist above. It's a lint, not a
substitute for a real `make seed` run — that's still the only way to
confirm row counts and FK resolution.

The rules themselves live in `data-caterer/script/validate/plan-rules.yaml`,
a declarative list (regex bans, required keys, a field-name-suffix →
type/options convention, etc.) applied by
`data-caterer/script/validate/validate_plan.py`. Adding a rule of an existing
kind (another line-ban regex, another `_bucket`-style suffix
convention, another required key) is a YAML-only change; a genuinely
new *kind* of check needs a matching function in `validate_plan.py`.
Either way, keep `plan-rules.yaml` and the checklist above in sync. The
dual-format-options rule additionally reads
`config/generator/common/datasources.yaml` directly (not duplicated
into `plan-rules.yaml`) — that's the registry of *what* formats are
required, `plan-rules.yaml` only configures *how* the check reports it.

`validate_plan.py` uses only the standard library — `plan_yaml.py` next
to it is a small hand-rolled loader for the YAML subset this repo's own
config files use (not a general parser; see its header comment), used
instead of adding PyYAML as a dependency. Both run inside a one-off
`python:3.12-slim` container (`docker run --rm ...`, see
`validate-plan.sh`) — this is the "auxiliary Docker image for a one-off
task" case in "Dependencies" below, not a new host dependency; nothing
is `pip install`ed.

Run `make install-hooks` once per clone to enable a pre-commit hook
(`.githooks/pre-commit`) that runs it automatically against any staged
`config/generator/plan/*.yaml` file (validating the staged content, not
the working tree), blocking the commit on failure. Bypass deliberately
with `git commit --no-verify`.

## Documenting a new finding

When you confirm a new Data Caterer behavior — a bug, an undocumented
limitation, an interaction between two features — record it in the plan
file's header comment, alongside the existing numbered list, in the same
shape: what happens (and how you confirmed it), then how it's worked
around (or why it can't be). This is what saves the next person from
rediscovering it by testing again.

## Code style

Default to no comments. Add one only when it captures a hidden
constraint, a workaround for a confirmed bug, or something that would
otherwise cost a real test cycle to rediscover. State the finding and
the fix, not the narrative of how you got there — one sentence beats
one paragraph.

## Dependencies

This repo's only *host* dependency is Docker. Scripts under
`data-caterer/script/` use `sed`/`awk` for rendering; keep new rendering
logic in that vein rather than adding a host-installed tool (Python,
`yq`, `jq`). An auxiliary Docker image invoked for a one-off task (e.g. a
YAML linter run via `docker run --rm ... some-image`) is fine — it
doesn't add a host dependency. If you need real YAML structural
manipulation rather than text substitution, follow `hoist.awk`'s
pattern: one clear `awk` pass, driven by indentation and key text, not
special-cased per call site.

## Generated output

`data/` and `data-caterer/.rendered/` (which holds both the per-run
`application.conf` and the rendered `plan/<sys>.yaml`) are gitignored
and regenerated on every run — never commit them. Add any new generated
path to `.gitignore`.

## Testing `FORMAT=sql` changes

`make seed SYS=<sys> FORMAT=sql` starts an ephemeral Postgres and tears
it down on exit, including on failure (see the `trap` in
`data-caterer/script/seed/seed.sh`). To inspect the container while debugging,
comment out `trap cleanup EXIT` temporarily — never commit that change.

## Commit and PR attribution

No Claude/Anthropic attribution in commits or PRs — see `CLAUDE.md`.
