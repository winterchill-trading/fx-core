(** Retail conversion pricing: from a mid rate and a spread to the amounts a customer
    sells and buys.

    Rules, all exact:
    - customer rate = mid x (1 - spread), rounded {b down} to 10 significant digits, so
      the published rate is never better than the one used;
    - sell fixed: bought amount = floor(sold x customer rate) in the bought currency's
      minor unit;
    - buy fixed: sold amount = ceil(bought / customer rate) in the sold currency's minor
      unit;
    - fee = sold x spread, half-up to the sold currency's minor unit. It is the cost of
      the spread expressed in the sold currency and is {e included} in the sold amount
      (shown to the customer, not charged on top);
    - a conversion that would give nothing on the other side is refused, and so is one
      above the maximum amount.

    Rounding therefore never favours the customer, and never costs them more than one
    minor unit beyond the published rate. *)

open! Core

(** Which side of the conversion the customer fixed. *)
module Fixed_side : sig
  type t =
    | Sell
    | Buy
  [@@deriving sexp, compare, equal, enumerate]

  (** ["sell"] or ["buy"]. *)
  val to_string : t -> string

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** What the customer asked for: an exact amount to sell, or an exact amount to buy. *)
module Request : sig
  type t =
    | Sell of Money.Amount.t
    | Buy of Money.Amount.t
  [@@deriving sexp_of, compare, equal]

  val fixed_side : t -> Fixed_side.t
  val amount : t -> Money.Amount.t
end

(** Significant digits of a customer rate: 10. *)
val customer_digits : int

(** [mid x (1 - spread_bps / 10_000)] rounded down to [customer_digits]. *)
val customer_rate : mid:Ratio.t -> spread_bps:int -> Ratio.t

(** [1 / customer_rate] to [customer_digits], half-even: the rate as quoted the other
    way round, for display. *)
val inverse_customer_rate : Ratio.t -> Ratio.t

(** The default maximum on either side: 2^53 - 1 minor units, the largest integer a
    JSON number carries exactly. *)
val default_max_minor_units : Z.t

(** The three amounts of a conversion. *)
module Amounts : sig
  type t =
    { sell : Money.Amount.t (** total taken from the customer, fee included *)
    ; buy : Money.Amount.t (** given to the customer *)
    ; fee : Money.Amount.t (** part of [sell], in the sold currency *)
    }
  [@@deriving sexp_of, compare, equal]
end

(** The amounts for [request] at an already rounded [customer_rate] (units of [buy] per
    one [sell]). Used directly to re-price at a rate fixed earlier (card settlement).
    Refuses an amount in neither currency, a non-positive amount, a result of zero, and
    an amount above [max_minor_units] on either side. *)
val amounts
  :  ?max_minor_units:Z.t
  -> sell:Money.Currency.t
  -> buy:Money.Currency.t
  -> customer_rate:Ratio.t
  -> spread_bps:int
  -> Request.t
  -> (Amounts.t, Refusal.t) Result.t

(** A priced conversion. *)
type t =
  { amounts : Amounts.t
  ; fixed_side : Fixed_side.t
  ; mid : Rate_table.Mid.t
  ; customer_rate : Ratio.t
  ; inverse_customer_rate : Ratio.t
  ; spread : Spread.t
  }
[@@deriving sexp_of, compare, equal]

(** Prices [request] from [mid] with the applied spread of [spread]. *)
val price
  :  ?max_minor_units:Z.t
  -> mid:Rate_table.Mid.t
  -> spread:Spread.t
  -> Request.t
  -> (t, Refusal.t) Result.t
