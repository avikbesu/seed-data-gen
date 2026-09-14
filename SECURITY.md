# Security

This repo generates synthetic sample data via Docker; it has no
production deployment and holds no real user data or credentials. The
fixed Postgres credentials in `config/docker/docker-compose.postgres.yaml`
are intentional dev-only defaults for an ephemeral, non-host-exposed
container torn down at the end of every run -- not a finding.

## Reporting a vulnerability

If you find a security issue (e.g. something that could execute
arbitrary code via a crafted plan file, or a real credential
accidentally committed), please report it privately via
[GitHub's private vulnerability reporting](https://github.com/avikbesu/seed-data-gen/security/advisories/new)
rather than opening a public issue. Expect a response within a few days.
