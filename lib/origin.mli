(** Where a reference rate came from: fetched from a live source, or shipped with the
    application as a bundled table for offline use and history. On the same date a live
    rate is preferred over a bundled one. *)

open! Core

type t =
  | Live (** fetched from a rate source at run time *)
  | Bundled (** loaded from a table shipped with the application *)
[@@deriving sexp, compare, equal, enumerate, hash, quickcheck]

(** ["live"] or ["bundled"]. *)
val to_string : t -> string

(** Accepts [to_string] output. *)
val of_string_or_error : string -> t Or_error.t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
