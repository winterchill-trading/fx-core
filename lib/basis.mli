(** What a price was based on: the source, the origin and the dates of the reference rates
    behind it. A cross rate combines two observations; its basis is the weaker of the two
    (the older rate date, the older fetch, bundled if either leg was bundled), so
    staleness is never understated. *)

open! Core

type t =
  { source : string
  ; origin : Origin.t
  ; rate_date : Date.t
  ; fetched_at : Time_ns.t
  }
[@@deriving sexp, compare, equal]

val of_observation : Observation.t -> t

(** The weaker of two bases, as described above. The source is the one of the older fetch. *)
val combine : t -> t -> t

(** [now - fetched_at], never negative. *)
val age : t -> now:Time_ns.t -> Time_ns.Span.t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
