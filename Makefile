.PHONY: seed validate-plan install-hooks

FORMAT ?= csv

seed: ## Generate SYS's sample data, e.g. `make seed SYS=banking` (FORMAT=csv, default, into data/$(SYS)/) or `make seed SYS=banking FORMAT=sql` (Postgres dump into data/$(SYS)/$(SYS).sql -- see config/generator/plan/$(SYS)/plan.yaml)
	@test -n "$(SYS)" || { echo "usage: make seed SYS=<system> [FORMAT=csv|sql]  (e.g. SYS=banking -- one per config/generator/plan/*/plan.yaml)" >&2; exit 1; }
	@test -f config/generator/plan/$(SYS)/plan.yaml || { echo "seed: no plan for SYS=$(SYS) (expected config/generator/plan/$(SYS)/plan.yaml)" >&2; exit 1; }
	data-caterer/script/seed/seed.sh $(SYS) $(FORMAT)

validate-plan: ## Validate plan file(s) against repo rules, e.g. `make validate-plan` (all) or `make validate-plan SYS=banking`
	@if [ -n "$(SYS)" ]; then \
		data-caterer/script/validate/validate-plan.sh config/generator/plan/$(SYS)/plan.yaml; \
	else \
		data-caterer/script/validate/validate-plan.sh; \
	fi

install-hooks: ## Wire up this repo's git hooks (pre-commit plan validation)
	git config core.hooksPath .githooks
	@echo "hooks installed (core.hooksPath=.githooks)"
