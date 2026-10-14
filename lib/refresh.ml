open! Async_kernel
open! Core

module Policy = struct
  type t =
    { interval : Time_ns.Span.t
    ; retry_after : Time_ns.Span.t
    }
  [@@deriving sexp, compare, equal]

  let default = { interval = Time_ns.Span.of_hr 1.; retry_after = Time_ns.Span.of_min 5. }
end

module Attempt = struct
  type outcome =
    | Succeeded of
        { observations : int
        ; latest_rate_date : Date.t option
        }
    | Failed of string
  [@@deriving sexp_of, compare, equal]

  type t =
    { at : Time_ns.Alternate_sexp.t
    ; outcome : outcome
    }
  [@@deriving sexp_of, compare, equal]
end

module Status = struct
  type t =
    { last_attempt_at : Time_ns.Alternate_sexp.t option
    ; last_success_at : Time_ns.Alternate_sexp.t option
    ; latest_rate_date : Date.t option
    ; reachable : bool
    }
  [@@deriving sexp_of, compare, equal]

  let initial =
    { last_attempt_at = None
    ; last_success_at = None
    ; latest_rate_date = None
    ; reachable = false
    }
  ;;

  let apply t ({ at; outcome } : Attempt.t) =
    match outcome with
    | Failed _ -> { t with last_attempt_at = Some at; reachable = false }
    | Succeeded { latest_rate_date; observations = _ } ->
      { last_attempt_at = Some at
      ; last_success_at = Some at
      ; latest_rate_date = Option.merge t.latest_rate_date latest_rate_date ~f:Date.max
      ; reachable = true
      }
  ;;

  let stale t (policy : Freshness.Policy.t) ~now =
    match t.last_success_at with
    | None -> true
    | Some at -> Time_ns.Span.( > ) (Time_ns.diff now at) policy.stale_after
  ;;
end

let next_attempt_at (policy : Policy.t) (status : Status.t) ~now =
  match status.last_attempt_at with
  | None -> now
  | Some at ->
    Time_ns.add at (if status.reachable then policy.interval else policy.retry_after)
;;

let fetch source table ~now =
  let%map result = Rate_source.latest source in
  let merged =
    let%bind.Or_error observations = result in
    let%map.Or_error table = Rate_table.add_all table observations in
    table, observations
  in
  match merged with
  | Error e -> table, { Attempt.at = now; outcome = Failed (Error.to_string_hum e) }
  | Ok (table, observations) ->
    ( table
    , { Attempt.at = now
      ; outcome =
          Succeeded
            { observations = List.length observations
            ; latest_rate_date =
                List.map observations ~f:(fun (o : Observation.t) -> o.date)
                |> List.max_elt ~compare:Date.compare
            }
      } )
;;
