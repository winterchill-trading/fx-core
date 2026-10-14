(** Estimates at mid: what a set of balances is worth in one base currency, and whether an
    amount reaches a threshold expressed in another currency.

    Estimates use the exact mid rate (no spread, no fee), sum exactly, and round once,
    half-even, to the base currency's minor unit. They are labelled estimates: nothing is
    executed at these values. *)

open! Core

type t =
  { base : Money.Currency.t
  ; total : Money.Amount.t option (** [None] when any currency has no rate *)
  ; missing : Money.Currency.t list (** held currencies without a usable rate, sorted *)
  ; basis : Basis.t option (** weakest basis of the rates used; [None] if none *)
  }
[@@deriving sexp_of, compare, equal]

(** Values [holdings] in [base] with the rates of [as_of]. Amounts already in [base] need
    no rate. A rate refused by [freshness] counts as missing. *)
val estimate
  :  ?freshness:Freshness.Policy.t
  -> Rate_table.t
  -> base:Money.Currency.t
  -> Money.Amount.t list
  -> now:Time_ns.t
  -> t

(** Whether [amount] is worth at least [threshold] at mid. Without a usable rate the
    answer is [true]: a check that guards a riskier path (an extra confirmation, a review)
    must not be skipped because a rate is missing. *)
val at_least
  :  ?freshness:Freshness.Policy.t
  -> Rate_table.t
  -> Money.Amount.t
  -> threshold:Money.Amount.t
  -> now:Time_ns.t
  -> bool
