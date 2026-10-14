open! Core
open Fx_core
open Helpers

let%expect_test "estimate in a base currency, rounded once" =
  let t = table () in
  let show ?now base holdings =
    let now = Option.value now ~default:(at ()) in
    let v = Valuation.estimate t ~base (List.map holdings ~f:amount) ~now in
    print_s
      [%message
        ""
          ~total:(v.total : Money.Amount.t option)
          ~missing:(v.missing : Money.Currency.t list)
          ~rate_date:(Option.map v.basis ~f:(fun b -> b.rate_date) : Date.t option)]
  in
  show eur [ "10.00 EUR"; "100.00 GBP"; "1000 JPY"; "0.003 KWD" ];
  show gbp [ "0.01 EUR"; "0.01 EUR"; "0.01 EUR" ];
  show eur [ "10.00 EUR"; "5.00 SEK" ];
  show eur [];
  show
    ~now:(Time_ns.add (at ()) (Time_ns.Span.of_day 10.))
    eur
    [ "10.00 EUR"; "1.00 GBP" ];
  [%expect
    {|
    ((total ("132.60 EUR")) (missing ()) (rate_date (2026-10-09)))
    ((total ("0.03 GBP")) (missing ()) (rate_date (2026-10-09)))
    ((total ()) (missing (SEK)) (rate_date ()))
    ((total ("0.00 EUR")) (missing ()) (rate_date ()))
    ((total ()) (missing (GBP)) (rate_date ()))
    |}]
;;

let%expect_test "thresholds at mid; no rate counts as reaching them" =
  let t = table () in
  let check a threshold =
    printf
      "%s >= %s: %b\n"
      a
      threshold
      (Valuation.at_least t (amount a) ~threshold:(amount threshold) ~now:(at ()))
  in
  check "429.35 GBP" "500.00 EUR";
  check "429.34 GBP" "500.00 EUR";
  check "500.00 EUR" "500.00 EUR";
  check "1.00 SEK" "500.00 EUR";
  [%expect
    {|
    429.35 GBP >= 500.00 EUR: true
    429.34 GBP >= 500.00 EUR: false
    500.00 EUR >= 500.00 EUR: true
    1.00 SEK >= 500.00 EUR: true
    |}]
;;
