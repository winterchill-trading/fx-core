(* Command-line front end: prices conversions from simulated or bundled rates. *)

open! Core
open! Async
open Fx_core
module Currency = Money.Currency

let usd = Currency.usd

let now_flag =
  let%map_open.Command now =
    flag
      "-now"
      (optional string)
      ~doc:"TIME request time, e.g. 2026-10-09T12:00:00Z (default: the current time)"
  in
  match now with
  | None -> Time_ns.now ()
  | Some s -> Time_ns.of_string_with_utc_offset s
;;

let bundled_flag =
  Command.Param.flag
    "-bundled"
    (Command.Param.optional Command.Param.string)
    ~doc:"FILE use a bundled CSV table (offline mode) instead of the simulated source"
;;

(* The table and the freshness policy: a bundled file means offline mode, where old
   rates are still used and shown as stale. *)
let load ~bundled ~now =
  match bundled with
  | Some path ->
    let%bind text = Reader.file_contents path in
    return
      (let%bind.Or_error obs = Bundled.parse ~pivot:usd ~source:"bundled" text in
       let%map.Or_error table = Rate_table.add_all (Rate_table.create ~pivot:usd) obs in
       table, Freshness.Policy.offline)
  | None ->
    let source =
      Simulated_source.create
        ~pivot:usd
        ~seeds:(Simulated_source.usd_seeds ())
        ~time_source:(Time_source.create ~now ())
        ()
      |> Or_error.ok_exn
    in
    let%map table, attempt =
      Refresh.fetch (Simulated_source.pack source) (Rate_table.create ~pivot:usd) ~now
    in
    (match attempt.outcome with
     | Succeeded _ -> Ok (table, Freshness.Policy.default)
     | Failed msg -> Or_error.error_string msg)
;;

let rates_command =
  Command.async_or_error
    ~summary:"Print the rate of every currency per USD on the day of the request"
    (let%map_open.Command now = now_flag
     and bundled = bundled_flag in
     fun () ->
       let%map.Deferred.Or_error table, _ = load ~bundled ~now in
       let as_of = Time_ns.to_date now ~zone:Time_float.Zone.utc in
       List.iter (Rate_table.currencies table) ~f:(fun c ->
         Option.iter (Rate_table.lookup table c ~as_of) ~f:(fun o ->
           printf
             "%-4s %-14s %s %s\n"
             (Currency.to_string c)
             (Ratio.to_string o.per_pivot)
             (Date.to_string o.date)
             (Origin.to_string o.origin))))
;;

let quote_command =
  Command.async_or_error
    ~summary:"Price a conversion: quote SELL-CURRENCY BUY-CURRENCY (-sell X | -buy X)"
    (let%map_open.Command now = now_flag
     and bundled = bundled_flag
     and sell = anon ("SELL-CURRENCY" %: string)
     and buy = anon ("BUY-CURRENCY" %: string)
     and sell_amount = flag "-sell" (optional string) ~doc:"AMOUNT amount to sell"
     and buy_amount = flag "-buy" (optional string) ~doc:"AMOUNT amount to buy"
     and spread_bps =
       flag "-spread" (optional_with_default 50 int) ~doc:"BPS standard spread (default 50)"
     and caps = flag "-cap" (listed int) ~doc:"BPS cap on the spread (repeatable)" in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let%bind table, freshness = load ~bundled ~now in
       let%bind sell = Deferred.return (Currency.of_string_or_error sell) in
       let%bind buy = Deferred.return (Currency.of_string_or_error buy) in
       let%bind request =
         Deferred.return
           (match sell_amount, buy_amount with
            | Some s, None ->
              Or_error.map (Money.Amount.of_decimal_string sell s) ~f:(fun a ->
                Pricing.Request.Sell a)
            | None, Some b ->
              Or_error.map (Money.Amount.of_decimal_string buy b) ~f:(fun a ->
                Pricing.Request.Buy a)
            | _ -> Or_error.error_string "give exactly one of -sell and -buy")
       in
       let%bind spread = Deferred.return (Spread.create ~standard_bps:spread_bps ~caps ()) in
       let%map q =
         Quote.create
           ~config:{ Quote.Config.default with freshness }
           table
           ~id:(Quote.Id.of_string "cli")
           ~sell
           ~buy
           ~spread
           request
           ~now
         |> Result.map_error ~f:Refusal.to_error
         |> Deferred.return
       in
       print_s [%sexp (q : Quote.t)])
;;

let bundle_command =
  Command.async_or_error
    ~summary:"Write simulated history as a bundled CSV table to stdout"
    (let%map_open.Command from = flag "-from" (required date) ~doc:"DATE first date"
     and to_ = flag "-to" (required date) ~doc:"DATE last date" in
     fun () ->
       let now = Time_ns.of_date_ofday ~zone:Time_float.Zone.utc (Date.add_days to_ 1) Time_ns.Ofday.start_of_day in
       let source =
         Simulated_source.create
           ~pivot:usd
           ~seeds:(Simulated_source.usd_seeds ())
           ~time_source:(Time_source.create ~now ())
           ()
         |> Or_error.ok_exn
       in
       let%map.Deferred.Or_error obs =
         Simulated_source.history
           source
           ~currencies:(List.map (Simulated_source.usd_seeds ()) ~f:fst)
           ~from
           ~to_
       in
       print_string (Bundled.to_csv obs))
;;

let () =
  Command.group
    ~summary:"Reference rates, cross rates and retail FX quotes"
    [ "rates", rates_command; "quote", quote_command; "bundle", bundle_command ]
  |> Command_unix.run
;;
