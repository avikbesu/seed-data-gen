# Repo conventions

- Do not add any Claude/Anthropic attribution to git commit messages or pull
  request descriptions (no `Co-Authored-By: Claude ...` trailer, no
  `Claude-Session` link, no "Generated with Claude Code" footer). Commits and
  PRs in this repo should read as authored solely by the human contributor.

## Repo highlights

For full agent-facing guidance (build/run/verify, layout, gotchas), see
`AGENTS.md` — it covers the same ground in more detail. The essentials:

- This generates relationally-intact sample datasets via
  [Data Caterer 0.19.1](https://data.catering/0.19.1/) (Spark-based), driven
  entirely by Docker — no other dependency. Meant to be dropped into other
  repos as a git submodule (see README.md's "As a submodule" section and
  `setup.sh`).
- Each dataset is a "system": `data-caterer/plan/<sys>.yaml` plus an optional
  `data-caterer/postprocess/<sys>.sh`. Two exist today: `banking` (party,
  accounts, transactions) and `retail` (customer, supplier, product, order,
  invoice). Adding a new system is just dropping in a new plan file —
  `make seed SYS=<sys>` picks it up with no other changes.
- Run/verify with `make seed SYS=banking` or `make seed SYS=retail`. There is
  no test suite; verification means generating against the real image and
  checking the output CSVs in `data/<sys>/` (gitignored) for correct row
  counts and zero orphan foreign keys.
- The plans and postprocess scripts document seven real Data Caterer 0.19.1
  bugs/limitations found by direct testing (not from the docs) — e.g.
  weighted `oneOf` always returning the last alternative, `foreignKeys` row
  inflation bleeding across unrelated steps, and `sql` fields unable to see
  another same-step field's `foreignKeys`-populated value. See
  `data-caterer/README.md` and each plan file's header comment before adding
  or changing a relationship — assume nothing about documented behavior
  without checking the real image.
- `retail.yaml`'s `order`/`order_item` relationship is the one genuine
  one-to-many case; it deliberately avoids a real `foreignKeys` block in
  favor of a deterministic closed-form cumulative-sum encoding, after
  `foreignKeys` + `count.perField` was tested and found to only cover
  ~25-27% of parent rows.
- `data/`, `.seed-modules/`, and `data-caterer/application.conf` are
  gitignored/regenerated on every run — never commit them.
