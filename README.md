# seed-data-gen

Generates sample datasets as CSV files using [Data Caterer
0.19.1](https://data.catering/0.19.1/), a Spark-based data generation
tool. Each dataset is a "system": a plan file under `data-caterer/plan/`
plus an optional post-processing script. Ships two systems so far:

- `banking` -- a simplified banking dataset (party, party_address,
  party_contact, party_profile, accounts, account_contracts,
  transactions).
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
table, with a header row and no leftover Spark part-files.

## Adding a system

Drop in a new `data-caterer/plan/<sys>.yaml` and `make seed SYS=<sys>`
works immediately -- nothing else needs editing. Its steps' output
`path`s must write under `/opt/app/data/<sys>/` to match the volume
mount in `docker/docker-compose.seed.yaml`.

For the plan format and Data Caterer gotchas, see `banking.yaml`'s
header comment (the full list of real bugs found, e.g. why a weighted
`oneOf` can't be trusted) and `retail.yaml`'s header comment (why it
uses NO real `foreignKeys` block at all despite having several
many-to-one relationships -- including a genuine one-to-many that
started out using `foreignKeys` + `count.perField` and was rebuilt
deterministic after that only covered ~25% of parent rows in testing --
and the deterministic-reference techniques, including a closed-form
cumulative-sum encoding for the one-to-many case, it uses instead).
Whatever you add, verify it directly against the real image (`make seed
SYS=<sys>`, then check row counts and that every FK-shaped value
resolves to a real parent row) rather than assuming Data Caterer's
documented behavior holds -- both existing plans found real
discrepancies this way.

If the plan needs fix-up that Data Caterer can't express (like
banking's loan-only Guarantor rule, or retail's cross-step amount
syncing -- see `data-caterer/README.md` and `postprocess/retail.sh`
respectively), add an executable `data-caterer/postprocess/<sys>.sh`;
the `seed` target runs it automatically after generation, passing the
output directory as `$1`. A system with nothing to fix up just doesn't
have one.

## As a submodule

```
git submodule add https://github.com/avikbesu/seed-data-gen.git seed-data-gen
```

Pin the checkout path in one Makefile variable rather than hardcoding it
inline -- everything else in the target follows from that:

```makefile
SEED_MODULE := seed-data-gen

seed: ## Populate seed data for a system, e.g. `make seed SYS=banking`
	@test -n "$(SYS)" || { echo "usage: make seed SYS=<system>  (e.g. SYS=banking)" >&2; exit 1; }
	git submodule update --init $(SEED_MODULE)
	@test -f $(SEED_MODULE)/data-caterer/plan/$(SYS).yaml || { echo "seed: no plan for SYS=$(SYS) (expected $(SEED_MODULE)/data-caterer/plan/$(SYS).yaml)" >&2; exit 1; }
	$(MAKE) -C $(SEED_MODULE) seed SYS=$(SYS)
	mkdir -p data
	cp -r $(SEED_MODULE)/data/$(SYS) data/$(SYS)
```

This one target works unmodified for every system this module provides,
present or future -- no per-system Makefile logic needed. `$(SEED_MODULE)`
must match wherever `git submodule add` actually checked this out; update
it there if the submodule is ever moved or renamed.

The `cp` step is optional -- skip `mkdir -p data` / `cp -r ...` and point
consumers at `$(SEED_MODULE)/data/$(SYS)/` directly if you don't need a
stable `data/<sys>` path decoupled from the submodule's own location.

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
