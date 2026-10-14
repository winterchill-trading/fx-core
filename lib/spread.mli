(** The spread a bank adds to the mid rate, in basis points, and the caps that customer
    tiers, plans or contracts put on it.

    The applied spread is the smallest of the standard spread and every cap that applies,
    so a cap can only lower the price, never raise it. Both values are kept: statements
    and receipts usually show the standard spread next to the one charged. *)

open! Core

type t = private
  { standard_bps : int
  ; applied_bps : int (** [<= standard_bps] *)
  }
[@@deriving sexp, compare, equal]

(** The largest spread accepted: 1000 bps (10 %). Anything above is a configuration
    mistake rather than a price. *)
val max_bps : int

(** [create ~standard_bps ?caps ()] applies the smallest cap. Fails when a value is
    negative or [standard_bps] is above [max_bps]. *)
val create : standard_bps:int -> ?caps:int list -> unit -> t Or_error.t

(** No spread at all, e.g. for an estimate at mid. *)
val zero : t

(** The same spread with one more cap. Fails on a negative cap. *)
val cap : t -> bps:int -> t Or_error.t

(** A standard spread and the caps of named tiers ("standard", "plus", "business"...). *)
module Schedule : sig
  type spread := t

  type t =
    { standard_bps : int
    ; tier_caps : int String.Map.t
    }
  [@@deriving sexp, compare, equal]

  (** Fails like [Spread.create]. *)
  val create : standard_bps:int -> tier_caps:(string * int) list -> t Or_error.t

  (** The spread for a customer in [tier] (no cap for an unknown or absent tier), with an
      extra [cap_bps] if given (a per-request cap from a contract or a provider). *)
  val spread : t -> ?tier:string -> ?cap_bps:int -> unit -> spread Or_error.t
end

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
