open! Core

module Policy = struct
  type t =
    { stale_after : Time_ns.Span.t
    ; max_age : Time_ns.Span.t option
    }
  [@@deriving sexp, compare, equal]

  let default =
    { stale_after = Time_ns.Span.of_hr 3.; max_age = Some (Time_ns.Span.of_day 7.) }
  ;;

  let offline = { default with max_age = None }
end

type t =
  { age : Time_ns.Span.t
  ; stale : bool
  ; too_old : bool
  }
[@@deriving sexp_of, compare, equal]

let assess (policy : Policy.t) (basis : Basis.t) ~now =
  let age = Basis.age basis ~now in
  let too_old =
    match policy.max_age with
    | None -> false
    | Some max_age ->
      let today = Time_ns.to_date now ~zone:Time_float.Zone.utc in
      let date_age = Time_ns.Span.of_day (Float.of_int (Date.diff today basis.rate_date)) in
      Time_ns.Span.( > ) date_age max_age || Time_ns.Span.( > ) age max_age
  in
  { age; stale = Time_ns.Span.( > ) age policy.stale_after; too_old }
;;

let check policy (basis : Basis.t) ~now =
  if (assess policy basis ~now).too_old
  then Error (Refusal.Rate_too_old { rate_date = basis.rate_date; fetched_at = basis.fetched_at })
  else Ok ()
;;
