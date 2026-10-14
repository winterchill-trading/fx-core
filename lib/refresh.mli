(** Keeping a rate table current: when to fetch next, what the last attempts say about
    the source, and one fetch-and-merge step.

    The schedule is pure: after a success the next fetch is one [interval] later, after a
    failure one [retry_after] later. A service runs the loop with its own timer and
    records each {!Attempt.t}; {!Status.t} is the fold of those attempts and answers a
    status endpoint (reachable, last success, last attempt, newest rate date, stale). *)

open! Async_kernel
open! Core

module Policy : sig
  type t =
    { interval : Time_ns.Span.t
    ; retry_after : Time_ns.Span.t
    }
  [@@deriving sexp, compare, equal]

  (** Every hour; five minutes after a failure. *)
  val default : t
end

module Attempt : sig
  type outcome =
    | Succeeded of
        { observations : int
        ; latest_rate_date : Date.t option
        }
    | Failed of string
  [@@deriving sexp_of, compare, equal]

  type t =
    { at : Time_ns.Alternate_sexp.t
    ; outcome : outcome
    }
  [@@deriving sexp_of, compare, equal]
end

module Status : sig
  type t =
    { last_attempt_at : Time_ns.Alternate_sexp.t option
    ; last_success_at : Time_ns.Alternate_sexp.t option
    ; latest_rate_date : Date.t option
    ; reachable : bool (** the last attempt succeeded *)
    }
  [@@deriving sexp_of, compare, equal]

  (** No attempt yet: not reachable. *)
  val initial : t

  val apply : t -> Attempt.t -> t

  (** Stale when no fetch ever succeeded or the last success is older than the policy's
      [stale_after]. *)
  val stale : t -> Freshness.Policy.t -> now:Time_ns.t -> bool
end

(** When to try next: now if never tried, else [interval] after a success or
    [retry_after] after a failure. *)
val next_attempt_at : Policy.t -> Status.t -> now:Time_ns.t -> Time_ns.t

(** Fetches the source's latest rates and merges them into [table]. On failure the table
    is returned unchanged with a [Failed] attempt; it is never emptied. *)
val fetch
  :  Rate_source.t
  -> Rate_table.t
  -> now:Time_ns.t
  -> (Rate_table.t * Attempt.t) Deferred.t
