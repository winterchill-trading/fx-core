# AGENTS.md (bin/)

`main.ml` is the `fx-core` command (`Command.async_or_error` groups):

- `rates`: rates per USD from the simulated source, or `-bundled FILE`.
- `quote SELL BUY (-sell X | -buy X) [-spread BPS] [-cap BPS]`: prints a `Quote.t` sexp; a bundled
  file switches to offline freshness.
- `bundle -from DATE -to DATE`: simulated history as bundled CSV.

Behaviour is pinned by `test/cli.t/run.t`; update it with `dune promote` after reading the diff.
