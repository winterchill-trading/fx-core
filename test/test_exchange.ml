open! Core
open Fx_core
open Helpers
module Booking = Payments_core.Booking

let chart = Booking.Chart.default
let customer_eur = Ledger.Account_id.of_string "customer:1/eur"
let customer_gbp = Ledger.Account_id.of_string "customer:1/gbp"
let funding = Ledger.Account_id.of_string "settlement:test"

let apply b event =
  Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event } |> Or_error.ok_exn
;;

(* Customer accounts in EUR and GBP, the chart's FX position and fee accounts, and a
   funding account that may go negative to pay in the opening balance. *)
let ledger ~eur_balance =
  let accounts =
    [ Ledger.Account.create customer_eur Liability
    ; Ledger.Account.create customer_gbp Liability
    ; Ledger.Account.create ~allow_negative:true funding Asset
    ]
    @ Booking.Chart.accounts chart ~rails:[] ~currencies:[ eur; gbp ]
  in
  let b = List.fold accounts ~init:Ledger.Balances.empty ~f:(fun b a -> apply b (Account_opened a)) in
  let deposit =
    Ledger.Entry.create
      ~idempotency_key:(Ledger.Idempotency_key.of_string "deposit-1")
      ~kind:(Transfer "deposit")
      ~effective_at:(at ~sec:(-60) ())
      ~recorded_at:(at ~sec:(-60) ())
      [ Ledger.Posting.debit funding (amount eur_balance)
      ; Ledger.Posting.credit customer_eur (amount eur_balance)
      ]
    |> Or_error.ok_exn
  in
  apply b (Posted deposit)
;;

let quote ?(id = "q-1") ?(now = at ()) request =
  Quote.create
    (table ())
    ~id:(Quote.Id.of_string id)
    ~sell:eur
    ~buy:gbp
    ~spread:(Or_error.ok_exn (Spread.create ~standard_bps:50 ()))
    request
    ~now
;;

let print_entries entries =
  List.iter entries ~f:(fun (e : Ledger.Entry.t) ->
    printf
      "%s %s\n"
      (Ledger.Idempotency_key.to_string e.idempotency_key)
      (Ledger.Entry.Code.to_string e.code);
    List.iter e.postings ~f:(fun p ->
      printf
        "  %-6s %-20s %s\n"
        (match p.side with
         | Debit -> "debit"
         | Credit -> "credit")
        (Ledger.Account_id.to_string p.account)
        (Money.Amount.to_string p.amount)))
;;

let%expect_test "a quote carries everything a receipt shows" =
  let q = ok (quote (Sell (amount "100.00 EUR"))) in
  print_s [%sexp (q : Quote.t)];
  [%expect
    {|
    ((id q-1) (sell "100.00 EUR") (buy "85.44 GBP") (fee "0.50 EUR")
     (fixed_side Sell) (mid_rate 0.85869565217391304348)
     (inverse_mid_rate 1.1645569620253164557) (customer_rate 0.8544021739)
     (inverse_customer_rate 1.170409007)
     (spread ((standard_bps 50) (applied_bps 50)))
     (basis
      ((source test) (origin Live) (rate_date 2026-10-09)
       (fetched_at "2026-10-09 12:00:00Z")))
     (stale false) (created_at "2026-10-09 12:00:00Z")
     (expires_at "2026-10-09 12:00:30Z"))
    |}]
;;

let%expect_test "quotes are refused on old rates unless offline" =
  let later = Time_ns.add (at ()) (Time_ns.Span.of_day 9.) in
  print_refusal (quote ~now:later (Sell (amount "100.00 EUR")));
  let q =
    Quote.create
      ~config:Quote.Config.offline
      (table ())
      ~id:(Quote.Id.of_string "q-offline")
      ~sell:eur
      ~buy:gbp
      ~spread:Spread.zero
      (Sell (amount "100.00 EUR"))
      ~now:later
    |> ok
  in
  print_s [%message (q.buy : Money.Amount.t) (q.stale : bool)];
  [%expect
    {|
    (rate_too_old
     (Rate_too_old (rate_date 2026-10-09) (fetched_at "2026-10-09 12:00:00Z")))
    ((q.buy "85.86 GBP") (q.stale true))
    |}]
;;

let%expect_test "executing books the sell leg, the fee and the buy leg" =
  let q = ok (quote (Sell (amount "100.00 EUR"))) in
  let book = Quote_book.add Quote_book.empty q |> Or_error.ok_exn in
  let b = ledger ~eur_balance:"150.00 EUR" in
  let execute ?(key = "x-1") ?(sec = 10) book =
    Exchange.execute
      book
      chart
      b
      ~quote_id:q.id
      ~from_:customer_eur
      ~to_:customer_gbp
      ~execution_key:key
      ~now:(at ~sec ())
  in
  let r = execute book |> Result.ok |> Option.value_exn in
  print_entries r.entries;
  let b = Booking.apply b r.entries |> Or_error.ok_exn in
  print_s
    [%message
      ""
        ~claim:(r.claim : Quote_book.Claim.t)
        ~status:(Quote_book.status r.book q.id ~now:(at ~sec:10 ()) : Quote_book.Status.t option)
        ~eur:(Ledger.Balances.available b customer_eur eur : Money.Amount.t)
        ~gbp:(Ledger.Balances.available b customer_gbp gbp : Money.Amount.t)];
  Ledger.Trial_balance.(check (of_balances b)) |> Or_error.ok_exn;
  (* A retry with the same key replays without booking; another key is refused. *)
  let again = execute ~key:"x-1" ~sec:60 r.book |> Result.ok |> Option.value_exn in
  print_s
    [%message
      "retry" ~claim:(again.claim : Quote_book.Claim.t) ~entries:(List.length again.entries : int)];
  let show r =
    print_s [%sexp (Result.map r ~f:(fun (_ : Exchange.t) -> ()) : (unit, Exchange.Error.t) Result.t)]
  in
  show (execute ~key:"x-2" r.book);
  [%expect
    {|
    x-1/swap-sell FX_LEG
      debit  customer:1/eur       99.50 EUR
      credit fx:position/EUR      99.50 EUR
    x-1/swap-fee FEE
      debit  customer:1/eur       0.50 EUR
      credit income:fees/EUR      0.50 EUR
    x-1/swap-buy FX_LEG
      debit  fx:position/GBP      85.44 GBP
      credit customer:1/gbp       85.44 GBP
    ((claim Fresh)
     (status ((Executed (execution_key x-1) (at "2026-10-09 12:00:10Z"))))
     (eur "50.00 EUR") (gbp "85.44 GBP"))
    (retry (claim Replayed) (entries 0))
    (Error (Refused (Quote_already_used q-1)))
    |}]
;;

let%expect_test "execution refusals leave the book unchanged" =
  let q = ok (quote (Sell (amount "100.00 EUR"))) in
  let book = Quote_book.add Quote_book.empty q |> Or_error.ok_exn in
  let try_ ?(quote_id = q.id) ~eur_balance ~sec () =
    Exchange.execute
      book
      chart
      (ledger ~eur_balance)
      ~quote_id
      ~from_:customer_eur
      ~to_:customer_gbp
      ~execution_key:"x-1"
      ~now:(at ~sec ())
    |> Result.map ~f:(fun (_ : Exchange.t) -> ())
    |> [%sexp_of: (unit, Exchange.Error.t) Result.t]
    |> print_s
  in
  try_ ~eur_balance:"150.00 EUR" ~sec:30 ();
  try_ ~eur_balance:"99.99 EUR" ~sec:5 ();
  try_ ~quote_id:(Quote.Id.of_string "nope") ~eur_balance:"150.00 EUR" ~sec:5 ();
  print_s
    [%sexp (Quote_book.status book q.id ~now:(at ~sec:5 ()) : Quote_book.Status.t option)];
  print_s
    [%sexp (Quote_book.status book q.id ~now:(at ~sec:30 ()) : Quote_book.Status.t option)];
  print_s
    [%sexp
      (Quote_book.add book q |> Result.map ~f:Quote_book.length : int Or_error.t)];
  print_s
    [%sexp (Quote_book.prune_expired book ~before:(at ~sec:31 ()) |> Quote_book.length : int)];
  [%expect
    {|
    (Error
     (Refused (Quote_expired (id q-1) (expires_at "2026-10-09 12:00:30Z"))))
    (Error
     (Refused
      (Insufficient_funds (available "99.99 EUR") (required "100.00 EUR"))))
    (Error (Refused (Unknown_quote nope)))
    (Open)
    (Expired)
    (Error ("quote already in the book" (id q-1)))
    0
    |}]
;;

let%test_unit "every executed quote books balanced entries that leave the customer with \
               the quoted amounts"
  =
  let gen =
    Quickcheck.Generator.tuple3
      (Int.gen_incl 1 10_000_000)
      (Int.gen_incl 0 Spread.max_bps)
      Bool.quickcheck_generator
  in
  Quickcheck.test gen ~trials:500 ~f:(fun (minor, bps, sell_fixed) ->
    let request : Pricing.Request.t =
      if sell_fixed
      then Sell (Money.Amount.of_minor_units_int eur minor)
      else Buy (Money.Amount.of_minor_units_int gbp minor)
    in
    match
      Quote.create
        (table ())
        ~id:(Quote.Id.of_string "q")
        ~sell:eur
        ~buy:gbp
        ~spread:(Or_error.ok_exn (Spread.create ~standard_bps:bps ()))
        request
        ~now:(at ())
    with
    | Error (Amount_too_small _) -> ()
    | Error r -> raise_s [%sexp (r : Refusal.t)]
    | Ok q ->
      let b = ledger ~eur_balance:"200000.00 EUR" in
      let entries =
        Exchange.book
          chart
          b
          q
          ~from_:customer_eur
          ~to_:customer_gbp
          ~execution_key:"k"
          ~now:(at ~sec:1 ())
        |> Result.ok
        |> Option.value_exn
      in
      let after = Booking.apply b entries |> Or_error.ok_exn in
      Ledger.Trial_balance.(check (of_balances after)) |> Or_error.ok_exn;
      [%test_result: Money.Amount.t]
        (Money.Amount.sub_exn
           (Ledger.Balances.available b customer_eur eur)
           (Ledger.Balances.available after customer_eur eur))
        ~expect:q.sell;
      [%test_result: Money.Amount.t]
        (Ledger.Balances.available after customer_gbp gbp)
        ~expect:q.buy;
      [%test_result: Money.Amount.t]
        (Ledger.Balances.available after (chart.fee_income eur) eur)
        ~expect:q.fee)
;;
