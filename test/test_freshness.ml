open! Core
open Fx_core
open Helpers

let basis ?(rate_date = friday) ?(origin = Origin.Live) fetched_at =
  { Basis.source = "test"; origin; rate_date; fetched_at }
;;

let%expect_test "stale after three hours, refused after seven days" =
  let show policy b ~now =
    let f = Freshness.assess policy b ~now in
    printf
      "age=%ds stale=%b too_old=%b\n"
      (Time_ns.Span.to_int_sec f.age)
      f.stale
      f.too_old
  in
  let p = Freshness.Policy.default in
  let fetched = at () in
  show p (basis fetched) ~now:(at ~sec:(3 * 3600) ());
  show p (basis fetched) ~now:(at ~sec:((3 * 3600) + 1) ());
  (* Rate date seven days back is still accepted; eight is not, even when fetched now. *)
  show p (basis ~rate_date:(Date.add_days friday (-7)) fetched) ~now:fetched;
  show p (basis ~rate_date:(Date.add_days friday (-8)) fetched) ~now:fetched;
  (* A copy fetched more than seven days ago is refused whatever its date says. *)
  show p (basis fetched) ~now:(Time_ns.add fetched (Time_ns.Span.of_day 7.5));
  (* A clock behind the fetch never gives a negative age. *)
  show p (basis fetched) ~now:(at ~sec:(-60) ());
  [%expect
    {|
    age=10800s stale=false too_old=false
    age=10801s stale=true too_old=false
    age=0s stale=false too_old=false
    age=0s stale=false too_old=true
    age=648000s stale=true too_old=true
    age=0s stale=false too_old=false
    |}]
;;

let%expect_test "offline mode never refuses on age" =
  let old = basis ~origin:Bundled ~rate_date:(Date.of_string "2026-01-02") (at ()) in
  let now = Time_ns.add (at ()) (Time_ns.Span.of_day 300.) in
  print_s
    [%message
      ""
        ~default:
          (Freshness.check Freshness.Policy.default old ~now : (unit, Refusal.t) Result.t)
        ~offline:
          (Freshness.check Freshness.Policy.offline old ~now : (unit, Refusal.t) Result.t)
        ~offline_stale:((Freshness.assess Freshness.Policy.offline old ~now).stale : bool)];
  [%expect
    {|
    ((default
      (Error
       (Rate_too_old (rate_date 2026-01-02) (fetched_at "2026-10-09 12:00:00Z"))))
     (offline (Ok ())) (offline_stale true))
    |}]
;;
