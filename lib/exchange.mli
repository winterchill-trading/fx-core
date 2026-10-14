(** Executing a quote: the ledger entries of a currency exchange.

    An exchange books, through {!Payments_core.Swap.execute}:
    - the sell leg: [sell - fee] from the paying account to the institution's FX position
      in the sold currency;
    - the fee: [fee] from the paying account to fee income in the sold currency (left
      out when zero);
    - the buy leg: [buy] from the FX position in the bought currency to the receiving
      account.

    Each entry balances in its own currency. The chart decides which accounts the FX
    position and fee income are ({!Payments_core.Booking.Chart.t}); a bank that calls them
    "fx settlement" and "fx revenue" passes its own chart. Entries are idempotent under
    [<execution key>/swap-sell], [/swap-fee] and [/swap-buy]. *)

open! Core

(** Why an execution failed: a refusal the customer can be told about, or a ledger
    failure (unknown or closed account, a rule of the chart) that is the operator's. *)
module Error : sig
  type t =
    | Refused of Refusal.t
    | Booking_failed of Error.t
  [@@deriving sexp_of]

  val to_error : t -> Core.Error.t
end

(** The entries for executing [quote] at [now], checked against [balances]. Refuses an
    expired quote and a paying account whose available balance in the sold currency is
    below [quote.sell]. Does not consult a quote book; see [execute]. *)
val book
  :  Payments_core.Booking.Chart.t
  -> Ledger.Balances.t
  -> Quote.t
  -> from_:Ledger.Account_id.t
  -> to_:Ledger.Account_id.t
  -> execution_key:string
  -> now:Time_ns.t
  -> (Ledger.Entry.t list, Error.t) Result.t

(** The outcome of [execute]. *)
type t =
  { book : Quote_book.t (** the quote marked executed *)
  ; quote : Quote.t
  ; entries : Ledger.Entry.t list
  (** to append; empty on a replay, whose entries were booked the first time *)
  ; claim : Quote_book.Claim.t
  }

(** Claims the quote in [book] under [execution_key] and books it, all or nothing: when
    booking fails the returned error leaves the caller's book untouched. A replay with
    the same key books nothing again. *)
val execute
  :  Quote_book.t
  -> Payments_core.Booking.Chart.t
  -> Ledger.Balances.t
  -> quote_id:Quote.Id.t
  -> from_:Ledger.Account_id.t
  -> to_:Ledger.Account_id.t
  -> execution_key:string
  -> now:Time_ns.t
  -> (t, Error.t) Result.t
