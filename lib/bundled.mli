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
    origin [Bundled].

    An optional fourth column, [fetched_at], records when the snapshot was actually
    obtained, as an ISO 8601 timestamp with an explicit offset:
    {v
    date,currency,rate,fetched_at
    2026-10-09,EUR,0.9187,2026-10-09T16:05:00Z
    2026-10-09,JPY,149.82,
    v}
    A row that carries it keeps that time, so the basis shows the snapshot's real age. A
    row without it (three fields, or an empty fourth) gets midnight UTC at the start of
    its rate date: a bundled rate is never younger than its publication, so its basis is
    honest about age (and a deployment in offline mode shows it as stale). Either header
    is accepted, and rows of both shapes may be mixed.

    [examples/bundled-rates.csv] is a complete example of both shapes. *)

open! Core

(** A row skipped because its currency code is not one {!Money.Currency} knows. *)
module Unknown_currency : sig
  type t =
    { line : int (** 1-based line number in the text *)
    ; currency : string (** the code as written *)
    }
  [@@deriving sexp, compare, equal]
end

(** Parses CSV text. Fails with the line number on a malformed line, an unknown currency,
    the pivot as a currency, a rate that is not a positive decimal, or a [fetched_at] that
    is not a timestamp with an offset.

    With [on_unknown_currency] the parse is lenient about currencies: a row whose currency
    is unknown (a table shipped for more currencies than this build supports) is skipped
    and passed to [on_unknown_currency] instead of failing the parse. Every other check
    still applies to the skipped row, including its date and rate. *)
val parse
  :  ?on_unknown_currency:(Unknown_currency.t -> unit)
  -> pivot:Money.Currency.t
  -> source:string
  -> string
  -> Observation.t list Or_error.t

(** {!parse} in lenient mode, returning the skipped rows, in line order, with the
    observations. *)
val parse_lenient
  :  pivot:Money.Currency.t
  -> source:string
  -> string
  -> (Observation.t list * Unknown_currency.t list) Or_error.t

(** The CSV text of [observations] (header included), sorted by date then currency. With
    [~fetched_at:true] (default [false]) each row also carries its [fetched_at] in UTC,
    such as [2026-10-09T16:05:00Z], so {!parse} restores it exactly. *)
val to_csv : ?fetched_at:bool -> Observation.t list -> string
