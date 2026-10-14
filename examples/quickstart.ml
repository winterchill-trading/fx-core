(* From reference rates to booked ledger entries: the README walk-through. *)

open! Core
open Fx_core

let usd = Money.Currency.usd
let eur = Money.Currency.eur
let gbp = Money.Currency.gbp
let now = Time_ns.of_string_with_utc_offset "2026-10-09T12:00:00Z"

let () =
  (* 1. A rate table: units per USD, one observation per currency, date and origin. *)
  let observation currency rate =
    Observation.create
      ~pivot:usd
      ~currency
      ~date:(Date.of_string "2026-10-09")
      ~per_pivot:(Ratio.of_string_or_error rate |> Or_error.ok_exn)
      ~origin:Live
      ~source:"example"
      ~fetched_at:now
    |> Or_error.ok_exn
  in
  let table =
    Rate_table.add_all
      (Rate_table.create ~pivot:usd)
      [ observation eur "0.92"; observation gbp "0.79" ]
    |> Or_error.ok_exn
  in
  (* 2. A quote: sell 100 EUR for GBP at 50 bps, capped at 35 bps for this tier. *)
  let schedule =
    Spread.Schedule.create ~standard_bps:50 ~tier_caps:[ "plus", 35 ] |> Or_error.ok_exn
  in
  let spread = Spread.Schedule.spread schedule ~tier:"plus" () |> Or_error.ok_exn in
  let quote =
    Quote.create
      table
      ~id:(Quote.Id.of_string "quote-1")
      ~sell:eur
      ~buy:gbp
      ~spread
      (Sell (Money.Amount.of_string "100.00 EUR"))
      ~now
    |> Result.map_error ~f:Refusal.to_error
    |> Or_error.ok_exn
  in
  printf
    "sell %s, buy %s, fee %s, customer rate %s\n"
    (Money.Amount.to_string quote.sell)
    (Money.Amount.to_string quote.buy)
    (Money.Amount.to_string quote.fee)
    (Ratio.to_string quote.customer_rate);
  (* 3. A ledger with a funded EUR account and the chart's FX accounts. *)
  let chart = Payments_core.Booking.Chart.default in
  let customer_eur = Ledger.Account_id.of_string "customer:1/eur" in
  let customer_gbp = Ledger.Account_id.of_string "customer:1/gbp" in
  let funding = Ledger.Account_id.of_string "funding" in
  let apply b event =
    Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event } |> Or_error.ok_exn
  in
  let balances =
    List.fold
      ([ Ledger.Account.create customer_eur Liability
       ; Ledger.Account.create customer_gbp Liability
       ; Ledger.Account.create ~allow_negative:true funding Asset
       ]
       @ Payments_core.Booking.Chart.accounts chart ~rails:[] ~currencies:[ eur; gbp ])
      ~init:Ledger.Balances.empty
      ~f:(fun b a -> apply b (Account_opened a))
  in
  let balances =
    apply
      balances
      (Posted
         (Ledger.Entry.create
            ~idempotency_key:(Ledger.Idempotency_key.of_string "deposit-1")
            ~kind:(Transfer "deposit")
            ~effective_at:now
            ~recorded_at:now
            [ Ledger.Posting.debit funding (Money.Amount.of_string "250.00 EUR")
            ; Ledger.Posting.credit customer_eur (Money.Amount.of_string "250.00 EUR")
            ]
          |> Or_error.ok_exn))
  in
  (* 4. Execute once: the quote book refuses a second use with another key. *)
  let book = Quote_book.add Quote_book.empty quote |> Or_error.ok_exn in
  let executed =
    Exchange.execute
      book
      chart
      balances
      ~quote_id:quote.id
      ~from_:customer_eur
      ~to_:customer_gbp
      ~execution_key:"exchange-1"
      ~now:(Time_ns.add now (Time_ns.Span.of_sec 5.))
    |> Result.map_error ~f:Exchange.Error.to_error
    |> Or_error.ok_exn
  in
  let balances = Payments_core.Booking.apply balances executed.entries |> Or_error.ok_exn in
  printf
    "entries %d; EUR %s, GBP %s\n"
    (List.length executed.entries)
    (Money.Amount.to_string (Ledger.Balances.available balances customer_eur eur))
    (Money.Amount.to_string (Ledger.Balances.available balances customer_gbp gbp))
;;
