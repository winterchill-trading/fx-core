open! Core

module Stable = struct
  module V1 = struct
    module Wire = struct
      type t =
        { pivot : Money.Currency.Stable.V1.t
        ; currency : Money.Currency.Stable.V1.t
        ; date : Date.Stable.V1.t
        ; per_pivot : Ratio.Stable.V1.t
        ; origin : Origin.Stable.V1.t
        ; source : string
        ; fetched_at : Time_ns.Stable.Alternate_sexp.V1.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end

    type t = Wire.t =
      { pivot : Money.Currency.t
      ; currency : Money.Currency.t
      ; date : Date.t
      ; per_pivot : Ratio.t
      ; origin : Origin.t
      ; source : string
      ; fetched_at : Time_ns.t
      }

    let compare = Wire.compare
    let equal = Wire.equal
    let sexp_of_t = Wire.sexp_of_t

    let validate (t : t) =
      if Money.Currency.equal t.pivot t.currency
      then
        Or_error.error_s
          [%message
            "observation: currency is the pivot" ~currency:(t.currency : Money.Currency.t)]
      else if Q.sign t.per_pivot <= 0
      then
        Or_error.error_s
          [%message
            "observation: rate must be positive" ~per_pivot:(t.per_pivot : Ratio.t)]
      else Ok t
    ;;

    let t_of_sexp sexp =
      match validate (Wire.t_of_sexp sexp) with
      | Ok t -> t
      | Error e -> of_sexp_error (Error.to_string_hum e) sexp
    ;;

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Wire)
        (struct
          type nonrec t = t

          let to_binable = Fn.id
          let of_binable w = Or_error.ok_exn (validate w)
        end)
  end
end

include Stable.V1

let create ~pivot ~currency ~date ~per_pivot ~origin ~source ~fetched_at =
  validate { pivot; currency; date; per_pivot; origin; source; fetched_at }
;;
