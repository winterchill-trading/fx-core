open! Core

module Stable = struct
  module V1 = struct
    type t =
      { source : string
      ; origin : Origin.Stable.V1.t
      ; rate_date : Date.Stable.V1.t
      ; fetched_at : Time_ns.Stable.Alternate_sexp.V1.t
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let of_observation (o : Observation.t) =
  { source = o.source; origin = o.origin; rate_date = o.date; fetched_at = o.fetched_at }
;;

let combine a b =
  let older = if Time_ns.( <= ) a.fetched_at b.fetched_at then a else b in
  { source = older.source
  ; origin =
      (match a.origin, b.origin with
       | Live, Live -> Live
       | Bundled, _ | _, Bundled -> Bundled)
  ; rate_date = Date.min a.rate_date b.rate_date
  ; fetched_at = older.fetched_at
  }
;;

let age t ~now = Time_ns.Span.max Time_ns.Span.zero (Time_ns.diff now t.fetched_at)
