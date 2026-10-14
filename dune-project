(lang dune 3.17)

(name fx-core)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/fx-core))

(homepage "https://github.com/winterchill-trading/fx-core")

(bug_reports "https://github.com/winterchill-trading/fx-core/issues")

(documentation "https://github.com/winterchill-trading/fx-core#readme")

(package
 (name fx-core)
 (synopsis
  "Foreign exchange for banks: reference rates, cross rates, retail pricing, quotes and ledger booking")
 (description
  "fx-core prices currency conversions the way a retail or business bank does: a table of reference rates per currency, date and origin (live or bundled), cross rates through a pivot currency, staleness and maximum-age rules, a spread in basis points with per-tier caps, customer rates rounded down to a fixed number of significant digits, sell-fixed and buy-fixed amounts rounded against the customer by at most one minor unit, a fee in the sold currency, single-use quotes with a time to live, card conversion re-pricing at the authorisation rate, portfolio estimates in a base currency, and the booking of an executed exchange as balanced ledger entries through payments-core. A rate-source module type has a deterministic simulated implementation. Pure and exact (rationals, never floats); the library never persists anything. Requires the OxCaml compiler (through its money dependency).")
 (tags
  (fx foreign-exchange currency rates pricing banking ledger oxcaml))
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (core_unix
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (async_kernel
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (async
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_jane
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  zarith
  money
  ledger
  payments-core
  (expect_test_helpers_core
   (and
    :with-test
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (odoc :with-doc)))
