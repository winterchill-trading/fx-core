(** Why a rate, quote or exchange was refused. Every pricing and quoting function returns
    one of these instead of an [Error.t], so a service can map each case to its own error
    code and message. [code] gives a stable snake_case name for logs and APIs. *)

open! Core

type t =
  | Same_currency of Money.Currency.t (** selling and buying the same currency *)
  | No_rate of { missing : Money.Currency.t list }
  (** no reference rate is known for these currencies at the requested time *)
  | Rate_too_old of
      { rate_date : Date.t
      ; fetched_at : Time_ns.Alternate_sexp.t
      } (** the newest rate is older than the policy's maximum age *)
  | Amount_not_positive of Money.Amount.t
  | Amount_too_small of Money.Amount.t
  (** the conversion would give nothing at all on the other side *)
  | Amount_too_large of Money.Amount.t (** above the configured maximum *)
  | Currency_mismatch of
      { expected : Money.Currency.t
      ; got : Money.Currency.t
      }
  | Unknown_quote of string
  | Quote_expired of
      { id : string
      ; expires_at : Time_ns.Alternate_sexp.t
      }
  | Quote_already_used of string
  | Quote_mismatch of string
  (** the execution request does not match the quote's currencies or amounts *)
  | Insufficient_funds of
      { available : Money.Amount.t
      ; required : Money.Amount.t
      } (** the paying account's available balance does not cover the sold amount *)
[@@deriving sexp_of, compare, equal]

(** ["same_currency"], ["no_rate"], ["rate_too_old"], ["amount_not_positive"],
    ["amount_too_small"], ["amount_too_large"], ["currency_mismatch"], ["unknown_quote"],
    ["quote_expired"], ["quote_already_used"], ["quote_mismatch"], ["insufficient_funds"]. *)
val code : t -> string

(** As an [Error.t], for callers that work in [Or_error]. *)
val to_error : t -> Error.t
