# Banking sample data generator

Generates a simplified, relationally-intact banking dataset using [Data
Caterer 0.19.1](https://data.catering/0.19.1/). Run via `make seed
SYS=banking` (CSV) or `make seed SYS=banking FORMAT=sql` (Postgres dump)
from the repo root.

## Layout

- `../config/generator/common/application.conf.template` -- Spark runtime
  defaults (HOCON), shared by every system, rendered into
  `.rendered/application.conf` (gitignored) each run with `@@SYS@@`
  substituted. Its `jdbc {}` block (real Postgres connection details) is
  kept only for `FORMAT=sql` and stripped entirely -- not just left
  unused -- for `FORMAT=csv`.
- `../config/generator/plan/banking/plan.yaml` -- the schema (7 tables: `party`, `party_address`,
  `party_contact`, `party_profile`, `accounts`, `account_contracts`,
  `transactions`), fields, and relationships, for both formats. See that
  file's own header comment for the full design rationale, every real
  Data Caterer bug found building it, and how each is worked around.

  `party_address` is a standalone 20,000-row pool (not 1:1 with `party`'s
  500 rows), weighted AU 60% / NZ 30% / {US, UK, NL, IN} 10% split evenly.
  `account_contracts.contract_role` is loan-aware (`Guarantor` only for
  Loan accounts) -- enforced by
  `../config/generator/plan/banking/postprocess/csv.sh` or
  `../config/generator/plan/banking/postprocess/sql.sql` after
  generation, not by the plan itself (bug 5 below).

Output lands in `data/banking/` (gitignored) -- CSVs for `FORMAT=csv`, one
`banking.sql` dump for `FORMAT=sql`.

## Known Data Caterer 0.19.1 issues worked around here

Found by testing directly against the real image, not assumed and not
present in the official docs' own examples:

1. **Multiple `foreignKeys` entries targeting the same step collide** --
   only the first actually populates real parent values; every other
   targeted field falls back to random defaults.
   Worked around: `party` <-> `party_contact` (1:1) uses a matching
   `incremental` sequence instead of `foreignKeys`, so there's no fan-in.

2. **`cardinality` on a `foreignKeys` relationship doesn't expand the
   child's row count** -- despite being documented to, it collapses to
   1:1 with the parent.
   Worked around: `count.perField` on the child step instead (the other
   documented mechanism -- confirmed to actually work, see the
   limitation noted below).

3. **Adding any `foreignKeys` entry targeting a step inflates every
   OTHER foreignKeys-target step's row count** to match its source step
   (giving `party` a real FK to the 20,000-row `party_address` pool
   ballooned `party` itself to 20,000 rows, and unrelated
   `account_contracts`/`transactions` to 60,000 each).
   Worked around: `party.address_id` is a deterministic SQL hash of `seq`
   into `party_address`'s known id format instead.

4. **A weighted `oneOf` (`"value->0.35"`) always returns the LAST
   alternative**, every row -- confirmed via generated-value distribution
   across every weighted field; an unweighted `oneOf` works normally.
   Worked around: a hidden `<field>_bucket` double (`omit: true`) + `sql`
   `CASE` on cumulative thresholds instead.

5. **A field's `sql` can't see another same-step field's real value once
   that field is populated via `foreignKeys`** -- the FK pass overwrites
   it after every `sql` field has already evaluated. Tried making
   `contract_role` loan-aware this way; never fired.
   Can't be fixed in-plan -- `contract_role` is a flat weighted pick,
   fixed up after generation by
   `../config/generator/plan/banking/postprocess/csv.sh` (recovering
   `account_type` from a 2-letter code in `accounts.id`) or
   `../config/generator/plan/banking/postprocess/sql.sql` (a real SQL join).

6. **A string literal in one field's `sql` exactly matching another
   field's name in the same step gets corrupted** -- a `'merchant'` CASE
   branch became the literal text `_temp_merchant` once a field was also
   named `merchant`.
   Worked around: renamed the field to `merchant_name`.

7. **`header: true` at the CSV connection level is silently ignored** for
   a step whose `path` ends in `.csv`. Setting it on the step's own
   `options` block instead works correctly.

## A known limitation of the workaround, not a bug

Every `foreignKeys` + `count.perField` relationship here --
`account_contracts.accounts_key` (`min: 1, max: 3`) and
`transactions.accounts_FK` (`min: 5, max: 50`) -- lands on an
"index-based" assignment that picks one FIXED count per parent (uniform
across every parent in a run, e.g. 150/account and ~140-168/account in
one test run) rather than a true random range, and only spreads across
as many distinct accounts as `total records / that fixed count` covers --
not guaranteed to be all 400. Confirmed identically for `FORMAT=sql`,
not just CSV -- this is Data Caterer's general `count.perField` behavior,
not sink-specific. Every FK value is still guaranteed to reference a real
account (zero orphans, every run). Good enough for sample/demo data, not
worth chasing further -- traces back to the same `cardinality` behavior
as issue 2 above.
