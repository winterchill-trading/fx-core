(** Staleness and maximum-age rules for reference rates.

    A rate is {e stale} once its copy is older than [stale_after] (shown to users, still
    usable), and {e too old} once either its rate date or its fetch time is more than
    [max_age] before the time of the request (refused). Reference rates are published per
    business day, so a weekend or a holiday makes a rate a few days old without anything
    being wrong; [max_age] is the bound beyond which the bank will not price at all.

    {b Offline mode.} {!Policy.offline} has no maximum age: a deployment running on
    bundled tables only (no network, demos, tests) keeps quoting from the newest bundled
    rate however old it is, and every basis it shows is reported stale. *)

open! Core

module Policy : sig
  type t =
    { stale_after : Time_ns.Span.t
    ; max_age : Time_ns.Span.t option (** [None]: never refuse on age *)
    }
  [@@deriving sexp, compare, equal]

  (** Stale after 3 hours, refused after 7 days. *)
  val default : t

  (** Stale after 3 hours, never refused: see offline mode above. *)
  val offline : t
end

type t =
  { age : Time_ns.Span.t (** since the fetch, never negative *)
  ; stale : bool
  ; too_old : bool
  }
[@@deriving sexp_of, compare, equal]

(** How fresh [basis] is for a request at [now]. The rate date is compared in whole UTC
    days with the date of [now]. *)
val assess : Policy.t -> Basis.t -> now:Time_ns.t -> t

(** [Ok ()] unless [assess] says too old. *)
val check : Policy.t -> Basis.t -> now:Time_ns.t -> (unit, Refusal.t) Result.t
