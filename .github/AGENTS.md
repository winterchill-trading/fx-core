# AGENTS.md (.github/)

`workflows/ci.yml`: infra `ox-setup` with pins `fixed-decimal`, `money`, `ledger`,
`payments-core` (dependency order), then build, test, the quickstart example, and the shared
`obj-magic` workflow. When `dune-project` gains an org dependency, add its pin here in the same
order. Check runs with `gh run list --limit 1` and at most one `gh run watch`.
