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

If it doesn't behave as documented, record that finding (see below);
don't leave it as an undocumented one-off workaround.

## Adding or changing a system

- Drop in `data-caterer/plan/<sys>.yaml`. `make seed SYS=<sys>` picks it
  up immediately for `FORMAT=csv` — no other changes needed.
- After any plan change, verify row counts and FK resolution directly.
  Don't assume `foreignKeys`/`count.perField` behave the same way for a
  new relationship shape just because they did for an existing one —
  see the bugs already catalogued for how easily this breaks.
- If the plan needs fix-up Data Caterer can't express in-plan, add
  `data-caterer/postprocess/csv/<sys>.sh`, run automatically after
  generation with the output directory as `$1`. A system with nothing to
  fix up simply has no such script.
- To add `FORMAT=sql` support, follow `banking.yaml`: one `dataSources`
  entry, `connection.type: "@@CONN_TYPE@@"`, and each step's `options:
  {csv: {...}, sql: {...}}`. Never duplicate the `dataSources` entry —
  Data Caterer's YAML parser does not support anchors/aliases. Add a
  matching `jdbc { <sys> {...} } ` block to
  `application-jdbc.conf.template` if the existing one isn't generic
  enough, and a fixup under `data-caterer/postprocess/sql/<sys>.sql` if
  needed.

## Documenting a new finding

When you confirm a new Data Caterer behavior — a bug, an undocumented
limitation, an interaction between two features — record it in the plan
file's header comment, alongside the existing numbered list, in the same
shape: what happens (and how you confirmed it), then how it's worked
around (or why it can't be). The value of these comments is that nobody
has to rediscover the same thing by testing again.

## Comments

Default to no comments. Add one only when it captures a hidden
constraint, a workaround for a confirmed bug, or something that would
otherwise cost a real test cycle to rediscover. State the finding and the
fix, not the narrative of how you got there — one sentence beats one
paragraph.

## Dependencies

This repo's only *host* dependency is Docker. Scripts under
`data-caterer/script/` use `sed`/`awk` for rendering; keep new rendering
logic in that vein rather than adding a host-installed tool (Python,
`yq`, `jq`). An auxiliary Docker image invoked for a one-off task (for
example, a YAML linter run via `docker run --rm ... some-image`) is fine
— it doesn't add a host dependency. If you need real YAML structural
manipulation rather than text substitution, follow `hoist.awk`'s pattern:
one clear `awk` pass, driven by indentation and key text, not
special-cased per call site.

## Generated output

`data/`, `data-caterer/application.conf`, and
`data-caterer/plan/.rendered/` are gitignored and regenerated on every
run — never commit them. Add any new generated path to `.gitignore`.

## Testing `FORMAT=sql` changes

`make seed SYS=<sys> FORMAT=sql` starts an ephemeral Postgres and tears
it down on exit, including on failure (see the `trap` in
`data-caterer/script/seed.sh`). To inspect the container while debugging,
comment out `trap cleanup EXIT` temporarily — never commit that change.

## Attribution

No Claude/Anthropic attribution in commits or PRs — see `CLAUDE.md`.
