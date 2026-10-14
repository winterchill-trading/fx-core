(** One reference rate: how many units of [currency] one unit of the [pivot] currency
    buys on [date], from [source] and [origin].

    Reference rates are mid-market values (no spread), usually blended from central-bank
    publications and published once per business day, so [date] is the day the rate
    applies to and [fetched_at] is when this copy was obtained. *)

open! Core

type t = private
  { pivot : Money.Currency.t (** the currency every rate is quoted against, e.g. USD *)
  ; currency : Money.Currency.t
  ; date : Date.t
  ; per_pivot : Ratio.t (** units of [currency] per one unit of [pivot], positive *)
  ; origin : Origin.t
  ; source : string (** name of the rate source *)
  ; fetched_at : Time_ns.t
  }
[@@deriving sexp, compare, equal]

(** Fails unless [per_pivot] is positive and [currency] differs from [pivot]. *)
val create
  :  pivot:Money.Currency.t
  -> currency:Money.Currency.t
  -> date:Date.t
  -> per_pivot:Ratio.t
  -> origin:Origin.t
  -> source:string
  -> fetched_at:Time_ns.t
  -> t Or_error.t

(** Versioned serializers whose bin_prot shape never changes. Reading validates like
    [create]. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
