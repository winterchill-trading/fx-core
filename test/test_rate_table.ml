open! Core
open Fx_core
open Helpers

let print_mid r =
  match r with
  | Error _ -> print_refusal r
  | Ok (m : Rate_table.Mid.t) ->
    print_s
      [%message
        ""
          ~rate:(Ratio.to_string m.rate)
          ~inverse:(Ratio.to_string (Rate_table.Mid.inverse_rate m))
          ~origin:(m.basis.origin : Origin.t)
          ~rate_date:(m.basis.rate_date : Date.t)]
;;

let%expect_test "cross rates go through the pivot" =
  let t = table () in
  let mid sell buy = print_mid (Rate_table.mid t ~sell ~buy ~as_of:friday) in
  mid eur gbp;
  mid usd jpy;
  mid jpy usd;
  mid eur kwd;
  [%expect
    {|
    ((rate 0.85869565217391304348) (inverse 1.1645569620253164557) (origin Live)
     (rate_date 2026-10-09))
    ((rate 150) (inverse 0.0066666666666666666667) (origin Live)
     (rate_date 2026-10-09))
    ((rate 0.0066666666666666666667) (inverse 150) (origin Live)
     (rate_date 2026-10-09))
    ((rate 0.33369565217391304348) (inverse 2.996742671009771987) (origin Live)
     (rate_date 2026-10-09))
    |}]
;;

let%expect_test "refusals" =
  let t = table () in
  print_refusal (Rate_table.mid t ~sell:eur ~buy:eur ~as_of:friday);
  print_refusal
    (Rate_table.mid t ~sell:eur ~buy:(Money.Currency.of_string "SEK") ~as_of:friday);
  print_refusal
    (Rate_table.mid
       t
       ~sell:(Money.Currency.of_string "NOK")
       ~buy:(Money.Currency.of_string "SEK")
       ~as_of:friday);
  (* Nothing on or before the day before the first observation. *)
  print_refusal (Rate_table.mid t ~sell:eur ~buy:gbp ~as_of:(Date.add_days friday (-1)));
  [%expect
    {|
    (same_currency (Same_currency EUR))
    (no_rate (No_rate (missing (SEK))))
    (no_rate (No_rate (missing (NOK SEK))))
    (no_rate (No_rate (missing (EUR GBP))))
    |}]
;;

let%expect_test "lookup takes the newest date on or before the day, live before bundled" =
  let monday = Date.add_days friday 3 in
  let t =
    Rate_table.add_all
      (Rate_table.create ~pivot:usd)
      [ obs ~origin:Bundled ~date:(Date.add_days friday (-1)) eur "0.90"
      ; obs ~origin:Bundled eur "0.91"
      ; obs eur "0.92"
      ; obs ~origin:Bundled ~date:monday eur "0.93"
      ]
    |> Or_error.ok_exn
  in
  let show ?selection as_of =
    match Rate_table.lookup ?selection t eur ~as_of with
    | None -> print_endline "none"
    | Some o ->
      printf
        "%s %s %s\n"
        (Date.to_string o.date)
        (Origin.to_string o.origin)
        (Ratio.to_string o.per_pivot)
  in
  show friday;
  show ~selection:Bundled_only friday;
  (* Saturday and Sunday read Friday's rate. *)
  show (Date.add_days friday 2);
  show monday;
  show (Date.add_days friday (-1));
  show (Date.add_days friday (-2));
  printf
    "length %d, latest %s\n"
    (Rate_table.length t)
    (Option.value_map (Rate_table.latest_date t) ~default:"none" ~f:Date.to_string);
  [%expect
    {|
    2026-10-09 live 0.92
    2026-10-09 bundled 0.91
    2026-10-09 live 0.92
    2026-10-12 bundled 0.93
    2026-10-08 bundled 0.9
    none
    length 4, latest 2026-10-12
    |}]
;;

let%expect_test "a cross basis is the weaker of the two legs" =
  let t =
    Rate_table.add_all
      (Rate_table.create ~pivot:usd)
      [ obs eur "0.92"
      ; obs ~origin:Bundled ~date:(Date.add_days friday (-1)) gbp "0.79"
      ; obs ~fetched_at:(at ~sec:(-3600) ()) chf "0.88"
      ]
    |> Or_error.ok_exn
  in
  let basis sell buy =
    let m = ok (Rate_table.mid t ~sell ~buy ~as_of:friday) in
    print_s [%sexp (m.basis : Basis.t)]
  in
  basis eur gbp;
  basis eur chf;
  [%expect
    {|
    ((source test) (origin Bundled) (rate_date 2026-10-08)
     (fetched_at "2026-10-09 12:00:00Z"))
    ((source test) (origin Live) (rate_date 2026-10-09)
     (fetched_at "2026-10-09 11:00:00Z"))
    |}]
;;

let%expect_test "history and cross history" =
  let days = List.init 4 ~f:(fun i -> Date.add_days friday (-i)) in
  let t =
    Rate_table.add_all
      (Rate_table.create ~pivot:usd)
      (List.concat_map days ~f:(fun date ->
         let i = Date.diff friday date in
         [ obs ~date eur (sprintf "0.9%d" i) ]
         @ if i = 1 then [] else [ obs ~date gbp (sprintf "0.7%d" i) ]))
    |> Or_error.ok_exn
  in
  let from = Date.add_days friday (-3) in
  List.iter (Rate_table.history t eur ~from ~to_:friday) ~f:(fun o ->
    printf "%s %s\n" (Date.to_string o.date) (Ratio.to_string o.per_pivot));
  List.iter (Rate_table.cross_history t ~sell:eur ~buy:gbp ~from ~to_:friday) ~f:(fun m ->
    printf "%s %s\n" (Date.to_string m.basis.rate_date) (Ratio.to_string m.rate));
  print_s
    [%sexp
      (List.length (Rate_table.cross_history t ~sell:usd ~buy:eur ~from ~to_:friday)
       : int)];
  [%expect
    {|
    2026-10-06 0.93
    2026-10-07 0.92
    2026-10-08 0.91
    2026-10-09 0.9
    2026-10-06 0.78494623655913978495
    2026-10-07 0.78260869565217391304
    2026-10-09 0.77777777777777777778
    4
    |}]
;;

let%expect_test "an observation with another pivot is rejected" =
  let o =
    Observation.create
      ~pivot:eur
      ~currency:gbp
      ~date:friday
      ~per_pivot:(ratio "0.86")
      ~origin:Live
      ~source:"test"
      ~fetched_at:(at ())
    |> Or_error.ok_exn
  in
  print_s
    [%sexp
      (Rate_table.add (Rate_table.create ~pivot:usd) o |> Result.map ~f:ignore
       : unit Or_error.t)];
  [%expect {| (Error ("observation has another pivot" (table USD) (observation EUR))) |}]
;;

let%test_unit "a cross rate times its inverse cross is one" =
  let t = table () in
  let currencies = Rate_table.currencies t in
  Quickcheck.test
    (Quickcheck.Generator.tuple2
       (Quickcheck.Generator.of_list currencies)
       (Quickcheck.Generator.of_list currencies))
    ~f:(fun (a, b) ->
      if not (Money.Currency.equal a b)
      then (
        let ab = ok (Rate_table.mid t ~sell:a ~buy:b ~as_of:friday) in
        let ba = ok (Rate_table.mid t ~sell:b ~buy:a ~as_of:friday) in
        assert (Q.equal (Q.mul ab.exact ba.exact) Q.one)))
;;
