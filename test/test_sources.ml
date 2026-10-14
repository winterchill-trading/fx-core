open! Core
open Fx_core
open Helpers
module Time_source = Async_kernel.Time_source

let run f = Async.Thread_safe.block_on_async_exn f

let simulated ?(now = at ()) () =
  let time_source = Time_source.create ~now () in
  let source =
    Simulated_source.create
      ~pivot:usd
      ~seeds:(Simulated_source.usd_seeds ())
      ~time_source
      ()
    |> Or_error.ok_exn
  in
  time_source, source
;;

let%expect_test "simulated rates depend only on currency and date" =
  let _, a = simulated () in
  let _, b = simulated ~now:(Time_ns.add (at ()) (Time_ns.Span.of_day 30.)) () in
  List.iter [ eur; gbp; jpy; chf ] ~f:(fun c ->
    let r s d = Option.value_map (Simulated_source.rate s c d) ~default:"-" ~f:Ratio.to_string in
    printf
      "%s fri %s sat %s same-on-other-source %b\n"
      (Money.Currency.to_string c)
      (r a friday)
      (r a (Date.add_days friday 1))
      (String.equal (r a friday) (r b friday)));
  print_s [%sexp (Simulated_source.rate a kwd friday : Ratio.t option)];
  [%expect
    {|
    EUR fri 0.922024 sat 0.922024 same-on-other-source true
    GBP fri 0.790474 sat 0.790474 same-on-other-source true
    JPY fri 149.925 sat 149.925 same-on-other-source true
    CHF fri 0.88 sat 0.88 same-on-other-source true
    ()
    |}]
;;

let%test_unit "simulated rates stay within the volatility band of the seed" =
  let _, s = simulated () in
  Quickcheck.test
    (Quickcheck.Generator.tuple2
       (Quickcheck.Generator.of_list (Simulated_source.usd_seeds ()))
       (Int.gen_incl 0 3650))
    ~f:(fun ((currency, seed), days) ->
      let r = Option.value_exn (Simulated_source.rate s currency (Date.add_days friday days)) in
      let band = Q.mul seed (Q.of_ints 51 10_000) in
      assert (Q.leq (Q.abs (Q.sub r seed)) band))
;;

let%expect_test "refresh merges the latest rates and tracks the source status" =
  let time_source, source = simulated () in
  let packed = Simulated_source.pack source in
  let policy = Refresh.Policy.default in
  let status = ref Refresh.Status.initial in
  let table = ref (Rate_table.create ~pivot:usd) in
  let step () =
    let now = Time_source.now time_source in
    let t, attempt = run (fun () -> Refresh.fetch packed !table ~now) in
    table := t;
    status := Refresh.Status.apply !status attempt;
    print_s
      [%message
        ""
          ~outcome:(attempt.outcome : Refresh.Attempt.outcome)
          ~rows:(Rate_table.length !table : int)
          ~next:(Refresh.next_attempt_at policy !status ~now : Time_ns.Alternate_sexp.t)
          ~stale:(Refresh.Status.stale !status Freshness.Policy.default ~now : bool)]
  in
  print_s [%message (Rate_source.name packed) (Rate_source.attribution packed)];
  step ();
  Simulated_source.set_reachable source false;
  Time_source.advance_directly time_source ~to_:(at ~sec:3600 ());
  step ();
  (* The table keeps its rates through a failure; staleness comes from the last success. *)
  Time_source.advance_directly time_source ~to_:(at ~sec:(4 * 3600) ());
  step ();
  Simulated_source.set_reachable source true;
  (* Saturday: the newest publication is still Friday's. *)
  Time_source.advance_directly time_source ~to_:(at ~sec:(86_400 + 3600) ());
  step ();
  print_s [%sexp (!status : Refresh.Status.t)];
  [%expect
    {|
    (simulated "Simulated reference rates (simulated)")
    ((outcome (Succeeded (observations 9) (latest_rate_date (2026-10-09))))
     (rows 9) (next "2026-10-09 13:00:00Z") (stale false))
    ((outcome (Failed "(\"rate source unreachable\" (source simulated))"))
     (rows 9) (next "2026-10-09 13:05:00Z") (stale false))
    ((outcome (Failed "(\"rate source unreachable\" (source simulated))"))
     (rows 9) (next "2026-10-09 16:05:00Z") (stale true))
    ((outcome (Succeeded (observations 9) (latest_rate_date (2026-10-09))))
     (rows 9) (next "2026-10-10 14:00:00Z") (stale false))
    ((last_attempt_at ("2026-10-10 13:00:00Z"))
     (last_success_at ("2026-10-10 13:00:00Z")) (latest_rate_date (2026-10-09))
     (reachable true))
    |}]
;;

let%expect_test "history skips weekends and stops at today" =
  let _, source = simulated () in
  let obs =
    run (fun () ->
      Simulated_source.history
        source
        ~currencies:[ eur ]
        ~from:(Date.add_days friday (-7))
        ~to_:(Date.add_days friday 7))
    |> ok_exn
  in
  List.iter obs ~f:(fun o -> printf "%s %s\n" (Date.to_string o.date) (Ratio.to_string o.per_pivot));
  [%expect
    {|
    2026-10-02 0.92368
    2026-10-05 0.924048
    2026-10-06 0.918804
    2026-10-07 0.91724
    2026-10-08 0.920552
    2026-10-09 0.922024
    |}]
;;

let%expect_test "bundled tables round trip and report bad lines" =
  let csv =
    {|# rates per USD
date,currency,rate
2026-10-08,EUR,0.9187
2026-10-08,JPY,149.82

2026-10-09,EUR,0.92
|}
  in
  let obs = Bundled.parse ~pivot:usd ~source:"bundled-test" csv |> Or_error.ok_exn in
  print_s [%sexp (List.hd_exn obs : Observation.t)];
  print_string (Bundled.to_csv obs);
  let again = Bundled.parse ~pivot:usd ~source:"bundled-test" (Bundled.to_csv obs) |> Or_error.ok_exn in
  (* The input is already in date, currency order, so the round trip is exact. *)
  print_s [%sexp (List.equal Observation.equal again obs : bool)];
  let bad = "date,currency,rate\n2026-10-08,EUR,0.9\n2026-10-08,XXX,1\n2026-10-08,USD,1\n2026-10-08,GBP,-1\nnonsense\n" in
  print_s [%sexp (Bundled.parse ~pivot:usd ~source:"b" bad |> Result.map ~f:List.length : int Or_error.t)];
  [%expect
    {|
    ((pivot USD) (currency EUR) (date 2026-10-08) (per_pivot 0.9187)
     (origin Bundled) (source bundled-test) (fetched_at "2026-10-08 00:00:00Z"))
    date,currency,rate
    2026-10-08,EUR,0.9187
    2026-10-08,JPY,149.82
    2026-10-09,EUR,0.92
    true
    (Error
     ((("bundled rates" (line 3)) ("unknown currency" XXX))
      (("bundled rates" (line 4))
       ("observation: currency is the pivot" (currency USD)))
      (("bundled rates" (line 5)) ("rate: malformed price" -1))
      (("bundled rates" (line 6)) "expected three fields: date,currency,rate")))
    |}]
;;
