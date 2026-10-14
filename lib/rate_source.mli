(** Where reference rates come from. A source returns observations against one pivot
    currency; it needs no credentials and is read-only. HTTP fetchers live in services;
    this library ships {!Simulated_source} and the bundled-table reader {!Bundled}. *)

open! Async_kernel
open! Core

module type S = sig
  type t

  (** Short name stored in each observation's [source]. *)
  val name : t -> string

  (** Text to show next to rates, e.g. the publisher's credit line. *)
  val attribution : t -> string

  (** Where people can read about the data. *)
  val url : t -> string option

  (** The pivot every observation is quoted against. *)
  val pivot : t -> Money.Currency.t

  (** The newest rate of every currency the source knows, with origin [Live]. *)
  val latest : t -> Observation.t list Deferred.Or_error.t

  (** Rates of [currencies] for every published date in [from, to_]. *)
  val history
    :  t
    -> currencies:Money.Currency.t list
    -> from:Date.t
    -> to_:Date.t
    -> Observation.t list Deferred.Or_error.t
end

(** A source of any implementation. *)
type t = T : (module S with type t = 'a) * 'a -> t

val name : t -> string
val attribution : t -> string
val url : t -> string option
val pivot : t -> Money.Currency.t
val latest : t -> Observation.t list Deferred.Or_error.t

val history
  :  t
  -> currencies:Money.Currency.t list
  -> from:Date.t
  -> to_:Date.t
  -> Observation.t list Deferred.Or_error.t
