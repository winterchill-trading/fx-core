open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Live
      | Bundled
    [@@deriving bin_io, sexp, compare, equal, enumerate, hash, quickcheck]
  end
end

include Stable.V1

let to_string = function
  | Live -> "live"
  | Bundled -> "bundled"
;;

let of_string_or_error = function
  | "live" -> Ok Live
  | "bundled" -> Ok Bundled
  | s -> Or_error.error_s [%message "unknown rate origin" s]
;;
