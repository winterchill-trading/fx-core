open! Core
open Fx_core
open Helpers

let%expect_test "rounding to significant digits" =
  List.iter
    [ "2/3", Money.Rounding.Down, 3
    ; "2/3", Up, 3
    ; "2/3", Half_even, 10
    ; "150", Down, 2
    ; "0.000123456", Half_even, 3
    ; "1234567.891", Down, 4
    ; "0.0025", Half_even, 1
    ; "0.0035", Half_even, 1
    ]
    ~f:(fun (q, mode, digits) ->
      printf
        "%-12s %-9s %2d -> %s\n"
        q
        (Money.Rounding.to_string mode)
        digits
        (Ratio.to_string (Ratio.round_sig mode ~digits (ratio q))));
  [%expect
    {|
    2/3          down       3 -> 0.666
    2/3          up         3 -> 0.667
    2/3          half_even 10 -> 0.6666666667
    150          down       2 -> 150
    0.000123456  half_even  3 -> 0.000123
    1234567.891  down       4 -> 1234000
    0.0025       half_even  1 -> 0.002
    0.0035       half_even  1 -> 0.004
    |}]
;;

let positive_q =
  Quickcheck.Generator.map2
    (Int.gen_incl 1 1_000_000_000)
    (Int.gen_incl 1 1_000_000_000)
    ~f:(fun n d -> Q.of_ints n d)
;;

let%test_unit "down never rounds up, up never down, and both stay within one unit in \
               the last digit"
  =
  Quickcheck.test
    (Quickcheck.Generator.tuple2 positive_q (Int.gen_incl 1 20))
    ~f:(fun (q, digits) ->
      let down = Ratio.round_sig Down ~digits q in
      let up = Ratio.round_sig Up ~digits q in
      assert (Q.leq down q && Q.geq up q);
      (* Relative step of the last kept digit is at most 10^(1 - digits). *)
      assert (Q.leq (Q.sub up down) (Q.mul q (Ratio.pow10 (1 - digits)))))
;;

let%test_unit "text form round trips" =
  Quickcheck.test positive_q ~f:(fun q ->
    [%test_result: Ratio.t] (ratio (Ratio.to_string q)) ~expect:q)
;;
