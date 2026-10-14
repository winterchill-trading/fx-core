open! Async_kernel
open! Core
module Currency = Money.Currency

type t =
  { name : string
  ; volatility_bps : int
  ; pivot : Currency.t
  ; seeds : Ratio.t Currency.Map.t
  ; time_source : Time_source.t
  ; mutable reachable : bool
  }

let create ?(name = "simulated") ?(volatility_bps = 50) ~pivot ~seeds ~time_source () =
  let open Or_error.Let_syntax in
  let%bind seeds_map = Currency.Map.of_alist_or_error seeds in
  let%bind () =
    match
      Map.to_alist seeds_map
      |> List.find ~f:(fun (c, r) -> Currency.equal c pivot || Q.sign r <= 0)
    with
    | Some (currency, rate) ->
      Or_error.error_s
        [%message "bad seed" (currency : Currency.t) ~rate:(rate : Ratio.t)]
    | None -> Ok ()
  in
  let%map () =
    if volatility_bps < 0
    then Or_error.error_s [%message "negative volatility" (volatility_bps : int)]
    else Ok ()
  in
  { name
  ; volatility_bps
  ; pivot
  ; seeds = seeds_map
  ; time_source = Time_source.read_only time_source
  ; reachable = true
  }
;;

let usd_seeds () =
  List.map
    [ "EUR", "0.92"
    ; "GBP", "0.79"
    ; "CHF", "0.88"
    ; "JPY", "150"
    ; "CAD", "1.36"
    ; "AUD", "1.52"
    ; "SEK", "10.5"
    ; "NOK", "10.7"
    ; "PLN", "3.95"
    ]
    ~f:(fun (code, rate) ->
      Currency.of_string code, Or_error.ok_exn (Ratio.of_string_or_error rate))
;;

let set_reachable t reachable = t.reachable <- reachable

let rec publication_date date =
  if Day_of_week.is_sun_or_sat (Date.day_of_week date)
  then publication_date (Date.add_days date (-1))
  else date
;;

(* A drift in [-volatility, +volatility] basis points from the first 8 bytes of
   MD5("<currency>/<date>"): stable across runs, machines and OCaml versions. *)
let drift_bps t currency date =
  if t.volatility_bps = 0
  then 0
  else (
    let digest =
      Md5.digest_string (Currency.to_string currency ^ "/" ^ Date.to_string date)
      |> Md5.to_binary
    in
    let n =
      String.foldi (String.prefix digest 7) ~init:0 ~f:(fun i acc c ->
        acc lor (Char.to_int c lsl (8 * i)))
    in
    (n % ((2 * t.volatility_bps) + 1)) - t.volatility_bps)
;;

let rate t currency date =
  Map.find t.seeds currency
  |> Option.map ~f:(fun seed ->
    let date = publication_date date in
    let factor = Q.(one + (of_int (drift_bps t currency date) / of_int 10_000)) in
    Ratio.round_sig Half_even ~digits:6 (Q.mul seed factor))
;;

let name t = t.name
let attribution t = sprintf "Simulated reference rates (%s)" t.name
let url _ = None
let pivot t = t.pivot
let now t = Time_source.now t.time_source
let today t = Time_ns.to_date (now t) ~zone:Time_float.Zone.utc

let observation t currency date =
  Option.map (rate t currency date) ~f:(fun per_pivot ->
    Observation.create
      ~pivot:t.pivot
      ~currency
      ~date
      ~per_pivot
      ~origin:Live
      ~source:t.name
      ~fetched_at:(now t)
    |> (* Seeds are positive and never the pivot (checked in [create]). *)
    Or_error.ok_exn)
;;

let unreachable t = Or_error.error_s [%message "rate source unreachable" ~source:t.name]

let latest t =
  return
    (if not t.reachable
     then unreachable t
     else (
       let date = publication_date (today t) in
       Ok (List.filter_map (Map.keys t.seeds) ~f:(fun c -> observation t c date))))
;;

let history t ~currencies ~from ~to_ =
  return
    (if not t.reachable
     then unreachable t
     else
       Ok
         (Date.dates_between ~min:from ~max:(Date.min to_ (today t))
          |> List.filter ~f:(fun d -> not (Day_of_week.is_sun_or_sat (Date.day_of_week d)))
          |> List.concat_map ~f:(fun d ->
            List.filter_map currencies ~f:(fun c -> observation t c d))))
;;

let pack t =
  Rate_source.T
    ( (module struct
        type nonrec t = t

        let name = name
        let attribution = attribution
        let url = url
        let pivot = pivot
        let latest = latest
        let history = history
      end)
    , t )
;;
