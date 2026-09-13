.PHONY: seed

seed: ## Generate a fresh, relationally-intact sample banking dataset as CSVs into data/banking/ (see data-caterer/plan/banking.yaml)
	rm -rf data/banking
	mkdir -p data/banking
	# The data-caterer image writes as uid 1001, not the host user -- see
	# docker/docker-compose.seed.yaml.
	chmod 777 data/banking
	docker compose -f docker/docker-compose.seed.yaml run --rm data-caterer
	# Data Caterer can't make account_contracts.contract_role loan-aware
	# itself (a field's `sql` can't see another field's real foreignKeys
	# value -- see bug 5 in banking.yaml's file-level comment), so fix up
	# here: Power of Attorney -> Guarantor wherever the contract's parent
	# account is a Loan.
	awk -F, ' \
		NR==FNR { \
			if (FNR==1) { for (i=1;i<=NF;i++) h[$$i]=i; next } \
			type[$$(h["id"])] = $$(h["account_type"]); next \
		} \
		FNR==1 { for (i=1;i<=NF;i++) ch[$$i]=i; print; next } \
		{ \
			if (type[$$(ch["accounts_key"])] == "Loan" && $$(ch["contract_role"]) == "Power of Attorney") { \
				$$(ch["contract_role"]) = "Guarantor" \
			} \
			print \
		} \
	' OFS=, data/banking/accounts.csv data/banking/account_contracts.csv > data/banking/account_contracts.csv.tmp
	mv data/banking/account_contracts.csv.tmp data/banking/account_contracts.csv
