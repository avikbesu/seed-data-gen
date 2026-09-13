# seed-data-gen

Generates relationally-intact sample datasets using [Data Caterer
0.19.1](https://data.catering/0.19.1/), a Spark-based data generation
tool. Standalone and dependency-free (just Docker), so it can be dropped
into other repos as a git submodule wherever sample data is useful.

Every foreign-key-shaped value resolves to a real parent row, verified
directly against the real image rather than assumed — see each plan
file's header comment for how and why that matters here.

## Prerequisites

- Docker, with Compose v2 (the `docker compose` subcommand, not the
  standalone `docker-compose` binary).

## Systems

Each dataset is a "system": a plan file under `data-caterer/plan/`, plus
an optional post-processing script.

| System    | Tables | `FORMAT=sql` |
|-----------|--------|--------------|
| `banking` | party, party_address, party_contact, party_profile, accounts, account_contracts, transactions | Yes |
| `retail`  | customer, supplier, product, employee, shift_roster, order, order_item, invoice | No |

## Usage

```
make seed SYS=banking
make seed SYS=retail
```

Output lands in `data/<sys>/` (gitignored): one clean CSV file per table,
header row included, no leftover Spark part-files. Data Caterer's own
log output is quiet by default; for full detail, set `LOG_LEVEL=info` on
the `data-caterer` service in the relevant `docker/docker-compose.*.yaml`
file, or pass `-e LOG_LEVEL=info` if calling `docker compose` directly.

## Postgres dump

```
make seed SYS=banking FORMAT=sql
```

`FORMAT` defaults to `csv`. `FORMAT=sql` starts an ephemeral Postgres
container, generates the same dataset directly into it, applies a SQL
fixup if the system needs one, and runs `pg_dump` into
`data/<sys>/<sys>.sql` — `CREATE DATABASE`/`CREATE TABLE` statements plus
an `INSERT` per row. The container is never reachable outside Docker and
never persists past one run.

Only `banking` supports it today. `FORMAT=sql` on a system that doesn't
(like `retail`) fails immediately with a clear error, before touching
Docker.

To add Postgres support for another system, follow `banking.yaml` as the
reference: one `dataSources` entry serves both formats, selected at
render time by `data-caterer/script/seed.sh`. See that plan's header
comment for the full mechanism and every Data Caterer behavior confirmed
while building it.

## Adding a system

Drop in `data-caterer/plan/<sys>.yaml` and `make seed SYS=<sys>` picks it
up immediately — no other changes needed. Output paths in the plan must
write under `/opt/app/data/<sys>/` to match the volume mount in
`docker/docker-compose.seed.yaml`.

See `banking.yaml`'s and `retail.yaml`'s header comments for the plan
format and every Data Caterer gotcha found building them. Verify anything
new directly against the real image — row counts, FK resolution — rather
than trusting Data Caterer's documentation; see `CONTRIBUTING.md`.

If a plan needs fix-up Data Caterer can't express in-plan, add an
executable `data-caterer/postprocess/csv/<sys>.sh` (and, for `FORMAT=sql`
support, `data-caterer/postprocess/sql/<sys>.sql`). `make seed` runs it
automatically after generation, passing the output directory as `$1`. A
system with nothing to fix up just doesn't have one.

## As a submodule

```
git submodule add https://github.com/avikbesu/seed-data-gen.git seed-data-gen
```

Pin the checkout path in one Makefile variable instead of hardcoding it
inline:

```makefile
SEED_MODULE := seed-data-gen
FORMAT ?= csv

seed: ## Populate seed data for a system, e.g. `make seed SYS=banking` (or FORMAT=sql, for systems that support it)
	@test -n "$(SYS)" || { echo "usage: make seed SYS=<system> [FORMAT=csv|sql]" >&2; exit 1; }
	git submodule update --init $(SEED_MODULE)
	@test -f $(SEED_MODULE)/data-caterer/plan/$(SYS).yaml || { echo "seed: no plan for SYS=$(SYS)" >&2; exit 1; }
	$(MAKE) -C $(SEED_MODULE) seed SYS=$(SYS) FORMAT=$(FORMAT)
	mkdir -p data
	cp -r $(SEED_MODULE)/data/$(SYS) data/$(SYS)
```

This works unmodified for every system the module provides, present or
future; `FORMAT` passes straight through. `$(SEED_MODULE)` must match
wherever `git submodule add` checked it out — update it there if the
submodule moves. The `cp` step is optional: skip it and point consumers
at `$(SEED_MODULE)/data/$(SYS)/` directly if a stable `data/<sys>` path
decoupled from the submodule's location isn't needed.

## Layout

| Path | Purpose |
|------|---------|
| `data-caterer/plan/<sys>.yaml` | Schema, fields, and relationships for one system, as a single `dataSources` entry. Rendered into `data-caterer/plan/.rendered/<sys>.yaml` (gitignored) before every run. |
| `data-caterer/script/seed.sh` | The `make seed` implementation. |
| `data-caterer/script/hoist.awk` | Resolves each step's format-specific `options` down to the shape Data Caterer expects. |
| `data-caterer/application.conf.template` | Spark runtime defaults, rendered into `application.conf` (gitignored) each run. |
| `data-caterer/application-jdbc.conf.template` | Postgres connection details, appended only for `FORMAT=sql`. |
| `data-caterer/postprocess/csv/<sys>.sh` | Optional `FORMAT=csv` fix-up. |
| `data-caterer/postprocess/sql/<sys>.sql` | Optional `FORMAT=sql` fix-up, run via `psql`. |
| `docker/docker-compose.seed.yaml` | One-shot service for `FORMAT=csv`. |
| `docker/docker-compose.postgres.yaml` | Ephemeral Postgres + Data Caterer services for `FORMAT=sql`, torn down every run. |
| `data-caterer/README.md` | Schema notes and every Data Caterer 0.19.1 issue worked around in the `banking` plan. |

## Known limitations

- `retail` has no `FORMAT=sql` support yet.
- There is no fast syntax-check loop for editing a plan — every change
  currently requires a full `make seed` run (Data Caterer's own JVM/Spark
  startup is a ~20s floor). Tracked in
  [#1](https://github.com/avikbesu/seed-data-gen/issues/1).

See `CONTRIBUTING.md` before making changes.
