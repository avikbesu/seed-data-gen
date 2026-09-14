#!/usr/bin/env bash
# Generates SYS's sample data in the given FORMAT (csv, default; or sql,
# a Postgres dump) -- see `make seed SYS=<sys> [FORMAT=csv|sql]`.
#
# Renders config/generator/plan/<sys>.yaml (the source of truth) into this
# directory's plan/.rendered/<sys>.yaml (gitignored, what
# application.conf.template's planFilePath points at): substitutes
# connection.type, then pipes through hoist.awk to resolve each step's
# options.csv/options.sql down to the flat shape Data Caterer expects --
# see config/generator/plan/banking.yaml's own header comment for the full
# rationale. A plan with none of those tokens (not every system needs a
# Postgres target) renders unchanged.
#
# Usage: data-caterer/script/seed.sh <sys> [format]   (e.g. banking sql)
set -euo pipefail

sys="$1"
format="${2:-csv}"

case "$format" in
	csv)
		conn_type=csv
		;;
	sql)
		conn_type=jdbc
		# Without this guard, FORMAT=sql on a plan with no @@CONN_TYPE@@
		# token silently "succeeds": the plan still literally says
		# connection.type: "csv"/options.path, so Data Caterer writes
		# CSVs into the ephemeral postgres container's own throwaway
		# filesystem (never mounted for this compose service) instead
		# of the live database -- pg_dump then produces a real-looking
		# but completely empty <sys>.sql (CREATE DATABASE, no tables, no
		# data), exit code 0. Confirmed directly.
		if ! grep -q '@@CONN_TYPE@@' "config/generator/plan/$sys.yaml"; then
			echo "seed.sh: SYS=$sys has no FORMAT=sql support (no @@CONN_TYPE@@ token in its plan) -- see README's Postgres dump section" >&2
			exit 1
		fi
		;;
	*)
		echo "seed.sh: unknown FORMAT=$format (expected csv or sql)" >&2
		exit 1
		;;
esac

mkdir -p data-caterer/plan/.rendered

sed "s/@@CONN_TYPE@@/$conn_type/g" "config/generator/plan/$sys.yaml" \
	| awk -v ACTIVE="$format" -f data-caterer/script/hoist.awk \
	> "data-caterer/plan/.rendered/$sys.yaml"

# Regenerated every run, not committed -- see application.conf.template
# for why this can't just be a static file.
sed "s/@@SYS@@/$sys/g" data-caterer/application.conf.template > data-caterer/application.conf
if [ "$format" = "sql" ]; then
	# See application-jdbc.conf.template for why this must be appended
	# only for FORMAT=sql, never left in application.conf.template itself.
	sed "s/@@SYS@@/$sys/g" data-caterer/application-jdbc.conf.template >> data-caterer/application.conf
fi

if [ "$format" = "csv" ]; then
	rm -rf "data/$sys"
	mkdir -p "data/$sys"
	# The data-caterer image writes as uid 1001, not the host user -- see
	# config/docker/docker-compose.seed.yaml.
	chmod 777 "data/$sys"
	SYS="$sys" docker compose -f config/docker/docker-compose.seed.yaml run --rm data-caterer
	# A system can optionally fix up what Data Caterer can't express in
	# the plan itself (see data-caterer/postprocess/csv/banking.sh for why
	# banking needs this) -- run it if present, skip it otherwise.
	if [ -x "data-caterer/postprocess/csv/$sys.sh" ]; then
		echo "Running data-caterer/postprocess/csv/$sys.sh..."
		"data-caterer/postprocess/csv/$sys.sh" "data/$sys"
	fi
else
	compose=(docker compose -f config/docker/docker-compose.postgres.yaml)
	cleanup() {
		SYS="$sys" "${compose[@]}" down -v
	}
	trap cleanup EXIT

	mkdir -p "data/$sys"
	SYS="$sys" "${compose[@]}" up -d --wait postgres
	SYS="$sys" "${compose[@]}" run --rm data-caterer

	# Same optional-fixup convention as the CSV path above, but as SQL run
	# against the live database instead of awk over CSVs -- see
	# data-caterer/postprocess/sql/banking.sql for why banking needs this.
	if [ -f "data-caterer/postprocess/sql/$sys.sql" ]; then
		echo "Running data-caterer/postprocess/sql/$sys.sql..."
		SYS="$sys" "${compose[@]}" exec -T postgres psql -U postgres -d "$sys" < "data-caterer/postprocess/sql/$sys.sql"
	fi

	SYS="$sys" "${compose[@]}" exec -T postgres pg_dump -U postgres --create --inserts --column-inserts "$sys" > "data/$sys/$sys.sql"
fi
