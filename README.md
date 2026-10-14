# fx-core

Foreign exchange the way a retail or business bank prices it: a table of reference
rates per currency, date and origin; cross rates through a pivot currency; staleness and
maximum-age rules; a spread in basis points with per-tier caps; customer rates and
amounts rounded so that rounding never favours the customer; single-use quotes with a
short time to live; card conversion re-pricing; estimates in a base currency; and the
booking of an executed exchange as balanced [`ledger`](https://github.com/winterchill-trading/ledger)
entries through [`payments-core`](https://github.com/winterchill-trading/payments-core)'s
`Swap`.

Everything is exact: rates are rationals (Zarith `Q`), amounts are integer minor units
from [`money`](https://github.com/winterchill-trading/money), and each rule rounds once,
in a stated direction. The library is pure and never persists anything: tables, quote
books and statuses are values that a service stores however it likes.

## Why separate

Every product that holds more than one currency needs the same handful of rules, and
gets them subtly wrong in different places: which rate applies on a Sunday, how old a
rate may be before the bank stops quoting, whether the bought amount rounds up or down,
whether the fee is inside the sold amount or on top, what happens when a quote is
executed twice. `money` knows single rates and amounts; `payments-core` knows how to
book a swap. This library sits between them and owns the pricing policy, so a payment
flow, a card processor, a brokerage that settles in another currency and a portfolio
page all price the same way, from the same table, and refuse for the same reasons.

## Quick start

```sh
dune build
dune exec fx-core -- rates -now 2026-10-09T12:00:00Z
dune exec fx-core -- quote EUR GBP -sell 100.00 -cap 35 -now 2026-10-09T12:00:00Z
dune exec fx-core -- bundle -from 2026-10-01 -to 2026-10-09 > rates.csv
dune exec fx-core -- quote GBP CHF -sell 50.00 -bundled rates.csv
dune exec ./examples/quickstart.exe
```

```
sell 100.00 EUR, buy 85.56 GBP, fee 0.35 EUR, customer rate 0.8556902173
entries 3; EUR 150.00 EUR, GBP 85.56 GBP
```

## Usage

```ocaml
open Fx_core

(* Rates per USD; the pivot is the table's, any currency works. *)
let table =
  Rate_table.add_all (Rate_table.create ~pivot:Money.Currency.usd) observations
  |> Or_error.ok_exn

(* The spread for this customer's tier, then a quote valid for 30 seconds. *)
let spread = Spread.Schedule.spread schedule ~tier:"plus" () |> Or_error.ok_exn

let quote =
  Quote.create table ~id ~sell:eur ~buy:gbp ~spread
    (Sell (Money.Amount.of_string "100.00 EUR")) ~now

(* Execute once: claim the quote in the book and get the entries to append. *)
let result =
  Exchange.execute book Payments_core.Booking.Chart.default balances
    ~quote_id ~from_:customer_eur ~to_:customer_gbp ~execution_key ~now
```

Every pricing function returns `(_, Refusal.t) Result.t`; `Refusal.code` gives a
stable snake_case name (`no_rate`, `rate_too_old`, `amount_too_small`,
`quote_expired`, `quote_already_used`, `insufficient_funds`, ...) for an API to map to
its own errors.

## Rules

| Rule | Value |
|---|---|
| Rate storage | units of each currency per one pivot unit, per (currency, date, origin) |
| Lookup | newest date on or before the request day; live preferred over bundled on the same date |
| Cross mid A -> B | `per_pivot(B) / per_pivot(A)`, exact, published to 20 significant digits half-even |
| Customer rate | `mid x (1 - spread)`, rounded **down** to 10 significant digits |
| Inverse rates | `1 / rate`, half-even, same digits (display only) |
| Sell fixed | bought = floor(sold x customer rate) in the bought minor unit |
| Buy fixed | sold = ceil(bought / customer rate) in the sold minor unit |
| Fee | sold x spread, half-up in the sold minor unit, included in the sold amount |
| Spread | standard bps (0 to 1000), lowered by the smallest applicable cap (tier, contract) |
| Refusals | same currency, no rate, rate too old, non-positive, converts to zero, above 2^53 - 1 minor units |
| Freshness | stale after 3 h (shown, still usable); refused when the rate date or the fetch is more than 7 days old |
| Quotes | 30 s time to live; open -> executed (once per execution key) or expired |
| Booking | sell leg `sold - fee` to the FX position, fee to fee income, buy leg from the FX position (three balanced entries via `Payments_core.Swap`) |
| Card FX | merchant amount fixed at authorisation; final amounts re-priced at the authorisation's customer rate; refunds return `floor(paid x refunded / settled)` |
| Estimates | exact mid, summed exactly, rounded once half-even; a currency without a rate is named, and no total is given |

Rounding therefore never favours the customer and never costs them more than one minor
unit beyond the published rate; the Quickcheck properties below check both bounds.

## Offline mode

A deployment without network access (a demo, a test environment, an air-gapped
replica) prices from **bundled** tables: CSV text shipped with the application.

```
date,currency,rate
2026-10-09,EUR,0.92
2026-10-09,JPY,149.82
```

`Bundled.parse` marks every row `Bundled` with a fetch time of midnight UTC at the
start of its rate date, so a bundled rate is never presented as younger than its
publication. Use `Freshness.Policy.offline` (or `Quote.Config.offline`): it drops the
maximum age, so quoting keeps working from the newest bundled date however old it is,
and every basis is reported **stale**. With the default policy the same table would be
refused after seven days, which is the right behaviour for a live service whose feed has
silently stopped.

Bundled and live rates can share one table: on a given date a live rate wins. To price
a past day deterministically (replays, seeded demo history) pass
`~selection:Bundled_only`, which ignores whatever was fetched since.

## Rate sources

`Rate_source.S` is the interface for anything that supplies reference rates (`latest`
and `history`, against one pivot, no credentials). HTTP fetchers belong in services;
this library ships:

- `Simulated_source`: deterministic rates from seed values, moved within a volatility
  band by an MD5 of currency and date, published Monday to Friday; driven by an
  `Async_kernel.Time_source` and switchable to unreachable for failure tests;
- `Refresh`: the pure schedule (every hour, five minutes after a failure), the status a
  service reports (reachable, last success, last attempt, newest rate date, stale) and
  `fetch`, which merges a source's latest rates into a table and never empties it on
  failure.

## Tests

`dune test` runs expect tests for every module, a cram test of the CLI (including
offline mode) and Quickcheck properties:

- significant-digit rounding: `Down` never rounds up, `Up` never down, both within one
  unit of the last kept digit; text forms round-trip;
- a cross rate times the reverse cross is exactly one;
- pricing over every pair, amounts up to 10^12 minor units and spreads up to 1000 bps:
  the customer rate never exceeds mid, the bought amount never exceeds what the sold
  amount is worth at the customer rate, and misses it by less than one minor unit; the
  fee never exceeds the sold amount; a lower spread never gives the customer less;
- every executed quote books entries that keep the ledger balanced and move exactly the
  quoted sold, bought and fee amounts;
- partial card refunds never add up to more than was paid;
- simulated rates stay within their volatility band.

Stable types (`Ratio`, `Origin`, `Observation`, `Basis`, `Spread`,
`Pricing.Fixed_side`, `Quote`) have pinned `bin_digest`s; a change needs a new
`Stable.V2`.

## Portability

The library uses no OxCaml-only language feature, so its own code builds with OCaml
5.2 or later. It depends on Jane Street's `v0.18~preview` packages, published today
only in the OxCaml opam repository, and on `money`, whose `fixed-decimal` dependency
needs the OxCaml compiler.

## Releasing

The version lives only in git tags, written into `fx-core.opam` by `dune subst`;
`CHANGES.md` collects notes under `## Unreleased`. `money`, `ledger` and
`payments-core` must be released first. Nothing has been released yet. API docs:
`dune build @doc`.

## Known gaps

- No HTTP rate fetcher: services implement `Rate_source.S` over their own client.
- Rates are per business day; intraday or streaming rates (a dealing desk) would need a
  timestamp rather than a date in `Observation`.
- `Quote_book` is a value; a service with several replicas needs its own store with an
  atomic claim per quote, using the same rules.
- The pivot is fixed per table; currencies quoted only against another base need
  converting before they are added.
- Tokens without a reference rate (stablecoins priced from a market) are not modelled
  apart: add their observations from a market feed like any other source.

## Used by

No other repository in the organization depends on it yet.
