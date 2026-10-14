# AGENTS.md (test/)

Tests for `fx_core`, one file per area (`test_ratio`, `test_rate_table`, `test_freshness`,
`test_pricing`, `test_exchange`, `test_card_fx`, `test_valuation`, `test_sources`, `test_stable`).

- `helpers.ml` builds a fixed table (EUR 0.92, GBP 0.79, JPY 150, CHF 0.88, KWD 0.307 per USD on
  Friday 2026-10-09) and the clock; reuse it so numbers stay comparable across files.
- Quickcheck properties check the rounding bounds, spread monotonicity, balanced bookings and
  refund shares; keep them when changing pricing.
- `test_stable.ml` pins digests: a change means a new `Stable.V2`.
- `cli.t/run.t` is the cram test of the binary.
- Run: `DUNE_BUILD_DIR=_build-fx-core opam exec --switch 5.2.0+ox -- dune build --root .. @fx-core/runtest`;
  promote with `dune promote` from `..` only after reading the diff.
