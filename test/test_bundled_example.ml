open! Core
open Fx_core

(* The example file shipped in examples/, so its documented shape stays parseable. *)
let csv = In_channel.read_all "../examples/bundled-rates.csv"
let usd = Money.Currency.usd

let%expect_test "the example file parses leniently and reports its unknown code" =
  let observations, unknown =
    Bundled.parse_lenient ~pivot:usd ~source:"example" csv |> Or_error.ok_exn
  in
  List.iter observations ~f:(fun (o : Observation.t) ->
    print_s
      [%message
        ""
          ~date:(o.date : Date.t)
          ~currency:(Money.Currency.to_string o.currency)
          ~rate:(Ratio.to_string o.per_pivot)
          ~fetched_at:(o.fetched_at : Time_ns.Alternate_sexp.t)]);
  print_s [%sexp (unknown : Bundled.Unknown_currency.t list)];
  [%expect
    {|
    ((date 2026-10-08) (currency EUR) (rate 0.9187)
     (fetched_at "2026-10-08 16:05:00Z"))
    ((date 2026-10-08) (currency GBP) (rate 0.7652)
     (fetched_at "2026-10-08 16:05:00Z"))
    ((date 2026-10-08) (currency JPY) (rate 149.82)
     (fetched_at "2026-10-08 00:00:00Z"))
    ((date 2026-10-09) (currency EUR) (rate 0.9201)
     (fetched_at "2026-10-09 16:00:00Z"))
    ((date 2026-10-09) (currency GBP) (rate 0.766)
     (fetched_at "2026-10-09 00:00:00Z"))
    ((date 2026-10-09) (currency JPY) (rate 150.07)
     (fetched_at "2026-10-09 00:00:00Z"))
    (((line 22) (currency NGN)))
    |}]
;;

let%expect_test "the strict parse refuses the same file" =
  print_s
    [%sexp
      (Bundled.parse ~pivot:usd ~source:"example" csv |> Result.map ~f:List.length
       : int Or_error.t)];
  [%expect {| (Error (("bundled rates" (line 22)) ("unknown currency" NGN))) |}]
;;

let%expect_test "on_unknown_currency sees each skipped row; other errors still fail" =
  let seen = ref [] in
  let parse text =
    Bundled.parse
      ~on_unknown_currency:(fun u -> seen := u :: !seen)
      ~pivot:usd
      ~source:"b"
      text
    |> Result.map ~f:List.length
  in
  print_s [%sexp (parse csv : int Or_error.t)];
  print_s [%sexp (List.rev !seen : Bundled.Unknown_currency.t list)];
  print_s
    [%sexp
      (parse "date,currency,rate\n2026-10-08,NGN,-1\n2026-10-08,USD,1\n" : int Or_error.t)];
  [%expect
    {|
    (Ok 6)
    (((line 22) (currency NGN)))
    (Error
     ((("bundled rates" (line 2)) ("rate: malformed price" -1))
      (("bundled rates" (line 3))
       ("observation: currency is the pivot" (currency USD)))))
    |}]
;;
