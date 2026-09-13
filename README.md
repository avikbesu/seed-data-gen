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

Then from the parent repo, either run `make -C seed-data-banking
seed-banking` directly, or add a delegating target to the parent's own
Makefile.

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
