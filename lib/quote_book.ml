open! Core

module Status = struct
  type t =
    | Open
    | Executed of
        { execution_key : string
        ; at : Time_ns.Alternate_sexp.t
        }
    | Expired
  [@@deriving sexp_of, compare, equal]

  let to_string = function
    | Open -> "open"
    | Executed _ -> "executed"
    | Expired -> "expired"
  ;;
end

module Entry = struct
  type t =
    { quote : Quote.t
    ; executed : (string * Time_ns.Alternate_sexp.t) option
    }
  [@@deriving sexp_of]
end

type t = Entry.t Quote.Id.Map.t [@@deriving sexp_of]

let empty = Quote.Id.Map.empty

let add t (q : Quote.t) =
  match Map.add t ~key:q.id ~data:{ Entry.quote = q; executed = None } with
  | `Ok t -> Ok t
  | `Duplicate -> Or_error.error_s [%message "quote already in the book" ~id:(q.id : Quote.Id.t)]
;;

let find t id = Map.find t id |> Option.map ~f:(fun (e : Entry.t) -> e.quote)

let status_of (e : Entry.t) ~now : Status.t =
  match e.executed with
  | Some (execution_key, at) -> Executed { execution_key; at }
  | None -> if Quote.is_expired e.quote ~now then Expired else Open
;;

let status t id ~now = Map.find t id |> Option.map ~f:(status_of ~now)

module Claim = struct
  type t =
    | Fresh
    | Replayed
  [@@deriving sexp_of, compare, equal]
end

let claim t id ~execution_key ~now =
  let id_s = Quote.Id.to_string id in
  match Map.find t id with
  | None -> Error (Refusal.Unknown_quote id_s)
  | Some e ->
    (match status_of e ~now with
     | Executed { execution_key = k; _ } when String.equal k execution_key ->
       Ok (t, e.quote, Claim.Replayed)
     | Executed _ -> Error (Refusal.Quote_already_used id_s)
     | Expired -> Error (Refusal.Quote_expired { id = id_s; expires_at = e.quote.expires_at })
     | Open ->
       Ok
         ( Map.set t ~key:id ~data:{ e with executed = Some (execution_key, now) }
         , e.quote
         , Claim.Fresh ))
;;

let prune_expired t ~before =
  Map.filter t ~f:(fun (e : Entry.t) ->
    Option.is_some e.executed || Time_ns.( >= ) e.quote.expires_at before)
;;

let length = Map.length
