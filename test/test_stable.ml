open! Core
open Fx_core
open Helpers

(* A changed digest means old bytes no longer decode: add a Stable.V2 instead of editing
   V1, and keep V1 readable. *)
let%expect_test "stable bin_prot digests" =
  List.iter
    [ "Ratio", [%bin_digest: Ratio.Stable.V1.t]
    ; "Origin", [%bin_digest: Origin.Stable.V1.t]
    ; "Observation", [%bin_digest: Observation.Stable.V1.t]
    ; "Basis", [%bin_digest: Basis.Stable.V1.t]
    ; "Spread", [%bin_digest: Spread.Stable.V1.t]
    ; "Pricing.Fixed_side", [%bin_digest: Pricing.Fixed_side.Stable.V1.t]
    ; "Quote", [%bin_digest: Quote.Stable.V1.t]
    ]
    ~f:(fun (name, digest) -> printf "%-20s %s\n" name digest);
  [%expect {|
    Ratio                d9a8da25d5656b016fb4dbdc2e4197fb
    Origin               de3d5e6eb6592241e1590ff480f78136
    Observation          236405fd2d3813444c08e2d74e1aa5b1
    Basis                624c3754e3c407c48f0274cbc7dc8668
    Spread               2c50044b72bfeab8a6dde4ed2416e593
    Pricing.Fixed_side   f195aa66fc17dfbef47d0b69539a759c
    Quote                e309e50a2b80cb21362136e4ad3c2e9c
    |}]
;;

let round_trip (type a) (module M : Binable.S with type t = a) (x : a) =
  Bin_prot.Reader.of_string M.bin_reader_t (Bin_prot.Writer.to_string M.bin_writer_t x)
;;

let%expect_test "values round trip through bin_prot and sexp" =
  let q =
    Quote.create
      (table ())
      ~id:(Quote.Id.of_string "q-1")
      ~sell:eur
      ~buy:jpy
      ~spread:(Or_error.ok_exn (Spread.create ~standard_bps:50 ~caps:[ 35 ] ()))
      (Buy (amount "10000 JPY"))
      ~now:(at ())
    |> ok
  in
  [%test_result: Quote.t] (round_trip (module Quote.Stable.V1) q) ~expect:q;
  [%test_result: Quote.t] (Quote.t_of_sexp (Quote.sexp_of_t q)) ~expect:q;
  let o = obs ~origin:Bundled gbp "0.7912" in
  [%test_result: Observation.t] (round_trip (module Observation.Stable.V1) o) ~expect:o;
  [%test_result: Observation.t] (Observation.t_of_sexp (Observation.sexp_of_t o)) ~expect:o;
  let bad = Sexp.of_string "((standard_bps 10) (applied_bps 20))" in
  print_s [%sexp (Or_error.try_with (fun () -> Spread.t_of_sexp bad) : Spread.t Or_error.t)];
  [%expect {|
    (Error
     (Of_sexp_error
       "(\"applied spread must be between zero and the standard\" (applied_bps 20)\
      \n (standard_bps 10))" (invalid_sexp ((standard_bps 10) (applied_bps 20)))))
    |}]
;;
