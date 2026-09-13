# seed-data-banking

Generates a simplified, relationally-intact sample banking dataset (party,
party_address, party_contact, party_profile, accounts, account_contracts,
transactions) as CSV files, using [Data Caterer
0.19.1](https://data.catering/0.19.1/), a Spark-based data generation tool.

Standalone and dependency-free (just Docker) so it can be dropped into
other repos as a git submodule wherever sample banking data is useful.

## Usage

```
make seed
```

Output lands in `data/banking/` (gitignored) -- one clean CSV file per
table, with a header row and no leftover Spark part-files.

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
into the parent repo at a fixed, predictable path:
`.seed-modules/banking`, regardless of the submodule's real path.

The parent repo's own Makefile then only ever needs to know about that
fixed path, never the submodule's actual location:

```makefile
seed: ## Populate seed data for a system, e.g. `make seed SYS=banking` (link it first: run <module>/setup.sh once)
	@test -n "$(SYS)" || { echo "usage: make seed SYS=<system>  (e.g. SYS=banking)" >&2; exit 1; }
	@test -d .seed-modules/$(SYS) || { echo "seed: no module linked for SYS=$(SYS) -- run its setup.sh from the repo root first" >&2; exit 1; }
	rm -rf data/$(SYS)
	$(MAKE) -C .seed-modules/$(SYS) seed
	mkdir -p data
	cp -r .seed-modules/$(SYS)/data/$(SYS) data/$(SYS)
```

`SYS` is which seed module to run -- `banking` for this repo, derived
by `setup.sh` from the name of this repo's own plan file
(`data-caterer/plan/banking.yaml` -> `banking`), not hardcoded. A future
`seed-data-<sys>` module just needs its own `data-caterer/plan/<sys>.yaml`
-- its `setup.sh` picks up `<sys>` automatically and links itself in at
`.seed-modules/<sys>`, no script edits needed. So a repo that seeds
multiple systems needs only the one generic target above, not one per
module. Add `.seed-modules/` to the parent repo's `.gitignore` -- it's
local, regenerated state, not something to commit.

## Layout

- `docker/docker-compose.seed.yaml` -- one-shot `docker compose run --rm`
  service definition for the Data Caterer image.
- `data-caterer/application.conf` -- Spark runtime defaults (HOCON).
- `data-caterer/plan/banking.yaml` -- the schema: 7 tables, their fields,
  and the relationships between them. See that file's own header comment
  for the full design rationale, including every real Data Caterer bug
  found while building it and how each is worked around.
- `data-caterer/README.md` -- detailed notes on the dataset shape and the
  Data Caterer 0.19.1 issues worked around in the plan.

See `data-caterer/README.md` for the full schema notes and known Data
Caterer issues.
