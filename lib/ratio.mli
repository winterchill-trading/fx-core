(** Exact non-negative rationals for rates and prices, with rounding to significant
    digits.

    Rates are kept as [Q.t] so a cross rate or an inverse loses nothing until the one
    place where a rule says to round. The text form is the decimal when it terminates
    (["1.0845"]) and the reduced fraction otherwise (["2000/2169"]). *)

open! Core

(** Sexp and bin_prot use the text form. *)
type t = Q.t [@@deriving compare, equal, sexp]

(** ["1.0845"], ["2000/2169"]. *)
val to_string : t -> string

(** Reads [to_string] output: digits, a decimal or a fraction; no sign, exponent or float
    syntax. *)
val of_string_or_error : string -> t Or_error.t

(** [round_sig mode ~digits q] rounds [q] to [digits] significant decimal digits with
    [mode], so the result always has a terminating decimal form:
    [round_sig Down ~digits:3 (Q.of_ints 2 3) = 0.666]. Zero stays zero. Raises unless
    [digits >= 1] or when [q] is negative. *)
val round_sig : Money.Rounding.t -> digits:int -> t -> t

(** [10^n] as a rational, for any integer [n]. *)
val pow10 : int -> t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    (** Bin_prot: the text form as a string. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
