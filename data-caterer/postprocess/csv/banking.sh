#!/usr/bin/env bash
# Post-processing for SYS=banking, run automatically by
# data-caterer/script/seed.sh after Data Caterer finishes (FORMAT=csv;
# a system with nothing to fix up just doesn't have one here).
#
# Data Caterer can't make account_contracts.contract_role loan-aware
# itself (a field's `sql` can't see another field's real foreignKeys
# value -- see bug 5 in plan/banking.yaml's file-level comment), so fix
# up here: Power of Attorney -> Guarantor wherever the contract's parent
# account is a Loan.
#
# Usage: banking.sh <output-dir>   (e.g. data/banking, containing that
# run's accounts.csv and account_contracts.csv)
set -euo pipefail

dir="$1"
awk -F, '
	NR==FNR {
		if (FNR==1) { for (i=1;i<=NF;i++) h[$i]=i; next }
		type[$(h["id"])] = $(h["account_type"]); next
	}
	FNR==1 { for (i=1;i<=NF;i++) ch[$i]=i; print; next }
	{
		if (type[$(ch["accounts_key"])] == "Loan" && $(ch["contract_role"]) == "Power of Attorney") {
			$(ch["contract_role"]) = "Guarantor"
		}
		print
	}
' OFS=, "$dir/accounts.csv" "$dir/account_contracts.csv" > "$dir/account_contracts.csv.tmp"
mv -f "$dir/account_contracts.csv.tmp" "$dir/account_contracts.csv"
