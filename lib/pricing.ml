open! Core
module Amount = Money.Amount
module Currency = Money.Currency

module Fixed_side = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Sell
        | Buy
      [@@deriving bin_io, sexp, compare, equal, enumerate]
    end
  end

  include Stable.V1

  let to_string = function
    | Sell -> "sell"
    | Buy -> "buy"
  ;;
end

module Request = struct
  type t =
    | Sell of Amount.t
    | Buy of Amount.t
  [@@deriving sexp_of, compare, equal]

  let fixed_side : t -> Fixed_side.t = function
    | Sell _ -> Sell
    | Buy _ -> Buy
  ;;

  let amount (Sell a | Buy a) = a
end

let customer_digits = 10

let customer_rate ~mid ~spread_bps =
  let factor = Q.(one - (of_int spread_bps / of_int 10_000)) in
  Ratio.round_sig Down ~digits:customer_digits (Q.mul mid factor)
;;

let inverse_customer_rate rate =
  Ratio.round_sig Half_even ~digits:customer_digits (Q.inv rate)
;;

let default_max_minor_units = Z.(pred (shift_left one 53))

module Amounts = struct
  type t =
    { sell : Amount.t
    ; buy : Amount.t
    ; fee : Amount.t
    }
  [@@deriving sexp_of, compare, equal]
end

let amounts
  ?(max_minor_units = default_max_minor_units)
  ~sell:sell_currency
  ~buy:buy_currency
  ~customer_rate
  ~spread_bps
  (request : Request.t)
  =
  let open Result.Let_syntax in
  let given = Request.amount request in
  let expected =
    match request with
    | Sell _ -> sell_currency
    | Buy _ -> buy_currency
  in
  let%bind () =
    if Currency.equal (Amount.currency given) expected
    then Ok ()
    else Error (Refusal.Currency_mismatch { expected; got = Amount.currency given })
  in
  let%bind () =
    if Amount.is_positive given then Ok () else Error (Refusal.Amount_not_positive given)
  in
  let sell, buy =
    match request with
    | Sell sell ->
      ( sell
      , Amount.of_q ~rounding:Down buy_currency (Q.mul (Amount.to_q sell) customer_rate) )
    | Buy buy ->
      Amount.of_q ~rounding:Up sell_currency (Q.div (Amount.to_q buy) customer_rate), buy
  in
  let%bind () =
    if Amount.is_positive buy && Amount.is_positive sell
    then Ok ()
    else Error (Refusal.Amount_too_small given)
  in
  let%map () =
    if Z.gt (Amount.minor_units sell) max_minor_units
       || Z.gt (Amount.minor_units buy) max_minor_units
    then Error (Refusal.Amount_too_large given)
    else Ok ()
  in
  let fee = Amount.mul_bps ~rounding:Half_up sell ~bps:spread_bps in
  { Amounts.sell; buy; fee }
;;

type t =
  { amounts : Amounts.t
  ; fixed_side : Fixed_side.t
  ; mid : Rate_table.Mid.t
  ; customer_rate : Ratio.t
  ; inverse_customer_rate : Ratio.t
  ; spread : Spread.t
  }
[@@deriving sexp_of, compare, equal]

let price ?max_minor_units ~(mid : Rate_table.Mid.t) ~(spread : Spread.t) request =
  let rate = customer_rate ~mid:mid.rate ~spread_bps:spread.applied_bps in
  let%map.Result amounts =
    amounts
      ?max_minor_units
      ~sell:mid.sell
      ~buy:mid.buy
      ~customer_rate:rate
      ~spread_bps:spread.applied_bps
      request
  in
  { amounts
  ; fixed_side = Request.fixed_side request
  ; mid
  ; customer_rate = rate
  ; inverse_customer_rate = inverse_customer_rate rate
  ; spread
  }
;;
