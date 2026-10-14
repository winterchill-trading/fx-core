open! Async_kernel
open! Core

module type S = sig
  type t

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
end

type t = T : (module S with type t = 'a) * 'a -> t

let name (T ((module M), s)) = M.name s
let attribution (T ((module M), s)) = M.attribution s
let url (T ((module M), s)) = M.url s
let pivot (T ((module M), s)) = M.pivot s
let latest (T ((module M), s)) = M.latest s
let history (T ((module M), s)) ~currencies ~from ~to_ = M.history s ~currencies ~from ~to_
