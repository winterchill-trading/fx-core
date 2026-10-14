open! Core
open Fx_core
open Helpers

let spread = Or_error.ok_exn (Spread.create ~standard_bps:50 ())

let auth merchant =
  Card_fx.authorise
    (table ())
    ~account_currency:eur
    ~merchant_amount:(amount merchant)
    ~spread
    ~now:(at ())
;;

let show (c : Card_fx.t) =
  printf
    "merchant %s -> account %s (fee %s) at %s\n"
    (Money.Amount.to_string c.merchant_amount)
    (Money.Amount.to_string c.account_amount)
    (Money.Amount.to_string c.fee)
    (Ratio.to_string c.customer_rate)
;;

let%expect_test "authorise, then re-price the final amount at the same rate" =
  let a = ok (auth "50.00 GBP") in
  show a;
  show (ok (Card_fx.reprice a ~final_merchant_amount:(amount "57.50 GBP")));
  show (ok (Card_fx.reprice a ~final_merchant_amount:(amount "50.00 GBP")));
  show (ok (auth "1999 JPY"));
  print_refusal (auth "10.00 EUR");
  print_refusal (Card_fx.reprice a ~final_merchant_amount:(amount "1.00 USD"));
  [%expect
    {|
    merchant 50.00 GBP -> account 58.53 EUR (fee 0.29 EUR) at 0.8544021739
    merchant 57.50 GBP -> account 67.30 EUR (fee 0.34 EUR) at 0.8544021739
    merchant 50.00 GBP -> account 58.53 EUR (fee 0.29 EUR) at 0.8544021739
    merchant 1999 JPY -> account 12.33 EUR (fee 0.06 EUR) at 162.2282608
    (same_currency (Same_currency EUR))
    (currency_mismatch (Currency_mismatch (expected GBP) (got USD)))
    |}]
;;

let%expect_test "refunds return the refunded share of what was paid, rounded down" =
  let paid = amount "58.53 EUR" in
  let settled = amount "50.00 GBP" in
  List.iter
    [ "50.00 GBP"; "25.00 GBP"; "0.01 GBP"; "50.01 GBP"; "0.00 GBP"; "1.00 EUR" ]
    ~f:(fun refund ->
      match
        Card_fx.refund_share
          ~paid
          ~settled_merchant:settled
          ~refund_merchant:(amount refund)
      with
      | Ok r -> printf "%s -> %s\n" refund (Money.Amount.to_string r)
      | Error _ as e -> print_refusal e);
  [%expect
    {|
    50.00 GBP -> 58.53 EUR
    25.00 GBP -> 29.26 EUR
    0.01 GBP -> 0.01 EUR
    (amount_too_large (Amount_too_large "50.01 GBP"))
    (amount_not_positive (Amount_not_positive "0.00 GBP"))
    (currency_mismatch (Currency_mismatch (expected GBP) (got EUR)))
    |}]
;;

let%test_unit "partial refunds never add up to more than was paid" =
  let gen =
    let open Quickcheck.Generator.Let_syntax in
    let%bind paid = Int.gen_incl 1 1_000_000 in
    let%bind settled = Int.gen_incl 1 1_000_000 in
    let%map cuts = List.gen_with_length 4 (Int.gen_incl 0 settled) in
    paid, settled, cuts
  in
  Quickcheck.test gen ~f:(fun (paid, settled, cuts) ->
    (* Split the settled amount into consecutive refunds at the cut points. *)
    let points = List.sort (0 :: settled :: cuts) ~compare:Int.compare in
    let parts =
      List.zip_exn (List.drop_last_exn points) (List.tl_exn points)
      |> List.filter_map ~f:(fun (a, b) -> if b > a then Some (b - a) else None)
    in
    let refunded =
      List.sum (module Int) parts ~f:(fun part ->
        Card_fx.refund_share
          ~paid:(Money.Amount.of_minor_units_int eur paid)
          ~settled_merchant:(Money.Amount.of_minor_units_int gbp settled)
          ~refund_merchant:(Money.Amount.of_minor_units_int gbp part)
        |> ok
        |> Money.Amount.minor_units_int
        |> Option.value_exn)
    in
    assert (refunded <= paid))
;;
