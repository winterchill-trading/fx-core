(** The life of quotes: [Open], then [Executed] once, or [Expired] when its time runs
    out first. A pure state machine over an immutable value; a service keeps the current
    book in its own store (or rebuilds it from its records) and applies the same rules.

    Claiming a quote for execution is idempotent per execution key: the same key claims
    the same quote again (a retried request), any other key is refused. *)

open! Core

module Status : sig
  type t =
    | Open
    | Executed of
        { execution_key : string
        ; at : Time_ns.Alternate_sexp.t
        }
    | Expired
  [@@deriving sexp_of, compare, equal]

  (** ["open"], ["executed"] or ["expired"]. *)
  val to_string : t -> string
end

type t [@@deriving sexp_of]

val empty : t

(** Adds a new open quote. Fails if its id is already in the book. *)
val add : t -> Quote.t -> t Or_error.t

val find : t -> Quote.Id.t -> Quote.t option

(** The status at [now]; an open quote reads as [Expired] from its expiry on. *)
val status : t -> Quote.Id.t -> now:Time_ns.t -> Status.t option

(** Whether a claim took the quote now or found it already taken with the same key. *)
module Claim : sig
  type t =
    | Fresh
    | Replayed
  [@@deriving sexp_of, compare, equal]
end

(** Marks the quote executed under [execution_key]. Refuses an unknown id, an expired
    quote and a quote executed under another key; a claim with the key that executed it
    returns [Replayed] and the book unchanged. *)
val claim
  :  t
  -> Quote.Id.t
  -> execution_key:string
  -> now:Time_ns.t
  -> (t * Quote.t * Claim.t, Refusal.t) Result.t

(** Drops quotes that were never executed and expired before [before]; executed quotes
    are kept so a late retry still replays. *)
val prune_expired : t -> before:Time_ns.t -> t

(** Number of quotes in the book. *)
val length : t -> int
