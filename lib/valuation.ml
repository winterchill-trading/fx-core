open! Core
module Amount = Money.Amount
module Currency = Money.Currency

type t =
  { base : Currency.t
  ; total : Amount.t option
  ; missing : Currency.t list
  ; basis : Basis.t option
  }
[@@deriving sexp_of, compare, equal]

let usable_mid ~freshness table ~sell ~buy ~now =
  let as_of = Time_ns.to_date now ~zone:Time_float.Zone.utc in
  match Rate_table.mid table ~sell ~buy ~as_of with
  | Error _ -> None
  | Ok mid ->
    (match Freshness.check freshness mid.basis ~now with
     | Ok () -> Some mid
     | Error _ -> None)
;;

let estimate ?(freshness = Freshness.Policy.default) table ~base holdings ~now =
  let sum, missing, basis =
    List.fold
      holdings
      ~init:(Q.zero, Currency.Set.empty, None)
      ~f:(fun (sum, missing, basis) amount ->
        let currency = Amount.currency amount in
        if Currency.equal currency base
        then Q.add sum (Amount.to_q amount), missing, basis
        else (
          match usable_mid ~freshness table ~sell:currency ~buy:base ~now with
          | None -> sum, Core.Set.add missing currency, basis
          | Some mid ->
            ( Q.add sum (Q.mul (Amount.to_q amount) mid.exact)
            , missing
            , Some
                (match basis with
                 | None -> mid.basis
                 | Some b -> Basis.combine b mid.basis) )))
  in
  { base
  ; total = (if Core.Set.is_empty missing then Some (Amount.of_q base sum) else None)
  ; missing = Core.Set.to_list missing
  ; basis
  }
;;

let at_least ?(freshness = Freshness.Policy.default) table amount ~threshold ~now =
  let currency = Amount.currency amount in
  let base = Amount.currency threshold in
  if Currency.equal currency base
  then Amount.( >= ) amount threshold
  else (
    match usable_mid ~freshness table ~sell:currency ~buy:base ~now with
    | None -> true
    | Some mid -> Q.( >= ) (Q.mul (Amount.to_q amount) mid.exact) (Amount.to_q threshold))
;;
