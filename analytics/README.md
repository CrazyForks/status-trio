# analytics

Machine-generated snapshots of the GitHub-side numbers. Do not hand-edit:
`scripts/snapshot-analytics.py` rewrites `daily/<YYYY-MM-DD>.json` and
`series.csv` on every run, and the daily
[Analytics snapshot workflow](../.github/workflows/analytics-snapshot.yml)
commits the result.

See [docs/analytics-snapshot.md](../docs/analytics-snapshot.md) for the schema,
the semantics of `count` versus `uniques`, and how to enable traffic archiving
in CI.
