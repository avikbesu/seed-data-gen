#!/usr/bin/env bash
# Generates SYS's sample data in the given FORMAT (csv, default; or sql,
# a Postgres dump) -- see `make seed SYS=<sys> [FORMAT=csv|sql]`.
#
# Renders config/generator/plan/<sys>/plan.yaml into
# data-caterer/.rendered/plan/<sys>.yaml (gitignored): substitutes
# connection.type, then pipes through hoist.awk to flatten each step's
# options.csv/options.sql -- see banking/plan.yaml's header for why.
#
# Usage: data-caterer/script/seed/seed.sh <sys> [format]   (e.g. banking sql)
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
		# token silently "succeeds": Data Caterer writes CSVs into the
		# postgres container's own throwaway filesystem instead of the
		# live database, and pg_dump produces a real-looking but empty
		# <sys>.sql, exit code 0 (confirmed directly).
		if ! grep -q '@@CONN_TYPE@@' "config/generator/plan/$sys/plan.yaml"; then
			echo "seed.sh: SYS=$sys has no FORMAT=sql support (no @@CONN_TYPE@@ token in its plan) -- see README's Postgres dump section" >&2
			exit 1
		fi
		;;
	*)
		echo "seed.sh: unknown FORMAT=$format (expected csv or sql)" >&2
		exit 1
		;;
esac

mkdir -p data-caterer/.rendered/plan

sed "s/@@CONN_TYPE@@/$conn_type/g" "config/generator/plan/$sys/plan.yaml" \
	| awk -v ACTIVE="$format" -f data-caterer/script/seed/hoist.awk \
	> "data-caterer/.rendered/plan/$sys.yaml"

# Regenerated every run, not committed. The jdbc {} block inside the
# template (marked @@JDBC_BLOCK_START@@/@@JDBC_BLOCK_END@@) is
# FORMAT=sql-only: for csv the whole marked range is deleted (must be
# textually absent, not just unused -- see the template's header); for
# sql only the two marker lines go, keeping the block.
if [ "$format" = "sql" ]; then
	jdbc_filter='/@@JDBC_BLOCK_START@@/d; /@@JDBC_BLOCK_END@@/d'
else
	jdbc_filter='/@@JDBC_BLOCK_START@@/,/@@JDBC_BLOCK_END@@/d'
fi
sed -e "$jdbc_filter" -e "s/@@SYS@@/$sys/g" \
	config/generator/common/application.conf.template \
	> data-caterer/.rendered/application.conf

if [ "$format" = "csv" ]; then
	rm -rf "data/$sys"
	mkdir -p "data/$sys"
	# The data-caterer image writes as uid 1001, not the host user -- see
	# config/docker/docker-compose.seed.yaml.
	chmod 777 "data/$sys"
	SYS="$sys" docker compose -f config/docker/docker-compose.seed.yaml run --rm data-caterer
	# Optional per-system fix-up for what Data Caterer can't express
	# in-plan (see postprocess/csv.sh's own comment) -- run if present.
	if [ -x "config/generator/plan/$sys/postprocess/csv.sh" ]; then
		echo "Running config/generator/plan/$sys/postprocess/csv.sh..."
		"config/generator/plan/$sys/postprocess/csv.sh" "data/$sys"
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

	# Same convention, but as a SQL run against the live database (see
	# postprocess/sql.sql's own comment) -- run if present.
	if [ -f "config/generator/plan/$sys/postprocess/sql.sql" ]; then
		echo "Running config/generator/plan/$sys/postprocess/sql.sql..."
		SYS="$sys" "${compose[@]}" exec -T postgres psql -U postgres -d "$sys" < "config/generator/plan/$sys/postprocess/sql.sql"
	fi

	SYS="$sys" "${compose[@]}" exec -T postgres pg_dump -U postgres --create --inserts --column-inserts "$sys" > "data/$sys/$sys.sql"
fi
