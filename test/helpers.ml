open! Core
open Fx_core

let usd = Money.Currency.usd
let eur = Money.Currency.eur
let gbp = Money.Currency.gbp
let jpy = Money.Currency.jpy
let chf = Money.Currency.chf
let kwd = Money.Currency.of_string "KWD"
let amount = Money.Amount.of_string
let ratio s = Or_error.ok_exn (Ratio.of_string_or_error s)
let friday = Date.of_string "2026-10-09"

let at ?(sec = 0) () =
  Time_ns.add
    (Time_ns.of_string_with_utc_offset "2026-10-09 12:00:00Z")
    (Time_ns.Span.of_int_sec sec)
;;

let obs ?(origin = Origin.Live) ?(date = friday) ?fetched_at currency rate =
  let fetched_at = Option.value_or_thunk fetched_at ~default:(fun () -> at ()) in
  Observation.create
    ~pivot:usd
    ~currency
    ~date
    ~per_pivot:(ratio rate)
    ~origin
    ~source:"test"
    ~fetched_at
  |> Or_error.ok_exn
;;

let table () =
  Rate_table.add_all
    (Rate_table.create ~pivot:usd)
    [ obs eur "0.92"; obs gbp "0.79"; obs jpy "150"; obs chf "0.88"; obs kwd "0.307" ]
  |> Or_error.ok_exn
;;

let ok = function
  | Ok x -> x
  | Error r -> raise_s [%sexp (r : Refusal.t)]
;;

let print_refusal = function
  | Ok _ -> print_endline "ok"
  | Error r -> print_s [%message (Refusal.code r) ~_:(r : Refusal.t)]
;;
