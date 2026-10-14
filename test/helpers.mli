open! Core
open Fx_core

val usd : Money.Currency.t
val eur : Money.Currency.t
val gbp : Money.Currency.t
val jpy : Money.Currency.t
val chf : Money.Currency.t
val kwd : Money.Currency.t

(** [amount "12.34 EUR"]. *)
val amount : string -> Money.Amount.t

val ratio : string -> Ratio.t

(** Friday 2026-10-09 12:00 UTC plus [sec] seconds. *)
val at : ?sec:int -> unit -> Time_ns.t

val friday : Date.t

(** A live observation fetched at [at ()] unless given. *)
val obs
  :  ?origin:Origin.t
  -> ?date:Date.t
  -> ?fetched_at:Time_ns.t
  -> Money.Currency.t
  -> string
  -> Observation.t

(** EUR 0.92, GBP 0.79, JPY 150, CHF 0.88, KWD 0.307 per USD on [friday], live. *)
val table : unit -> Rate_table.t

val ok : ('a, Refusal.t) Result.t -> 'a
val print_refusal : ('a, Refusal.t) Result.t -> unit
