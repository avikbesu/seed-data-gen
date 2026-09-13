# seed-data-banking

Generates a simplified, relationally-intact sample banking dataset (party,
party_address, party_contact, party_profile, accounts, account_contracts,
transactions) as CSV files, using [Data Caterer
0.19.1](https://data.catering/0.19.1/), a Spark-based data generation tool.

Standalone and dependency-free (just Docker) so it can be dropped into
other repos as a git submodule wherever sample banking data is useful.

## Usage

```
make seed-banking
```

Output lands in `data/banking/` (gitignored) -- one clean CSV file per
table, with a header row and no leftover Spark part-files.

## As a submodule

```
git submodule add https://github.com/avikbesu/seed-data-banking.git seed-data-banking
```

The path you give `git submodule add` is just a suggestion -- nothing in
this repo depends on it, and nothing in the parent repo should hardcode
it either (submodules get renamed/moved). `setup.sh` is self-locating
(it resolves every path from its own location, via `BASH_SOURCE`), so
the parent repo only needs to *find* the submodule -- by identity (its
git remote), not by a fixed path -- and hand `setup.sh` a destination.
`git submodule foreach` does exactly that lookup:

```makefile
seed-banking: ## Generate sample banking data into data/banking/, wherever the seed-data-banking submodule is checked out
	git submodule update --init --recursive
	git submodule foreach --quiet 'case "$$(git remote get-url origin 2>/dev/null)" in \
		*seed-data-banking*) ./setup.sh "$$toplevel/data/banking" ;; esac'
	@test -d data/banking || { echo "seed-banking: no seed-data-banking submodule found" >&2; exit 1; }
```

This keeps working if the submodule is later moved or renamed -- e.g.
`git submodule add ... vendor/seed-data` -- with no changes needed on
the parent repo's side. Calling `setup.sh` directly (`./path/to/setup.sh
[dest]`) also works for a one-off run, e.g. right after `git submodule
add`, to populate the initial dataset.

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
