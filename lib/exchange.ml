open! Core

module Error = struct
  type t =
    | Refused of Refusal.t
    | Booking_failed of Error.t
  [@@deriving sexp_of]

  let to_error t = Core.Error.create_s [%sexp (t : t)]
end

let book_entries chart balances (quote : Quote.t) ~from_ ~to_ ~execution_key ~now =
  let open Result.Let_syntax in
  let%bind () =
    if Quote.is_expired quote ~now
    then
      Error
        (Error.Refused
           (Quote_expired
              { id = Quote.Id.to_string quote.id; expires_at = quote.expires_at }))
    else Ok ()
  in
  let available =
    Ledger.Balances.available balances from_ (Money.Amount.currency quote.sell)
  in
  let%bind () =
    if Money.Amount.( >= ) available quote.sell
    then Ok ()
    else Error (Error.Refused (Insufficient_funds { available; required = quote.sell }))
  in
  Payments_core.Swap.execute
    chart
    balances
    (Quote.to_swap_quote quote)
    ~from_
    ~to_
    ~event_id:execution_key
    ~now
  |> Result.map_error ~f:(fun e -> Error.Booking_failed e)
;;

let book = book_entries

type t =
  { book : Quote_book.t
  ; quote : Quote.t
  ; entries : Ledger.Entry.t list
  ; claim : Quote_book.Claim.t
  }

let execute quote_book chart balances ~quote_id ~from_ ~to_ ~execution_key ~now =
  let open Result.Let_syntax in
  let%bind book, quote, claim =
    Quote_book.claim quote_book quote_id ~execution_key ~now
    |> Result.map_error ~f:(fun r -> Error.Refused r)
  in
  match claim with
  | Replayed -> Ok { book; quote; entries = []; claim }
  | Fresh ->
    let%map entries = book_entries chart balances quote ~from_ ~to_ ~execution_key ~now in
    { book; quote; entries; claim }
;;
