(** Bundled rate tables: reference rates shipped with an application as CSV text, for
    offline operation and for history that predates the first live fetch.

    Format, one observation per line after a header:
    {v
date,currency,rate
2026-10-09,EUR,0.9187
2026-10-09,JPY,149.82
    v}
    The rate is units of [currency] per one unit of the pivot, written as an exact
    decimal. Blank lines and lines starting with [#] are ignored. Every observation gets
    origin [Bundled] and a [fetched_at] of midnight UTC at the start of its rate date: a
    bundled rate is never younger than its publication, so its basis is honest about age
    (and a deployment in offline mode shows it as stale). *)

open! Core

(** Parses CSV text. Fails with the line number on a malformed line, an unknown
    currency, the pivot as a currency, or a rate that is not a positive decimal. *)
val parse
  :  pivot:Money.Currency.t
  -> source:string
  -> string
  -> Observation.t list Or_error.t

(** The CSV text of [observations] (header included), sorted by date then currency. *)
val to_csv : Observation.t list -> string
