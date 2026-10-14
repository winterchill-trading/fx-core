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

let observation ~pivot ~source ~fields ~date ~currency ~per_pivot =
  let open Or_error.Let_syntax in
  let%bind fetched_at =
    match fields with
    | [ _; _; _; fetched_at ] when not (String.is_empty fetched_at) ->
      parse_fetched_at fetched_at
    | _ -> Ok (Time_ns.of_date_ofday ~zone:utc date Time_ns.Ofday.start_of_day)
  in
  Observation.create ~pivot ~currency ~date ~per_pivot ~origin:Bundled ~source ~fetched_at
;;

module Unknown_currency = struct
  type t =
    { line : int
    ; currency : string
    }
  [@@deriving sexp, compare, equal]
end

let parse_line ~lenient ~pivot ~source line =
  let fields = String.split line ~on:',' |> List.map ~f:String.strip in
  match fields with
  | [ date; code; rate ] | [ date; code; rate; _ ] ->
    let open Or_error.Let_syntax in
    let%bind date = Or_error.try_with (fun () -> Date.of_string date) in
    (match Money.Currency.of_string_or_error code with
     | Error _ when lenient ->
       (* The rate is still checked, so a skipped row is a well-formed row: only the
          currency may be unknown. *)
       let%map (_ : Ratio.t) = Ratio.of_string_or_error rate in
       `Unknown code
     | currency ->
       let%bind currency in
       let%bind per_pivot = Ratio.of_string_or_error rate in
       let%map o = observation ~pivot ~source ~fields ~date ~currency ~per_pivot in
       `Observation o)
  | _ ->
    Or_error.error_s
      [%message "expected three or four fields: date,currency,rate[,fetched_at]"]
;;

let parse_lines ~lenient ~pivot ~source text =
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
    parse_line ~lenient ~pivot ~source line
    |> Result.map ~f:(fun r -> n, r)
    |> Or_error.tag_s ~tag:[%message "bundled rates" ~line:(n : int)])
  |> Or_error.combine_errors
;;

let parse_lenient ~pivot ~source text =
  let%map.Or_error rows = parse_lines ~lenient:true ~pivot ~source text in
  List.partition_map rows ~f:(fun (line, row) ->
    match row with
    | `Observation o -> First o
    | `Unknown currency -> Second { Unknown_currency.line; currency })
;;

let parse ?on_unknown_currency ~pivot ~source text =
  match on_unknown_currency with
  | None ->
    let%map.Or_error rows = parse_lines ~lenient:false ~pivot ~source text in
    List.filter_map rows ~f:(function
      | _, `Observation o -> Some o
      | _, `Unknown _ -> None)
  | Some f ->
    let%map.Or_error observations, unknown = parse_lenient ~pivot ~source text in
    List.iter unknown ~f;
    observations
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
