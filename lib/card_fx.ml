open! Core
module Amount = Money.Amount

type t =
  { merchant_amount : Amount.t
  ; account_amount : Amount.t
  ; fee : Amount.t
  ; mid_rate : Ratio.t
  ; customer_rate : Ratio.t
  ; inverse_customer_rate : Ratio.t
  ; spread : Spread.t
  ; basis : Basis.t
  }
[@@deriving sexp_of, compare, equal]

let authorise
  ?inverse_digits
  ?(freshness = Freshness.Policy.default)
  table
  ~account_currency
  ~merchant_amount
  ~spread
  ~now
  =
  let open Result.Let_syntax in
  let as_of = Time_ns.to_date now ~zone:Time_float.Zone.utc in
  let%bind mid =
    Rate_table.mid
      table
      ~sell:account_currency
      ~buy:(Amount.currency merchant_amount)
      ~as_of
  in
  let%bind () = Freshness.check freshness mid.basis ~now in
  let%map priced = Pricing.price ?inverse_digits ~mid ~spread (Buy merchant_amount) in
  { merchant_amount
  ; account_amount = priced.amounts.sell
  ; fee = priced.amounts.fee
  ; mid_rate = mid.rate
  ; customer_rate = priced.customer_rate
  ; inverse_customer_rate = priced.inverse_customer_rate
  ; spread
  ; basis = mid.basis
  }
;;

let reprice t ~final_merchant_amount =
  let%map.Result amounts =
    Pricing.amounts
      ~sell:(Amount.currency t.account_amount)
      ~buy:(Amount.currency t.merchant_amount)
      ~customer_rate:t.customer_rate
      ~spread_bps:t.spread.applied_bps
      (Buy final_merchant_amount)
  in
  { t with
    merchant_amount = final_merchant_amount
  ; account_amount = amounts.sell
  ; fee = amounts.fee
  }
;;

let refund_share ~paid ~settled_merchant ~refund_merchant =
  let open Result.Let_syntax in
  let%bind () =
    let expected = Amount.currency settled_merchant in
    let got = Amount.currency refund_merchant in
    if Money.Currency.equal expected got
    then Ok ()
    else Error (Refusal.Currency_mismatch { expected; got })
  in
  let%bind () =
    match
      List.find [ paid; settled_merchant; refund_merchant ] ~f:(Fn.non Amount.is_positive)
    with
    | Some a -> Error (Refusal.Amount_not_positive a)
    | None -> Ok ()
  in
  let%map () =
    if Amount.( > ) refund_merchant settled_merchant
    then Error (Refusal.Amount_too_large refund_merchant)
    else Ok ()
  in
  Amount.of_minor_units
    (Amount.currency paid)
    (Z.div
       (Z.mul (Amount.minor_units paid) (Amount.minor_units refund_merchant))
       (Amount.minor_units settled_merchant))
;;
