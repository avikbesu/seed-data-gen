.PHONY: seed

seed: ## Generate a fresh sample dataset as CSVs into data/$(SYS)/ for the given system, e.g. `make seed SYS=banking` (see data-caterer/plan/$(SYS).yaml)
	@test -n "$(SYS)" || { echo "usage: make seed SYS=<system>  (e.g. SYS=banking -- one per data-caterer/plan/*.yaml)" >&2; exit 1; }
	@test -f data-caterer/plan/$(SYS).yaml || { echo "seed: no plan for SYS=$(SYS) (expected data-caterer/plan/$(SYS).yaml)" >&2; exit 1; }
	rm -rf data/$(SYS)
	mkdir -p data/$(SYS)
	# The data-caterer image writes as uid 1001, not the host user -- see
	# docker/docker-compose.seed.yaml.
	chmod 777 data/$(SYS)
	# Regenerated every run, not committed -- see application.conf.template
	# for why this can't just be a static file.
	sed 's/@@SYS@@/$(SYS)/g' data-caterer/application.conf.template > data-caterer/application.conf
	SYS=$(SYS) docker compose -f docker/docker-compose.seed.yaml run --rm data-caterer
	# A system can optionally fix up what Data Caterer can't express in
	# the plan itself (see data-caterer/postprocess/banking.sh for why
	# banking needs this) -- run it if present, skip it otherwise.
	@if [ -x data-caterer/postprocess/$(SYS).sh ]; then \
		echo "Running data-caterer/postprocess/$(SYS).sh..."; \
		data-caterer/postprocess/$(SYS).sh data/$(SYS); \
	fi
