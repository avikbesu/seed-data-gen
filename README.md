# seed-data-banking

Generates sample datasets as CSV files using [Data Caterer
0.19.1](https://data.catering/0.19.1/), a Spark-based data generation
tool. Each dataset is a "system": a plan file under `data-caterer/plan/`
plus an optional post-processing script. Ships two systems so far:

- `banking` -- a simplified banking dataset (party, party_address,
  party_contact, party_profile, accounts, account_contracts,
  transactions).
- `retail` -- a simplified retail store dataset (customer, merchant,
  employee, shift_roster, merchant_order, invoice).

Both are relationally intact -- every foreign-key-shaped value resolves
to a real parent row, verified directly against the real image, not
assumed (see each plan file's own header comment for how and why).

Standalone and dependency-free (just Docker) so it can be dropped into
other repos as a git submodule wherever sample data is useful.

## Usage

```
make seed SYS=banking
make seed SYS=retail
```

Output lands in `data/<sys>/` (gitignored) -- one clean CSV file per
table, with a header row and no leftover Spark part-files.

## Adding a system

Drop in a new `data-caterer/plan/<sys>.yaml` and `make seed SYS=<sys>`
works immediately -- nothing else needs editing. Its steps' output
`path`s must write under `/opt/app/data/<sys>/` to match the volume
mount in `docker/docker-compose.seed.yaml`.

For the plan format and Data Caterer gotchas, see `banking.yaml`'s
header comment (the full list of real bugs found, e.g. why a weighted
`oneOf` can't be trusted) and `retail.yaml`'s header comment (why it
uses only one real `foreignKeys` block despite having several
many-to-one relationships, and the deterministic-reference techniques
it uses for the rest instead). Whatever you add, verify it directly
against the real image (`make seed SYS=<sys>`, then check row counts
and that every FK-shaped value resolves to a real parent row) rather
than assuming Data Caterer's documented behavior holds -- both existing
plans found real discrepancies this way.

If the plan needs fix-up that Data Caterer can't express (like
banking's loan-only Guarantor rule -- see `data-caterer/README.md`),
add an executable `data-caterer/postprocess/<sys>.sh`; the `seed` target
runs it automatically after generation, passing the output directory as
`$1`. A system with nothing to fix up just doesn't have one (retail
doesn't).

## As a submodule

```
git submodule add https://github.com/avikbesu/seed-data-banking.git seed-data-banking
```

The path you give `git submodule add` is just a suggestion -- nothing in
this repo depends on it, and nothing in the parent repo should hardcode
it either (submodules get renamed/moved). Instead, run `setup.sh` once
from the parent repo's root (`./path/to/seed-data-banking/setup.sh`,
wherever the submodule actually landed) -- it's self-locating (resolves
every path from its own location via `BASH_SOURCE`), and it links itself
into the parent repo at a fixed, predictable path per system it finds:
`.seed-modules/<sys>` for each `data-caterer/plan/<sys>.yaml` -- e.g.
`.seed-modules/banking` today, regardless of the submodule's real path.

The parent repo's own Makefile then only ever needs to know about that
fixed `.seed-modules/<sys>` convention, never the submodule's actual
location or how many systems it provides:

```makefile
seed: ## Populate seed data for a system, e.g. `make seed SYS=banking` (link it first: run <module>/setup.sh once)
	@test -n "$(SYS)" || { echo "usage: make seed SYS=<system>  (e.g. SYS=banking)" >&2; exit 1; }
	@test -d .seed-modules/$(SYS) || { echo "seed: no module linked for SYS=$(SYS) -- run its setup.sh from the repo root first" >&2; exit 1; }
	rm -rf data/$(SYS)
	$(MAKE) -C .seed-modules/$(SYS) seed SYS=$(SYS)
	mkdir -p data
	cp -r .seed-modules/$(SYS)/data/$(SYS) data/$(SYS)
```

This one target works unmodified for every system any linked module
provides, present or future -- a parent repo seeding multiple systems
(from this module or several) needs no per-system Makefile logic. Add
`.seed-modules/` to the parent repo's `.gitignore` -- it's local,
regenerated linkage, not something to commit.

## Layout

- `docker/docker-compose.seed.yaml` -- one-shot `docker compose run --rm`
  service definition for the Data Caterer image, parameterized by `SYS`.
- `data-caterer/application.conf.template` -- Spark runtime defaults
  (HOCON), shared by every system. Rendered into `application.conf`
  (gitignored) each run by `make seed SYS=<sys>`.
- `data-caterer/plan/<sys>.yaml` -- one per system: the schema, fields,
  and relationships. `banking.yaml`'s header comment has the full design
  rationale, including every real Data Caterer bug found while building
  it and how each is worked around.
- `data-caterer/postprocess/<sys>.sh` -- optional, one per system that
  needs it: fix-up Data Caterer can't express in the plan itself.
- `data-caterer/README.md` -- detailed notes on the banking dataset
  shape and the Data Caterer 0.19.1 issues worked around in its plan.

See `data-caterer/README.md` for the full schema notes and known Data
Caterer issues.
