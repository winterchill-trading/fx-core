open! Core

let header = "date,currency,rate"
let header_with_fetched_at = "date,currency,rate,fetched_at"
let utc = Time_float.Zone.utc

let fetched_at_to_string time =
  let date, ofday = Time_ns.to_date_ofday time ~zone:utc in
  (* Whole seconds always; the fraction only when there is one, without trailing zeros. *)
  let ofday =
    match String.lsplit2 (Time_ns.Ofday.to_string ofday) ~on:'.' with
    | None -> Time_ns.Ofday.to_string ofday
    | Some (seconds, fraction) ->
      (match String.rstrip fraction ~drop:(Char.equal '0') with
       | "" -> seconds
       | fraction -> seconds ^ "." ^ fraction)
  in
  Date.to_string date ^ "T" ^ ofday ^ "Z"
;;

(* An explicit offset is required: a bare local time would depend on the reader's zone. *)
let parse_fetched_at text =
  let has_offset =
    String.is_suffix text ~suffix:"Z"
    ||
    match String.rindex text 'T' with
    | None -> false
    | Some t ->
      String.exists (String.drop_prefix text t) ~f:(fun c ->
        Char.equal c '+' || Char.equal c '-')
  in
  if not has_offset
  then Or_error.error_s [%message "fetched_at needs a UTC offset" text]
  else
    Or_error.try_with (fun () -> Time_ns.of_string_with_utc_offset text)
    |> Or_error.tag_s ~tag:[%message "bad fetched_at" text]
;;

let parse_line ~pivot ~source line =
  let fields = String.split line ~on:',' |> List.map ~f:String.strip in
  match fields with
  | [ date; currency; rate ] | [ date; currency; rate; _ ] ->
    let open Or_error.Let_syntax in
    let%bind date = Or_error.try_with (fun () -> Date.of_string date) in
    let%bind currency = Money.Currency.of_string_or_error currency in
    let%bind per_pivot = Ratio.of_string_or_error rate in
    let%bind fetched_at =
      match fields with
      | [ _; _; _; fetched_at ] when not (String.is_empty fetched_at) ->
        parse_fetched_at fetched_at
      | _ -> Ok (Time_ns.of_date_ofday ~zone:utc date Time_ns.Ofday.start_of_day)
    in
    Observation.create
      ~pivot
      ~currency
      ~date
      ~per_pivot
      ~origin:Bundled
      ~source
      ~fetched_at
  | _ ->
    Or_error.error_s
      [%message "expected three or four fields: date,currency,rate[,fetched_at]"]
;;

let parse ~pivot ~source text =
  String.split_lines text
  |> List.mapi ~f:(fun i line -> i + 1, String.strip line)
  |> List.filter ~f:(fun (_, line) ->
    not (String.is_empty line || String.is_prefix line ~prefix:"#"))
  |> (function
        | (_, first) :: rest
          when String.equal first header || String.equal first header_with_fetched_at ->
          rest
        | lines -> lines)
  |> List.map ~f:(fun (n, line) ->
    parse_line ~pivot ~source line
    |> Or_error.tag_s ~tag:[%message "bundled rates" ~line:(n : int)])
  |> Or_error.combine_errors
;;

let to_csv ?(fetched_at = false) observations =
  let rows =
    List.sort observations ~compare:(fun (a : Observation.t) (b : Observation.t) ->
      Comparable.lexicographic
        [ (fun (a : Observation.t) (b : Observation.t) -> Date.compare a.date b.date)
        ; (fun a b -> Money.Currency.compare a.currency b.currency)
        ]
        a
        b)
    |> List.map ~f:(fun (o : Observation.t) ->
      let row =
        sprintf
          "%s,%s,%s"
          (Date.to_string o.date)
          (Money.Currency.to_string o.currency)
          (Ratio.to_string o.per_pivot)
      in
      if fetched_at then row ^ "," ^ fetched_at_to_string o.fetched_at else row)
  in
  let header = if fetched_at then header_with_fetched_at else header in
  String.concat ~sep:"\n" (header :: rows) ^ "\n"
;;
