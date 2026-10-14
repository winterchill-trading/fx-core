# AGENTS.md (examples/)

`quickstart.ml` goes from a rate table to a quote, a quote book and the booked ledger entries. It
is the README's walk-through and CI runs it (`dune exec ./examples/quickstart.exe`), so keep it
compiling and keep the README output block in sync when it changes.

`bundled-rates.csv` is the documented example of the `Bundled` CSV shape (both row forms and
one unknown currency for the lenient parse). `test/test_bundled_example.ml` parses it; update
its expect output when the file changes.
