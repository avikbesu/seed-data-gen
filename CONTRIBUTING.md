# Contributing

## Core rule: verify against the real image, never trust the docs

Every workaround in this repo (see `data-caterer/README.md` and each plan
file's header comment) exists because Data Caterer 0.19.1's actual
behavior, tested directly against `datacatering/data-caterer:0.19.1`,
differed from what its docs describe or what seemed like it should work.
Before relying on any Data Caterer feature you haven't already seen
verified here:

1. Write the minimal plan that exercises it.
2. Run it against the real image (`make seed SYS=<sys>` or a throwaway
   test plan).
3. Check the actual output -- row counts, FK resolution, generated
   values -- not just that the run exited 0.

If it doesn't behave as documented, that's a finding worth recording (see
below), not a one-off workaround to leave undocumented.

## Adding or changing a system

- Drop in `data-caterer/plan/<sys>.yaml`; `make seed SYS=<sys>` picks it
  up immediately, no other changes needed for `FORMAT=csv`.
- After any plan change, verify directly: row counts match what you
  expect, and every FK-shaped value resolves to a real parent row (zero
  orphans). Don't assume `foreignKeys`/`count.perField` behave the same
  way for a new relationship shape just because they did for an existing
  one -- see the bugs already catalogued for how easily this breaks.
- If the plan needs fix-up Data Caterer can't express in-plan, add
  `data-caterer/postprocess/csv/<sys>.sh` (run automatically after
  generation, output dir as `$1`). A system with nothing to fix up just
  doesn't have one.
- To add `FORMAT=sql` support for a system, follow `banking.yaml` as the
  reference: one `dataSources` entry, `connection.type: "@@CONN_TYPE@@"`,
  and each step's `options: {csv: {...}, sql: {...}}` -- never two
  duplicated `dataSources` entries (YAML anchors don't work here,
  confirmed directly). Add a matching `jdbc { <sys> {...} }` block to
  `application-jdbc.conf.template` if it isn't already generic enough,
  and a SQL fixup under `data-caterer/postprocess/sql/<sys>.sql` if
  needed.

## Documenting a new finding

When you confirm a new real Data Caterer behavior (a bug, an
undocumented limitation, a gotcha in how two features interact), write it
into the plan file's own header comment, numbered alongside the existing
list, in the same shape: **what happens** (confirmed how), then **worked
around** (or why it can't be). Don't just fix it silently -- the whole
value of these comments is that the next person doesn't have to
rediscover the same thing by testing again.

## Comments: concise, and only for the non-obvious

Default to no comments. Add one only when it explains a hidden
constraint, a workaround for a specific confirmed bug, or something that
would otherwise cost someone a real test cycle to rediscover. State the
finding and the fix -- skip the narrative of how you got there. If a
comment can be said in one sentence instead of a paragraph, use one
sentence.

## Keep it dependency-free

This repo's only dependency is Docker (see the top-level README). Don't
add a scripting dependency (Python, `yq`, `jq`, etc.) to
`data-caterer/script/`; `sed`/`awk` are the tools in use, and any new
rendering logic should stay in that vein. If you genuinely need real YAML
structure manipulation (not just text substitution or line-range
deletion), `awk` state machines like `hoist.awk` are the established
pattern here -- keep it to one clear pass, driven by indentation/key text
rather than special-cased per call site.

## Never commit generated output

`data/`, `data-caterer/application.conf`, and `data-caterer/plan/.rendered/`
are gitignored on purpose -- they're regenerated every run. If you add a
new rendered/generated path, add it to `.gitignore` too.

## Testing `FORMAT=sql` changes

`make seed SYS=<sys> FORMAT=sql` starts an ephemeral Postgres, generates
into it, and tears it down on exit (including on failure -- see the
`trap` in `data-caterer/script/seed.sh`). If you're debugging interactively
and need the container to stay up, comment out the `trap cleanup EXIT`
line temporarily -- never leave that commented out in a commit.

## Attribution

No Claude/Anthropic attribution in commits or PRs -- see `CLAUDE.md`.
