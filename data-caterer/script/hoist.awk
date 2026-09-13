# Resolves a plan's per-format options: {csv: {...}, sql: {...}} down to
# the flat options: Data Caterer expects for the active format -- see
# data-caterer/script/seed.sh and plan/banking.yaml's header comment.
#
# For each direct child of an `options:` block named exactly `csv:` or
# `sql:`: drops the whole block (key line + every deeper-indented child)
# if it's not ACTIVE, or drops just the key line and de-indents its
# children by 2 spaces if it IS active -- hoisting them to be direct
# children of `options:`. Driven by indentation and key text alone, so it
# applies uniformly to every step with no per-step setup.
#
# Usage: awk -v ACTIVE=csv -f hoist.awk <rendered-plan.yaml
# ACTIVE must be "csv" or "sql".
BEGIN {
	skip_depth = -1
	hoist_depth = -1
}
{
	line = $0
	match(line, /^[ ]*/)
	ind = RLENGTH
	key = line
	sub(/^[ ]*/, "", key)

	# currently inside a dropped (inactive-format) block?
	if (skip_depth >= 0) {
		if (ind > skip_depth) next
		skip_depth = -1
	}

	# currently inside a hoisted (active-format) block?
	if (hoist_depth >= 0) {
		if (ind > hoist_depth) {
			print substr(line, 3)
			next
		}
		hoist_depth = -1
	}

	if (key == "csv:" || key == "sql:") {
		tag = key
		sub(/:$/, "", tag)
		if (tag == ACTIVE) {
			hoist_depth = ind
		} else {
			skip_depth = ind
		}
		next
	}

	print line
}
