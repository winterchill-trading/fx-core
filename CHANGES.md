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
- `Bundled`: an optional fourth CSV column, `fetched_at` (ISO 8601 with an offset), keeps
  a snapshot's real fetch time; rows without it still get midnight UTC of their rate date.
  `Bundled.to_csv ~fetched_at:true` writes the column.
- Display inverse digits: `Pricing.inverse_customer_rate ?digits` (default 10),
  `Pricing.price ?inverse_digits`, `Rate_table.Mid.inverse_rate ?digits` (default 20),
  `Quote.create ?inverse_digits` (both inverses) and `Card_fx.authorise ?inverse_digits`.
  Amounts and customer rates never depend on it.
