(** A firm price for one conversion, valid for a short time and usable once.

    A quote fixes the amounts the customer sells and buys, the fee inside the sold amount,
    the mid and customer rates (with their inverses for display), the spread and the basis
    of the reference rates. It is priced from a {!Rate_table} at the request time and
    refused when the newest usable rate is too old for the {!Freshness.Policy}.

    The quote id is a {!Payments_core.Swap.Id.t}, so a quote converts to a
    {!Payments_core.Swap.Quote.t} for booking without a second identifier. *)

open! Core

module Id = Payments_core.Swap.Id

type t =
  { id : Id.t
  ; sell : Money.Amount.t (** taken from the customer, fee included *)
  ; buy : Money.Amount.t (** given to the customer *)
  ; fee : Money.Amount.t (** spread cost in the sold currency, included in [sell] *)
  ; fixed_side : Pricing.Fixed_side.t
  ; mid_rate : Ratio.t (** units bought per unit sold, 20 significant digits *)
  ; inverse_mid_rate : Ratio.t
  ; customer_rate : Ratio.t (** 10 significant digits, rounded down *)
  ; inverse_customer_rate : Ratio.t
  ; spread : Spread.t
  ; basis : Basis.t
  ; stale : bool (** the basis was stale when quoted (still usable) *)
  ; created_at : Time_ns.t
  ; expires_at : Time_ns.t
  }
[@@deriving sexp, compare, equal]

(** How quotes are made. *)
module Config : sig
  type t =
    { ttl : Time_ns.Span.t
    ; freshness : Freshness.Policy.t
    ; max_minor_units : Z.t
    }
  [@@deriving sexp_of]

  (** 30 seconds, {!Freshness.Policy.default}, {!Pricing.default_max_minor_units}. *)
  val default : t

  (** [default] with {!Freshness.Policy.offline}. *)
  val offline : t
end

(** Prices [request] (selling [sell], buying [buy]) at [now] against the rates of the UTC
    day of [now]. [selection] defaults to live-preferred; pass [Bundled_only] to price a
    past day deterministically. *)
val create
  :  ?config:Config.t
  -> ?selection:Rate_table.Selection.t
  -> Rate_table.t
  -> id:Id.t
  -> sell:Money.Currency.t
  -> buy:Money.Currency.t
  -> spread:Spread.t
  -> Pricing.Request.t
  -> now:Time_ns.t
  -> (t, Refusal.t) Result.t

(** [now >= expires_at]. *)
val is_expired : t -> now:Time_ns.t -> bool

(** The quote as payments-core books it: the mid rate as [market], the applied spread,
    and the amounts unchanged. *)
val to_swap_quote : t -> Payments_core.Swap.Quote.t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
