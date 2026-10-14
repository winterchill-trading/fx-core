# AGENTS.md (lib/)

The `fx-core` library, wrapped as `Fx_core` (`fx_core.ml` lists the modules).

- Dependency order inside the library: `Ratio` -> `Origin`, `Observation`, `Basis` -> `Refusal`,
  `Freshness` -> `Rate_table` -> `Spread`, `Pricing` -> `Quote`, `Quote_book`, `Exchange`,
  `Card_fx`, `Valuation` -> `Rate_source`, `Simulated_source`, `Bundled`, `Refresh`.
- Rounding rules live in `Pricing` (customer rate down to 10 significant digits, sell-fixed floor,
  buy-fixed ceil, fee half-up) and `Rate_table` (mid at 20 digits half-even). Change them only with
  the properties in `test/test_pricing.ml` still passing.
- Only `Rate_source`, `Simulated_source` and `Refresh` touch `Async_kernel`; keep the rest synchronous.
- Every new public value needs odoc; check with `dune build --root .. @fx-core/doc`.
