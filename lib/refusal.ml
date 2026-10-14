open! Core

type t =
  | Same_currency of Money.Currency.t
  | No_rate of { missing : Money.Currency.t list }
  | Rate_too_old of
      { rate_date : Date.t
      ; fetched_at : Time_ns.Alternate_sexp.t
      }
  | Amount_not_positive of Money.Amount.t
  | Amount_too_small of Money.Amount.t
  | Amount_too_large of Money.Amount.t
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
[@@deriving sexp_of, compare, equal]

let code = function
  | Same_currency _ -> "same_currency"
  | No_rate _ -> "no_rate"
  | Rate_too_old _ -> "rate_too_old"
  | Amount_not_positive _ -> "amount_not_positive"
  | Amount_too_small _ -> "amount_too_small"
  | Amount_too_large _ -> "amount_too_large"
  | Currency_mismatch _ -> "currency_mismatch"
  | Unknown_quote _ -> "unknown_quote"
  | Quote_expired _ -> "quote_expired"
  | Quote_already_used _ -> "quote_already_used"
  | Quote_mismatch _ -> "quote_mismatch"
;;

let to_error t = Error.create_s [%sexp (t : t)]
