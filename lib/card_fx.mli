(** Card payments in a foreign currency.

    At authorisation the merchant amount is fixed and the account side is a buy-fixed
    conversion: the account amount is rounded {b up}, the fee half-up, at the customer
    rate of that moment. The rate is then frozen on the authorisation:
    - a final amount that differs from the authorised one (tips, fuel, hotels) is
      re-priced at the {e same} customer rate, so the customer sees no second rate for one
      purchase;
    - a refund returns the same share of what was paid as the refunded share of the
      merchant amount, rounded down, so a full refund returns exactly what was paid and
      partial refunds never add up to more. *)

open! Core

(** The account side of a foreign card payment at authorisation. *)
type t =
  { merchant_amount : Money.Amount.t
  ; account_amount : Money.Amount.t (** includes [fee] *)
  ; fee : Money.Amount.t (** in the account currency *)
  ; mid_rate : Ratio.t (** merchant units per account unit *)
  ; customer_rate : Ratio.t
  ; inverse_customer_rate : Ratio.t
  ; spread : Spread.t
  ; basis : Basis.t
  }
[@@deriving sexp_of, compare, equal]

(** Prices an authorisation of [merchant_amount] on an account in [account_currency]
    from the rates of the UTC day of [now]. Refuses a merchant amount in the account
    currency ([Same_currency]: no conversion needed), a missing or too-old rate. *)
val authorise
  :  ?freshness:Freshness.Policy.t
  -> Rate_table.t
  -> account_currency:Money.Currency.t
  -> merchant_amount:Money.Amount.t
  -> spread:Spread.t
  -> now:Time_ns.t
  -> (t, Refusal.t) Result.t

(** The account side of a final merchant amount at the authorisation's customer rate
    and spread. *)
val reprice : t -> final_merchant_amount:Money.Amount.t -> (t, Refusal.t) Result.t

(** [refund_share ~paid ~settled_merchant ~refund_merchant] is
    [floor(paid * refund_merchant / settled_merchant)] in [paid]'s currency. Refuses a
    refund above the settled merchant amount, a non-positive amount or mixed
    currencies. *)
val refund_share
  :  paid:Money.Amount.t
  -> settled_merchant:Money.Amount.t
  -> refund_merchant:Money.Amount.t
  -> (Money.Amount.t, Refusal.t) Result.t
