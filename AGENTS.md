# AGENTS.md

Guide for AI coding agents working in this repository. Read this first; the subdirectory
`AGENTS.md` files add detail for `lib/`, `bin/`, `test/`, `examples/` and `.github/`. The
workspace-wide guide is `../oxcaml-claude-skills/AGENTS.md`.

## Purpose

`fx-core` prices currency conversions the way a bank does: reference rate tables per currency,
date and origin, cross rates through a pivot, staleness rules, spreads with per-tier caps,
directional rounding, single-use quotes, card FX re-pricing and estimates at mid. An executed
quote becomes balanced `ledger` entries through `payments-core`'s `Swap`; nothing is persisted.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The `fx-core` library (`Fx_core`): `Ratio`, `Observation`, `Rate_table`, `Freshness`, `Spread`, `Pricing`, `Quote`, `Quote_book`, `Exchange`, `Card_fx`, `Valuation`, `Rate_source`, `Simulated_source`, `Bundled`, `Refresh` |
| `bin/` | The `fx-core` command: `rates`, `quote`, `bundle` |
| `test/` | Expect tests, Quickcheck properties, pinned digests, the `cli.t` cram test |
| `examples/` | `quickstart.ml`, the README walk-through, run in CI |
| `.github/` | CI workflow |
| `dune-project` | Package metadata; `dune build` regenerates `fx-core.opam` |

## Build, test, docs

Inside the workspace (sibling checkouts and the shared `5.2.0+ox` switch are required), from this
directory:

```sh
DUNE_BUILD_DIR=_build-fx-core opam exec --switch 5.2.0+ox -- dune build --root .. @fx-core/all
DUNE_BUILD_DIR=_build-fx-core opam exec --switch 5.2.0+ox -- dune build --root .. @fx-core/runtest
DUNE_BUILD_DIR=_build-fx-core opam exec --switch 5.2.0+ox -- dune build --root .. @fx-core/doc
```

`DUNE_BUILD_DIR` resolves from the workspace root because of `--root ..`. Promote expect output
with `dune promote` (same prefix, run from `..`) after reading the diff.

Standalone: `opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`,
then `opam install --deps-only --with-test .` and `dune build && dune test`.

## Conventions

- Every module has an `.mli` with odoc on each public value. `open! Core`, labelled arguments.
- Exact arithmetic only: rates are `Q.t` (`Ratio`), amounts are `money` minor units. Each rule
  rounds once in a stated direction; never introduce floats.
- Pricing functions return `(_, Refusal.t) Result.t`; add a `Refusal` case (and its `code`) rather
  than an ad-hoc error.
- The library is pure: state (tables, quote books, refresh status) is a value; no store, no I/O
  beyond `Rate_source` implementations.
- `Stable` types have pinned digests in `test/test_stable.ml`; add a `V2`, never edit `V1`.
- Expect tests plus Quickcheck for invariants; comments for humans at non-obvious choices.
- Formatting: `DUNE_BUILD_DIR=_build-fx-core opam exec --switch 5.2.0+ox -- dune build --root .. @fx-core/fmt --auto-promote`.
  Never run `dune fmt` at the workspace root.
- User-visible changes get a line under "Unreleased" in `CHANGES.md`.
- Display-only knobs (such as `?inverse_digits`) must never reach amounts or customer rates;
  `test/test_pricing.ml` has a Quickcheck property for it.
- `Bundled` CSV: three columns, or four with `fetched_at`; keep both readable, and keep
  `to_csv` without the column by default so existing files stay byte-identical.
- `examples/bundled-rates.csv` documents the CSV shape and is read by
  `test/test_bundled_example.ml` (a `deps` entry in `test/dune`); change the format and
  the example together. The lenient parse skips only unknown currency codes, never other
  errors, and still validates the skipped row's date and rate.

## Dependencies and dependents

- Depends on `money`, `ledger` and `payments-core` (plus `fixed-decimal` transitively).
- CI pin order: `fixed-decimal`, `money`, `ledger`, `payments-core`.
- No org repository depends on it yet.

## CI

`ci.yml` runs the infra `ox-setup` action with the pins above, then `dune build`, `dune test`,
the quickstart example, and the shared `obj-magic` workflow. Check a run with
`gh run list --limit 1`, then at most one `gh run watch <id> --exit-status`. A cold cache takes
over half an hour; pushing again cancels it before the cache is saved.

## Pitfalls

- `let compare = Q.compare` against a derived `compare` in the `.mli` fails on modes; eta-expand.
- `[@sexp.opaque]` works only inside parentheses with the type: `(Z.t[@sexp.opaque])`.
- Inline tests that need Async: use `Async.Thread_safe.block_on_async_exn` in a plain expect test
  so the other tests do not have to return deferreds.
- `Swap.execute` books whatever amounts the `Swap.Quote.t` record carries; `Quote.to_swap_quote`
  is the only place that builds one, keep it that way.
- Simulated rates come from MD5 of currency and date; changing the seeds or the hash changes every
  pinned expect output in `test/` and `test/cli.t`.
- A half-written sibling repo can make the workspace build fail; filter output for `fx-core/`.

## Where to read more

- `README.md`: rules table, offline mode, rate sources, tests, known gaps.
- `CHANGES.md`, and `../specs/repos/fx-core.md` when present.
- `../oxcaml-claude-skills/skills/banking-standards/` and `../oxcaml-claude-skills/GOTCHAS.md`
  ("Product libraries").
- `../oxcaml-claude-skills/AGENTS.md`, the workspace-wide guide.

## Never do

- Install or upgrade opam packages that change the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared switch; dry-run first.
- Publish, tag or release. Commit credentials or print secrets. Poll CI in a loop.
