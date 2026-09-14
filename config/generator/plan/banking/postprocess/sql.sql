-- SQL equivalent of this directory's csv.sh awk fixup, run by
-- data-caterer/script/seed/seed.sh against the live database before pg_dump
-- (bug 5 in ../plan.yaml -- `sql` can't see a foreignKeys-populated
-- sibling field). Swap Power of Attorney -> Guarantor wherever the
-- contract's parent account is a Loan.
UPDATE account_contracts ac
SET contract_role = 'Guarantor'
FROM accounts a
WHERE ac.accounts_key = a.id
  AND a.account_type = 'Loan'
  AND ac.contract_role = 'Power of Attorney';
