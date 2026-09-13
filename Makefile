.PHONY: seed

FORMAT ?= csv

seed: ## Generate SYS's sample data, e.g. `make seed SYS=banking` (FORMAT=csv, default, into data/$(SYS)/) or `make seed SYS=banking FORMAT=sql` (Postgres dump into data/$(SYS)/$(SYS).sql -- see data-caterer/plan/$(SYS).yaml)
	@test -n "$(SYS)" || { echo "usage: make seed SYS=<system> [FORMAT=csv|sql]  (e.g. SYS=banking -- one per data-caterer/plan/*.yaml)" >&2; exit 1; }
	@test -f data-caterer/plan/$(SYS).yaml || { echo "seed: no plan for SYS=$(SYS) (expected data-caterer/plan/$(SYS).yaml)" >&2; exit 1; }
	data-caterer/script/seed.sh $(SYS) $(FORMAT)
