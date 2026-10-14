open! Core

let max_bps = 1000

module Stable = struct
  module V1 = struct
    module Wire = struct
      type t =
        { standard_bps : int
        ; applied_bps : int
        }
      [@@deriving bin_io, sexp, compare, equal]
    end

    type t = Wire.t =
      { standard_bps : int
      ; applied_bps : int
      }

    let compare = Wire.compare
    let equal = Wire.equal
    let sexp_of_t = Wire.sexp_of_t

    let validate (t : t) =
      if t.standard_bps < 0 || t.standard_bps > max_bps
      then Or_error.error_s [%message "spread out of range" ~standard_bps:(t.standard_bps : int)]
      else if t.applied_bps < 0 || t.applied_bps > t.standard_bps
      then
        Or_error.error_s
          [%message
            "applied spread must be between zero and the standard"
              ~applied_bps:(t.applied_bps : int)
              ~standard_bps:(t.standard_bps : int)]
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

let create ~standard_bps ?(caps = []) () =
  match List.find caps ~f:(fun c -> c < 0) with
  | Some cap -> Or_error.error_s [%message "negative spread cap" (cap : int)]
  | None ->
    let applied_bps = List.fold caps ~init:standard_bps ~f:Int.min in
    validate { standard_bps; applied_bps }
;;

let zero = { standard_bps = 0; applied_bps = 0 }

let cap t ~bps =
  if bps < 0
  then Or_error.error_s [%message "negative spread cap" (bps : int)]
  else Ok { t with applied_bps = Int.min t.applied_bps bps }
;;

let create_spread = create

module Schedule = struct
  type nonrec spread = t

  type t =
    { standard_bps : int
    ; tier_caps : int String.Map.t
    }
  [@@deriving sexp, compare, equal]

  let create ~standard_bps ~tier_caps =
    let%bind.Or_error tier_caps = String.Map.of_alist_or_error tier_caps in
    let%map.Or_error (_ : spread) =
      create_spread ~standard_bps ~caps:(Map.data tier_caps) ()
    in
    { standard_bps; tier_caps }
  ;;

  let spread t ?tier ?cap_bps () =
    let tier_cap = Option.bind tier ~f:(Map.find t.tier_caps) in
    create_spread ~standard_bps:t.standard_bps ~caps:(List.filter_opt [ tier_cap; cap_bps ]) ()
  ;;
end
