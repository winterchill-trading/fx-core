open! Core
open Fx_core
open Helpers

let spread ?caps bps = Or_error.ok_exn (Spread.create ~standard_bps:bps ?caps ())
let mid sell buy = ok (Rate_table.mid (table ()) ~sell ~buy ~as_of:friday)

let show ?(spread = spread 50) ?max_minor_units sell buy request =
  match Pricing.price ?max_minor_units ~mid:(mid sell buy) ~spread request with
  | Error _ as r -> print_refusal r
  | Ok (p : Pricing.t) ->
    printf
      "%s: sell %s buy %s fee %s | mid %s customer %s inverse %s spread %d/%d\n"
      (Pricing.Fixed_side.to_string p.fixed_side)
      (Money.Amount.to_string p.amounts.sell)
      (Money.Amount.to_string p.amounts.buy)
      (Money.Amount.to_string p.amounts.fee)
      (Ratio.to_string p.mid.rate)
      (Ratio.to_string p.customer_rate)
      (Ratio.to_string p.inverse_customer_rate)
      p.spread.applied_bps
      p.spread.standard_bps
;;

let%expect_test "sell fixed rounds the bought amount down, buy fixed the sold amount up" =
  show eur gbp (Sell (amount "100.00 EUR"));
  show eur gbp (Buy (amount "100.00 GBP"));
  show eur jpy (Sell (amount "10.00 EUR"));
  show jpy eur (Sell (amount "1000 JPY"));
  show usd kwd (Buy (amount "1.000 KWD"));
  [%expect
    {|
    sell: sell 100.00 EUR buy 85.44 GBP fee 0.50 EUR | mid 0.85869565217391304348 customer 0.8544021739 inverse 1.170409007 spread 50/50
    buy: sell 117.05 EUR buy 100.00 GBP fee 0.59 EUR | mid 0.85869565217391304348 customer 0.8544021739 inverse 1.170409007 spread 50/50
    sell: sell 10.00 EUR buy 1622 JPY fee 0.05 EUR | mid 163.04347826086956522 customer 162.2282608 inverse 0.006164154106 spread 50/50
    sell: sell 1000 JPY buy 6.10 EUR fee 5 JPY | mid 0.0061333333333333333333 customer 0.006102666666 inverse 163.8627922 spread 50/50
    buy: sell 3.28 USD buy 1.000 KWD fee 0.02 USD | mid 0.307 customer 0.305465 inverse 3.273697478 spread 50/50
    |}]
;;

let%expect_test "caps lower the spread, never raise it" =
  show ~spread:(spread ~caps:[ 35 ] 50) eur gbp (Sell (amount "100.00 EUR"));
  show ~spread:(spread ~caps:[ 80; 20 ] 50) eur gbp (Sell (amount "100.00 EUR"));
  show ~spread:(spread ~caps:[ 80 ] 50) eur gbp (Sell (amount "100.00 EUR"));
  show ~spread:Spread.zero eur gbp (Sell (amount "100.00 EUR"));
  [%expect
    {|
    sell: sell 100.00 EUR buy 85.56 GBP fee 0.35 EUR | mid 0.85869565217391304348 customer 0.8556902173 inverse 1.168647227 spread 35/50
    sell: sell 100.00 EUR buy 85.69 GBP fee 0.20 EUR | mid 0.85869565217391304348 customer 0.8569782608 inverse 1.166890744 spread 20/50
    sell: sell 100.00 EUR buy 85.44 GBP fee 0.50 EUR | mid 0.85869565217391304348 customer 0.8544021739 inverse 1.170409007 spread 50/50
    sell: sell 100.00 EUR buy 85.86 GBP fee 0.00 EUR | mid 0.85869565217391304348 customer 0.8586956521 inverse 1.164556962 spread 0/0
    |}]
;;

let%expect_test "refusals" =
  (* One yen buys less than a cent. *)
  show jpy usd (Sell (amount "1 JPY"));
  show eur gbp (Sell (amount "0.00 EUR"));
  show eur gbp (Sell (amount "-1.00 EUR"));
  show eur gbp (Sell (amount "1.00 GBP"));
  show eur gbp (Buy (amount "1.00 EUR"));
  show ~max_minor_units:(Z.of_int 100_000) eur gbp (Sell (amount "1000.01 EUR"));
  show ~max_minor_units:(Z.of_int 100_000) eur gbp (Buy (amount "900.00 GBP"));
  [%expect
    {|
    (amount_too_small (Amount_too_small "1 JPY"))
    (amount_not_positive (Amount_not_positive "0.00 EUR"))
    (amount_not_positive (Amount_not_positive "-1.00 EUR"))
    (currency_mismatch (Currency_mismatch (expected EUR) (got GBP)))
    (currency_mismatch (Currency_mismatch (expected GBP) (got EUR)))
    (amount_too_large (Amount_too_large "1000.01 EUR"))
    (amount_too_large (Amount_too_large "900.00 GBP"))
    |}]
;;

let%expect_test "spread schedule by tier" =
  let schedule =
    Spread.Schedule.create ~standard_bps:50 ~tier_caps:[ "plus", 35; "premium", 20 ]
    |> Or_error.ok_exn
  in
  List.iter
    [ None, None
    ; Some "plus", None
    ; Some "premium", None
    ; Some "unknown", None
    ; Some "plus", Some 25
    ; None, Some 60
    ]
    ~f:(fun (tier, cap_bps) ->
      let s = Spread.Schedule.spread schedule ?tier ?cap_bps () |> Or_error.ok_exn in
      print_s
        [%message "" (tier : string option) (cap_bps : int option) ~_:(s : Spread.t)]);
  print_s [%sexp (Spread.create ~standard_bps:1001 () : Spread.t Or_error.t)];
  print_s [%sexp (Spread.create ~standard_bps:50 ~caps:[ -1 ] () : Spread.t Or_error.t)];
  [%expect
    {|
    ((tier ()) (cap_bps ()) ((standard_bps 50) (applied_bps 50)))
    ((tier (plus)) (cap_bps ()) ((standard_bps 50) (applied_bps 35)))
    ((tier (premium)) (cap_bps ()) ((standard_bps 50) (applied_bps 20)))
    ((tier (unknown)) (cap_bps ()) ((standard_bps 50) (applied_bps 50)))
    ((tier (plus)) (cap_bps (25)) ((standard_bps 50) (applied_bps 25)))
    ((tier ()) (cap_bps (60)) ((standard_bps 50) (applied_bps 50)))
    (Error ("spread out of range" (standard_bps 1001)))
    (Error ("negative spread cap" (cap -1)))
    |}]
;;

(* Properties over every pair of the test table, amounts up to ten million major units and
   spreads up to the maximum. *)
let gen =
  let currencies = Rate_table.currencies (table ()) in
  let open Quickcheck.Generator.Let_syntax in
  let%bind sell = Quickcheck.Generator.of_list currencies in
  let%bind buy =
    Quickcheck.Generator.filter (Quickcheck.Generator.of_list currencies) ~f:(fun c ->
      not (Money.Currency.equal c sell))
  in
  let%bind minor = Int.gen_log_uniform_incl 1 1_000_000_000_000 in
  let%bind bps = Int.gen_incl 0 Spread.max_bps in
  let%map side = Quickcheck.Generator.of_list Pricing.Fixed_side.all in
  sell, buy, minor, bps, side
;;

let one_minor currency = Money.Amount.to_q (Money.Amount.of_minor_units_int currency 1)

let%test_unit "rounding never favours the customer, and costs at most one minor unit" =
  Quickcheck.test gen ~trials:5_000 ~f:(fun (sell, buy, minor, bps, side) ->
    let m = mid sell buy in
    let request : Pricing.Request.t =
      match side with
      | Sell -> Sell (Money.Amount.of_minor_units_int sell minor)
      | Buy -> Buy (Money.Amount.of_minor_units_int buy minor)
    in
    match Pricing.price ~mid:m ~spread:(spread bps) request with
    | Error (Amount_too_small _ | Amount_too_large _) -> ()
    | Error r -> raise_s [%sexp (r : Refusal.t)]
    | Ok p ->
      let s = Money.Amount.to_q p.amounts.sell in
      let b = Money.Amount.to_q p.amounts.buy in
      let worth = Q.mul s p.customer_rate in
      assert (Q.leq p.customer_rate m.rate);
      assert (Q.leq b worth);
      (match side with
       | Sell -> assert (Q.lt worth (Q.add b (one_minor buy)))
       | Buy -> assert (Q.lt (Q.mul (Q.sub s (one_minor sell)) p.customer_rate) b));
      assert (Money.Amount.( <= ) p.amounts.fee p.amounts.sell);
      assert (Money.Amount.is_positive p.amounts.buy))
;;

let%test_unit "a lower spread never gives the customer less" =
  Quickcheck.test gen ~trials:2_000 ~f:(fun (sell, buy, minor, bps, side) ->
    let m = mid sell buy in
    let request : Pricing.Request.t =
      match side with
      | Sell -> Sell (Money.Amount.of_minor_units_int sell minor)
      | Buy -> Buy (Money.Amount.of_minor_units_int buy minor)
    in
    let price bps = Pricing.price ~mid:m ~spread:(spread bps) request in
    match price bps, price (bps / 2) with
    | Ok high, Ok low ->
      (match side with
       | Sell -> assert (Money.Amount.( >= ) low.amounts.buy high.amounts.buy)
       | Buy -> assert (Money.Amount.( <= ) low.amounts.sell high.amounts.sell))
    | _ -> ())
;;

let%expect_test "display inverse digits are configurable" =
  let mid = mid eur gbp in
  List.iter [ 4; 6; 10; 14 ] ~f:(fun digits ->
    let p =
      Pricing.price
        ~inverse_digits:digits
        ~mid
        ~spread:(spread 50)
        (Sell (amount "100.00 EUR"))
      |> Result.ok
      |> Option.value_exn
    in
    printf
      "%2d: customer %s inverse %s mid inverse %s buy %s\n"
      digits
      (Ratio.to_string p.customer_rate)
      (Ratio.to_string p.inverse_customer_rate)
      (Ratio.to_string (Rate_table.Mid.inverse_rate ~digits mid))
      (Money.Amount.to_string p.amounts.buy));
  print_s
    [%sexp
      (Ratio.equal
         (Pricing.inverse_customer_rate (Q.of_string "4/3"))
         (Pricing.inverse_customer_rate
            ~digits:Pricing.customer_digits
            (Q.of_string "4/3"))
       : bool)];
  [%expect
    {|
     4: customer 0.8544021739 inverse 1.17 mid inverse 1.165 buy 85.44 GBP
     6: customer 0.8544021739 inverse 1.17041 mid inverse 1.16456 buy 85.44 GBP
    10: customer 0.8544021739 inverse 1.170409007 mid inverse 1.164556962 buy 85.44 GBP
    14: customer 0.8544021739 inverse 1.1704090070785 mid inverse 1.1645569620253 buy 85.44 GBP
    true
    |}]
;;

let%test_unit "inverse digits never change amounts or the customer rate" =
  Quickcheck.test
    (Quickcheck.Generator.both (Int.gen_incl 1 30) (Int.gen_incl 1 1_000_000))
    ~f:(fun (digits, cents) ->
      let request : Pricing.Request.t =
        Sell (Money.Amount.of_minor_units_int eur cents)
      in
      (* Tiny amounts are refused (nothing on the other side); both calls must agree. *)
      let price ?inverse_digits () =
        Pricing.price ?inverse_digits ~mid:(mid eur gbp) ~spread:(spread 50) request
        |> Result.ok
        |> Option.map ~f:(fun (p : Pricing.t) -> p.amounts, p.customer_rate)
      in
      [%test_result: (Pricing.Amounts.t * Ratio.t) option]
        (price ~inverse_digits:digits ())
        ~expect:(price ()))
;;
