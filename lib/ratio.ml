open! Core

type t = Q.t

let compare a b = Q.compare a b
let equal a b = Q.equal a b
let to_string = Money.Rate.price_to_string
let of_string_or_error = Money.Rate.price_of_string
let sexp_of_t t = Sexp.Atom (to_string t)

let t_of_sexp sexp =
  match sexp with
  | Sexp.Atom s ->
    (match of_string_or_error s with
     | Ok q -> q
     | Error e -> of_sexp_error (Error.to_string_hum e) sexp)
  | Sexp.List _ -> of_sexp_error "ratio: expected an atom" sexp
;;

let pow10 n =
  if n >= 0
  then Q.of_bigint (Z.pow (Z.of_int 10) n)
  else Q.inv (Q.of_bigint (Z.pow (Z.of_int 10) (-n)))
;;

(* The decimal exponent [e] with [10^e <= q < 10^(e+1)], for a positive [q]. The digit
   counts of numerator and denominator give it to within one. *)
let exponent q =
  let digits z = String.length (Z.to_string z) in
  let e = digits (Q.num q) - digits (Q.den q) in
  if Q.( >= ) q (pow10 e) then e else e - 1
;;

let round_sig mode ~digits q =
  if digits < 1
  then raise_s [%message "Ratio.round_sig: digits must be positive" (digits : int)];
  match Q.sign q with
  | 0 -> Q.zero
  | s when s < 0 ->
    raise_s [%message "Ratio.round_sig: negative value" ~q:(Q.to_string q)]
  | _ ->
    let scale = pow10 (digits - 1 - exponent q) in
    Q.div (Q.of_bigint (Money.Rounding.round mode (Q.mul q scale))) scale
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t

    let compare = compare
    let equal = equal
    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    include Binable.Of_stringable_without_uuid [@alert "-legacy"] (struct
        type nonrec t = t

        let to_string = to_string
        let of_string s = Or_error.ok_exn (of_string_or_error s)
      end)
  end
end
