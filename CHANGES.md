# Changes

All notable changes to this library. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow semantic
versioning once released.

## Unreleased

### Added

- `Ratio`: exact rationals with rounding to significant digits and a stable text form.
- `Origin`, `Observation`, `Basis`: reference rates per pivot unit, date and origin,
  and the basis a price shows.
- `Rate_table`: as-of lookup (live before bundled), history, cross rates through the
  pivot at 20 significant digits, cross history.
- `Freshness`: stale and maximum-age rules, with an offline policy.
- `Spread` with caps and a per-tier `Schedule`; `Pricing` with the customer rate rounded
  down to 10 significant digits, sell-fixed floor, buy-fixed ceil and an included fee.
- `Quote`, `Quote_book` (open, executed, expired; idempotent claims per execution key)
  and `Exchange`, which books executions through `payments-core`'s `Swap`.
- `Card_fx` (authorisation, re-pricing at the authorisation rate, refund shares) and
  `Valuation` (estimates at mid, thresholds).
- `Rate_source.S`, `Simulated_source`, `Bundled` CSV tables and `Refresh`.
- `fx-core` command (`rates`, `quote`, `bundle`) and a quickstart example run in CI.
