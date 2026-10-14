open! Core
module Id = Payments_core.Swap.Id

module Stable = struct
  module V1 = struct
    type t =
      { id : Id.Stable.V1.t
      ; sell : Money.Amount.Stable.V1.t
      ; buy : Money.Amount.Stable.V1.t
      ; fee : Money.Amount.Stable.V1.t
      ; fixed_side : Pricing.Fixed_side.Stable.V1.t
      ; mid_rate : Ratio.Stable.V1.t
      ; inverse_mid_rate : Ratio.Stable.V1.t
      ; customer_rate : Ratio.Stable.V1.t
      ; inverse_customer_rate : Ratio.Stable.V1.t
      ; spread : Spread.Stable.V1.t
      ; basis : Basis.Stable.V1.t
      ; stale : bool
      ; created_at : Time_ns.Stable.Alternate_sexp.V1.t
      ; expires_at : Time_ns.Stable.Alternate_sexp.V1.t
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

module Config = struct
  type t =
    { ttl : Time_ns.Span.t
    ; freshness : Freshness.Policy.t
    ; max_minor_units : (Z.t[@sexp.opaque])
    }
  [@@deriving sexp_of]

  let default =
    { ttl = Time_ns.Span.of_sec 30.
    ; freshness = Freshness.Policy.default
    ; max_minor_units = Pricing.default_max_minor_units
    }
  ;;

  let offline = { default with freshness = Freshness.Policy.offline }
end

let create ?(config = Config.default) ?selection table ~id ~sell ~buy ~spread request ~now =
  let open Result.Let_syntax in
  let as_of = Time_ns.to_date now ~zone:Time_float.Zone.utc in
  let%bind mid = Rate_table.mid ?selection table ~sell ~buy ~as_of in
  let%bind () = Freshness.check config.freshness mid.basis ~now in
  let%map priced =
    Pricing.price ~max_minor_units:config.max_minor_units ~mid ~spread request
  in
  { id
  ; sell = priced.amounts.sell
  ; buy = priced.amounts.buy
  ; fee = priced.amounts.fee
  ; fixed_side = priced.fixed_side
  ; mid_rate = mid.rate
  ; inverse_mid_rate = Rate_table.Mid.inverse_rate mid
  ; customer_rate = priced.customer_rate
  ; inverse_customer_rate = priced.inverse_customer_rate
  ; spread
  ; basis = mid.basis
  ; stale = (Freshness.assess config.freshness mid.basis ~now).stale
  ; created_at = now
  ; expires_at = Time_ns.add now config.ttl
  }
;;

let is_expired t ~now = Time_ns.( >= ) now t.expires_at

let to_swap_quote t : Payments_core.Swap.Quote.t =
  let market =
    Money.Rate.create
      ~base:(Money.Amount.currency t.sell)
      ~quote:(Money.Amount.currency t.buy)
      ~price:t.mid_rate
      ~at:t.basis.fetched_at
      ~source:t.basis.source
    |> (* A quote's currencies differ and its mid rate is positive by construction. *)
    Or_error.ok_exn
  in
  { id = t.id
  ; sell = t.sell
  ; fee = t.fee
  ; buy = t.buy
  ; market
  ; spread_bps = t.spread.applied_bps
  ; created_at = t.created_at
  ; expires_at = t.expires_at
  }
;;
