(** A table of reference rates per currency, date and origin, all quoted against one
    pivot currency, and the cross rates derived from it.

    Rates are stored as units of each currency per one unit of the pivot (USD in most
    feeds). The mid rate between two other currencies goes through the pivot:
    [mid A->B = per_pivot B / per_pivot A], computed exactly and then rounded to 20
    significant digits (half-even), which is far below a minor unit for any realistic
    amount but keeps every printed rate finite.

    The table is an immutable value: adding observations returns a new table. A lookup
    takes the newest date on or before the requested day; on that date a live rate is
    preferred over a bundled one. *)

open! Core

type t [@@deriving sexp_of]

(** An empty table quoted against [pivot]. *)
val create : pivot:Money.Currency.t -> t

val pivot : t -> Money.Currency.t

(** Adds or replaces the observation for its (currency, date, origin). Fails when its
    pivot is not the table's. *)
val add : t -> Observation.t -> t Or_error.t

(** [add] for each observation in order; all or nothing. *)
val add_all : t -> Observation.t list -> t Or_error.t

(** The pivot and every currency with at least one observation, sorted. *)
val currencies : t -> Money.Currency.t list

(** The number of stored observations. *)
val length : t -> int

(** Which observations a lookup may use. *)
module Selection : sig
  type t =
    | Prefer_live (** live and bundled, live first on the same date *)
    | Bundled_only
    (** bundled tables only: deterministic pricing of past days (demo history, replays)
        that must not depend on what was fetched since *)
  [@@deriving sexp, compare, equal, enumerate]
end

(** The observation for [currency] on the newest date on or before [as_of]. [None] for
    the pivot itself and for currencies without such an observation. *)
val lookup
  :  ?selection:Selection.t
  -> t
  -> Money.Currency.t
  -> as_of:Date.t
  -> Observation.t option

(** One observation per date between [from] and [to_] inclusive (live preferred), oldest
    first. Empty for the pivot. *)
val history
  :  ?selection:Selection.t
  -> t
  -> Money.Currency.t
  -> from:Date.t
  -> to_:Date.t
  -> Observation.t list

(** The newest rate date of any observation, if any. *)
val latest_date : t -> Date.t option

(** A mid-market cross rate between two currencies. *)
module Mid : sig
  type t =
    { sell : Money.Currency.t
    ; buy : Money.Currency.t
    ; exact : Ratio.t (** units of [buy] per one unit of [sell], unrounded *)
    ; rate : Ratio.t (** [exact] to 20 significant digits, half-even *)
    ; basis : Basis.t
    }
  [@@deriving sexp_of, compare, equal]

  (** [1 / exact] to 20 significant digits, half-even. *)
  val inverse_rate : t -> Ratio.t

  (** As a {!Money.Rate.t} with [sell] as base, at [rate], stamped with the basis fetch
      time and source. *)
  val to_money_rate : t -> Money.Rate.t
end

(** Significant digits of a published mid rate: 20. *)
val mid_digits : int

(** The mid rate from [sell] to [buy] on [as_of]. Refuses the same currency twice and
    names every currency without a rate. Staleness is the caller's decision
    ({!Freshness}). *)
val mid
  :  ?selection:Selection.t
  -> t
  -> sell:Money.Currency.t
  -> buy:Money.Currency.t
  -> as_of:Date.t
  -> (Mid.t, Refusal.t) Result.t

(** Mid rates per date between [from] and [to_], for dates where both currencies have a
    rate of their own (the pivot always has one). Oldest first; each point has the basis
    of that date. *)
val cross_history
  :  ?selection:Selection.t
  -> t
  -> sell:Money.Currency.t
  -> buy:Money.Currency.t
  -> from:Date.t
  -> to_:Date.t
  -> Mid.t list
