open! Core
module Currency = Money.Currency

(* Both origins for one currency and date; a live rate wins over a bundled one. *)
module Slot = struct
  type t =
    { live : Observation.t option
    ; bundled : Observation.t option
    }
  [@@deriving sexp_of]

  let empty = { live = None; bundled = None }

  let set t (o : Observation.t) =
    match o.origin with
    | Live -> { t with live = Some o }
    | Bundled -> { t with bundled = Some o }
  ;;

  let count t =
    Bool.to_int (Option.is_some t.live) + Bool.to_int (Option.is_some t.bundled)
  ;;
end

module Selection = struct
  type t =
    | Prefer_live
    | Bundled_only
  [@@deriving sexp, compare, equal, enumerate]
end

type t =
  { pivot : Currency.t
  ; rates : Slot.t Date.Map.t Currency.Map.t
  }
[@@deriving sexp_of]

let create ~pivot = { pivot; rates = Currency.Map.empty }
let pivot t = t.pivot

let add t (o : Observation.t) =
  if not (Currency.equal o.pivot t.pivot)
  then
    Or_error.error_s
      [%message
        "observation has another pivot"
          ~table:(t.pivot : Currency.t)
          ~observation:(o.pivot : Currency.t)]
  else
    Ok
      { t with
        rates =
          Map.update t.rates o.currency ~f:(fun dates ->
            Map.update (Option.value dates ~default:Date.Map.empty) o.date ~f:(fun slot ->
              Slot.set (Option.value slot ~default:Slot.empty) o))
      }
;;

let add_all t os = List.fold_result os ~init:t ~f:add

let currencies t =
  Core.Set.to_list (Core.Set.add (Currency.Set.of_list (Map.keys t.rates)) t.pivot)
;;

let length t =
  Map.sum (module Int) t.rates ~f:(fun dates -> Map.sum (module Int) dates ~f:Slot.count)
;;

let pick ~(selection : Selection.t) (slot : Slot.t) =
  match selection with
  | Prefer_live -> Option.first_some slot.live slot.bundled
  | Bundled_only -> slot.bundled
;;

let lookup ?(selection = Selection.Prefer_live) t currency ~as_of =
  match Map.find t.rates currency with
  | None -> None
  | Some dates ->
    (* Walk back from [as_of]; a date whose slot has nothing usable for this selection
       (only a live rate under [Bundled_only]) is skipped. *)
    Map.to_sequence dates ~order:`Decreasing_key ~keys_less_or_equal_to:as_of
    |> Sequence.find_map ~f:(fun (_, slot) -> pick ~selection slot)
;;

let history ?(selection = Selection.Prefer_live) t currency ~from ~to_ =
  match Map.find t.rates currency with
  | None -> []
  | Some dates ->
    Map.to_sequence dates ~keys_greater_or_equal_to:from ~keys_less_or_equal_to:to_
    |> Sequence.filter_map ~f:(fun (_, slot) -> pick ~selection slot)
    |> Sequence.to_list
;;

let latest_date t =
  Map.fold t.rates ~init:None ~f:(fun ~key:_ ~data:dates acc ->
    match Map.max_elt dates, acc with
    | None, acc -> acc
    | Some (d, _), None -> Some d
    | Some (d, _), Some a -> Some (Date.max d a))
;;

let mid_digits = 20

module Mid = struct
  type t =
    { sell : Currency.t
    ; buy : Currency.t
    ; exact : Ratio.t
    ; rate : Ratio.t
    ; basis : Basis.t
    }
  [@@deriving sexp_of, compare, equal]

  let inverse_rate ?(digits = mid_digits) t =
    Ratio.round_sig Half_even ~digits (Q.inv t.exact)
  ;;

  let to_money_rate t =
    Money.Rate.create
      ~base:t.sell
      ~quote:t.buy
      ~price:t.rate
      ~at:t.basis.fetched_at
      ~source:t.basis.source
    |> Or_error.ok_exn
  ;;
end

(* The pivot is worth one of itself on every date and has no basis of its own. *)
let leg t ~selection currency ~as_of =
  if Currency.equal currency t.pivot
  then `Pivot
  else (
    match lookup ~selection t currency ~as_of with
    | Some o -> `Rate o
    | None -> `Missing currency)
;;

let combine ~sell ~buy a b =
  let per = function
    | `Pivot -> Q.one
    | `Rate (o : Observation.t) -> o.per_pivot
  in
  let basis =
    match a, b with
    | `Rate o, `Pivot | `Pivot, `Rate o -> Basis.of_observation o
    | `Rate x, `Rate y -> Basis.combine (Basis.of_observation x) (Basis.of_observation y)
    | `Pivot, `Pivot ->
      (* Unreachable: callers refuse [sell = buy] and only one currency is the pivot. *)
      assert false
  in
  let exact = Q.div (per b) (per a) in
  { Mid.sell
  ; buy
  ; exact
  ; rate = Ratio.round_sig Half_even ~digits:mid_digits exact
  ; basis
  }
;;

let mid ?(selection = Selection.Prefer_live) t ~sell ~buy ~as_of =
  if Currency.equal sell buy
  then Error (Refusal.Same_currency sell)
  else (
    let a = leg t ~selection sell ~as_of in
    let b = leg t ~selection buy ~as_of in
    match a, b with
    | `Missing x, `Missing y -> Error (Refusal.No_rate { missing = [ x; y ] })
    | `Missing x, _ | _, `Missing x -> Error (Refusal.No_rate { missing = [ x ] })
    | ((`Pivot | `Rate _) as a), ((`Pivot | `Rate _) as b) -> Ok (combine ~sell ~buy a b))
;;

let cross_history ?(selection = Selection.Prefer_live) t ~sell ~buy ~from ~to_ =
  if Currency.equal sell buy
  then []
  else (
    let by_date currency =
      if Currency.equal currency t.pivot
      then `Pivot
      else
        `Dates
          (history ~selection t currency ~from ~to_
           |> List.map ~f:(fun (o : Observation.t) -> o.date, `Rate o)
           |> Date.Map.of_alist_exn)
    in
    match by_date sell, by_date buy with
    | `Pivot, `Pivot -> []
    | `Pivot, `Dates m -> Map.data m |> List.map ~f:(fun b -> combine ~sell ~buy `Pivot b)
    | `Dates m, `Pivot -> Map.data m |> List.map ~f:(fun a -> combine ~sell ~buy a `Pivot)
    | `Dates ma, `Dates mb ->
      Map.fold2 ma mb ~init:[] ~f:(fun ~key:_ ~data acc ->
        match data with
        | `Both (a, b) -> combine ~sell ~buy a b :: acc
        | `Left _ | `Right _ -> acc)
      |> List.rev)
;;
