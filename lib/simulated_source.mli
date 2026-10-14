(** A deterministic reference-rate source for tests, demos and offline development.

    Each currency starts from a seed rate per pivot unit. The rate of a business day is
    the seed moved by a pseudo-random amount within [volatility_bps] that depends only on
    the currency and the date (an MD5 of both), rounded to 6 significant digits, so two
    runs and two machines agree on every rate. Rates are published Monday to Friday; on a
    weekend the newest rate is Friday's.

    The clock comes from a [Async_kernel.Time_source], so tests drive it with a synthetic
    one. A source can be made unreachable to exercise refresh failures. *)

open! Async_kernel
open! Core

type t

(** Fails when a seed is not positive, a currency is the pivot or appears twice, or
    [volatility_bps] is negative. Defaults: name ["simulated"], 50 bps. *)
val create
  :  ?name:string
  -> ?volatility_bps:int
  -> pivot:Money.Currency.t
  -> seeds:(Money.Currency.t * Ratio.t) list
  -> time_source:[> read ] Time_source.T1.t
  -> unit
  -> t Or_error.t

(** A few common currencies against USD at round, plausible values: EUR, GBP, CHF, JPY,
    CAD, AUD, SEK, NOK, PLN. *)
val usd_seeds : unit -> (Money.Currency.t * Ratio.t) list

(** While [false], [latest] and [history] fail as an unreachable server would. *)
val set_reachable : t -> bool -> unit

(** The rate the source publishes for [currency] on [date] (the business day on or before
    it), if the currency is seeded. Pure. *)
val rate : t -> Money.Currency.t -> Date.t -> Ratio.t option

(** The business day on or before [date]. *)
val publication_date : Date.t -> Date.t

include Rate_source.S with type t := t

(** [Rate_source.T] of this source. *)
val pack : t -> Rate_source.t
