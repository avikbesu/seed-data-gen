# seed-data-gen

Generates sample datasets using [Data Caterer
0.19.1](https://data.catering/0.19.1/), a Spark-based data generation
tool. Each dataset is a "system": a plan file under `data-caterer/plan/`
plus an optional post-processing script. Output format is `csv` (default)
or `sql` -- a Postgres dump -- via `FORMAT=csv|sql` (see "Postgres dump"
below); `sql` support is currently plan-by-plan, not automatic for every
system. Ships two systems so far:

- `banking` -- a simplified banking dataset (party, party_address,
  party_contact, party_profile, accounts, account_contracts,
  transactions). Supports `FORMAT=sql`.
- `retail` -- a simplified retail store dataset (customer, supplier,
  product, employee, shift_roster, order, order_item, invoice).

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
table, with a header row and no leftover Spark part-files. This is
`FORMAT=csv`, the default -- see "Postgres dump" below for `FORMAT=sql`.

## Postgres dump (`FORMAT=sql`)

```
make seed SYS=banking FORMAT=sql
```

`FORMAT` defaults to `csv`. `FORMAT=sql` starts an ephemeral Postgres
container, generates the same dataset directly into it, applies that
system's SQL fixup if present (`data-caterer/postprocess/sql/<sys>.sql`),
runs `pg_dump` into `data/<sys>/<sys>.sql` (`CREATE DATABASE`/`CREATE
TABLE` plus an `INSERT` per row), then tears the container down. Never
reachable outside Docker (no host port published), never persists past
one run.

Both formats live in ONE `dataSources` entry per plan -- no duplicated
fields or `foreignKeys`. `connection.type: "@@CONN_TYPE@@"` and each
step's `options: {csv: {...}, sql: {...}}` are resolved at render time by
`data-caterer/script/seed.sh`: substitutes `@@CONN_TYPE@@` to
`csv`/`jdbc` (`"jdbc"` is Spark's real format name), then
`data-caterer/script/hoist.awk` drops the inactive format's block and
de-indents the active one's children into the flat `options:` shape Data
Caterer expects. Real jdbc credentials live in
`data-caterer/application-jdbc.conf.template`, appended only for
`FORMAT=sql` (a `jdbc {}` block merely existing forces jdbc validation on
any matching-named dataSource, breaking `FORMAT=csv` if left in
unconditionally -- confirmed directly). See `banking.yaml`'s header
comment for the full rationale and every finding along the way.

Only `banking` has Postgres support today. `FORMAT=sql` on a plan with no
`@@CONN_TYPE@@` token (like `retail`) fails fast with a clear error
before touching Docker -- `data-caterer/script/seed.sh` checks for it up
front, because without that check the plan still literally says
`connection.type: "csv"`/`options.path`, so Data Caterer writes CSVs into
the ephemeral Postgres container's own throwaway filesystem (never
mounted for that compose service) instead of the database, and `pg_dump`
produces a real-looking but completely empty `<sys>.sql` -- confirmed
directly, exit code 0 either way without the guard.

Adding Postgres support for another system means adding `csv:`/`sql:`
sub-keys to each step's `options:` and templating `connection.type` the
same way -- see `banking.yaml` as the reference -- plus, if needed, a
fixup under `data-caterer/postprocess/sql/<sys>.sql`.

## Adding a system

Drop in a new `data-caterer/plan/<sys>.yaml` and `make seed SYS=<sys>`
works immediately. Its steps' CSV output paths must write under
`/opt/app/data/<sys>/` to match the volume mount in
`docker/docker-compose.seed.yaml`.

See `banking.yaml`'s and `retail.yaml`'s header comments for the plan
format and every real Data Caterer gotcha found building them (weighted
`oneOf` unreliability, `foreignKeys` row-count quirks, deterministic
alternatives to `foreignKeys`, etc.). Verify anything new directly
against the real image (row counts, FK resolution) rather than trusting
Data Caterer's docs -- both existing plans found real discrepancies this
way.

If the plan needs fix-up Data Caterer can't express (banking's
loan-only Guarantor rule, retail's cross-step amount syncing), add an
executable `data-caterer/postprocess/csv/<sys>.sh`; `make seed` runs it
automatically after generation (FORMAT=csv; see the Postgres dump section
for FORMAT=sql's equivalent), passing the output directory as `$1`. A
system with nothing to fix up just doesn't have one.

## As a submodule

```
git submodule add https://github.com/avikbesu/seed-data-gen.git seed-data-gen
```

Pin the checkout path in one Makefile variable rather than hardcoding it
inline -- everything else in the target follows from that:

```makefile
SEED_MODULE := seed-data-gen
FORMAT ?= csv

seed: ## Populate seed data for a system, e.g. `make seed SYS=banking` (or FORMAT=sql, for systems that support it)
	@test -n "$(SYS)" || { echo "usage: make seed SYS=<system> [FORMAT=csv|sql]  (e.g. SYS=banking)" >&2; exit 1; }
	git submodule update --init $(SEED_MODULE)
	@test -f $(SEED_MODULE)/data-caterer/plan/$(SYS).yaml || { echo "seed: no plan for SYS=$(SYS) (expected $(SEED_MODULE)/data-caterer/plan/$(SYS).yaml)" >&2; exit 1; }
	$(MAKE) -C $(SEED_MODULE) seed SYS=$(SYS) FORMAT=$(FORMAT)
	mkdir -p data
	cp -r $(SEED_MODULE)/data/$(SYS) data/$(SYS)
```

Works unmodified for every system this module provides, present or
future -- `FORMAT` just passes through, and `data/$(SYS)/` holds whatever
that run produced (CSVs, or a single `$(SYS).sql` for `FORMAT=sql`).
`$(SEED_MODULE)` must match wherever `git submodule add` actually checked
this out; update it there if the submodule moves. `FORMAT=sql` for a
system that doesn't support it (no `@@CONN_TYPE@@` token in its plan)
fails fast with a clear error, before touching Docker -- see "Postgres
dump" above.

The `cp` step is optional -- skip it and point consumers at
`$(SEED_MODULE)/data/$(SYS)/` directly if you don't need a stable
`data/<sys>` path decoupled from the submodule's own location.

## Layout

- `docker/docker-compose.seed.yaml` -- one-shot service for `FORMAT=csv`,
  parameterized by `SYS`.
- `docker/docker-compose.postgres.yaml` -- ephemeral `postgres` +
  `data-caterer` services for `FORMAT=sql`, torn down every run.
- `data-caterer/script/seed.sh` -- the `make seed` implementation: renders
  the plan and application.conf, then runs the right docker-compose flow.
- `data-caterer/script/hoist.awk` -- resolves each step's
  `options.csv`/`options.sql` to the flat shape Data Caterer expects.
- `data-caterer/application.conf.template` -- Spark runtime defaults
  (HOCON), rendered into `application.conf` (gitignored) each run.
- `data-caterer/application-jdbc.conf.template` -- real Postgres
  connection details, appended only for `FORMAT=sql`.
- `data-caterer/plan/<sys>.yaml` -- one per system: schema, fields, and
  relationships as one `dataSources` entry, rendered into
  `data-caterer/plan/.rendered/<sys>.yaml` (gitignored) before every run.
  `banking.yaml`'s header comment has the full design rationale.
- `data-caterer/postprocess/csv/<sys>.sh` -- optional `FORMAT=csv` fixup.
- `data-caterer/postprocess/sql/<sys>.sql` -- the `FORMAT=sql` equivalent,
  run via `psql` against the live database.
- `data-caterer/README.md` -- detailed notes on the banking dataset shape
  and the Data Caterer 0.19.1 issues worked around in its plan.
