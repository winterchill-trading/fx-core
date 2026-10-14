open! Core

let header = "date,currency,rate"

let parse_line ~pivot ~source line =
  match String.split line ~on:',' |> List.map ~f:String.strip with
  | [ date; currency; rate ] ->
    let open Or_error.Let_syntax in
    let%bind date = Or_error.try_with (fun () -> Date.of_string date) in
    let%bind currency = Money.Currency.of_string_or_error currency in
    let%bind per_pivot = Ratio.of_string_or_error rate in
    Observation.create
      ~pivot
      ~currency
      ~date
      ~per_pivot
      ~origin:Bundled
      ~source
      ~fetched_at:
        (Time_ns.of_date_ofday ~zone:Time_float.Zone.utc date Time_ns.Ofday.start_of_day)
  | _ -> Or_error.error_s [%message "expected three fields: date,currency,rate"]
;;

let parse ~pivot ~source text =
  String.split_lines text
  |> List.mapi ~f:(fun i line -> i + 1, String.strip line)
  |> List.filter ~f:(fun (_, line) ->
    not (String.is_empty line || String.is_prefix line ~prefix:"#"))
  |> (function
        | (_, first) :: rest when String.equal first header -> rest
        | lines -> lines)
  |> List.map ~f:(fun (n, line) ->
    parse_line ~pivot ~source line
    |> Or_error.tag_s ~tag:[%message "bundled rates" ~line:(n : int)])
  |> Or_error.combine_errors
;;

let to_csv observations =
  let rows =
    List.sort observations ~compare:(fun (a : Observation.t) (b : Observation.t) ->
      Comparable.lexicographic
        [ (fun (a : Observation.t) (b : Observation.t) -> Date.compare a.date b.date)
        ; (fun a b -> Money.Currency.compare a.currency b.currency)
        ]
        a
        b)
    |> List.map ~f:(fun (o : Observation.t) ->
      sprintf
        "%s,%s,%s"
        (Date.to_string o.date)
        (Money.Currency.to_string o.currency)
        (Ratio.to_string o.per_pivot))
  in
  String.concat ~sep:"\n" (header :: rows) ^ "\n"
;;
