(******************************************************************************)
(* The Harmony Project                                                        *)
(* harmony@lists.seas.upenn.edu                                               *)
(******************************************************************************)
(* Copyright (C) 2008 J. Nathan Foster and Benjamin C. Pierce                 *)
(*                                                                            *)
(* This library is free software; you can redistribute it and/or              *)
(* modify it under the terms of the GNU Lesser General Public                 *)
(* License as published by the Free Software Foundation; either               *)
(* version 2.1 of the License, or (at your option) any later version.         *)
(*                                                                            *)
(* This library is distributed in the hope that it will be useful,            *)
(* but WITHOUT ANY WARRANTY; without even the implied warranty of             *)
(* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU          *)
(* Lesser General Public License for more details.                            *)
(******************************************************************************)
(* /src/bvalue.ml                                                             *)
(* Boomerang run-time values                                                  *)
(* $Id: bvalue.ml 4998 2011-03-16 21:53:34Z mgree $ *)
(******************************************************************************)

open Ubase
open Hbase

open Bsyntax
open Bident
open Benv

open MyStdlib
open Optician 
open Lang

module Info = Hbase.Info
module MLens = Blenses.MLens

module LensModule =
struct
  type t = Blenses.MLens.t
  let hash_fold_t _ _ = failwith "unimplemented"
  let hash _ = failwith "unimplemented"
  let compare _ _ = failwith "unimplemented"
  let pp _ _ = failwith "unimplemented"
  let show _ = failwith "unimplemented"
end

module IntToLens = DictOf(IntModule)(LensModule)

let rec to_boomerang_regex
  : Regex.t -> Brx.t =
  Regex.fold
    ~empty_f:Brx.empty
    ~base_f:Brx.mk_string
    ~concat_f:Brx.mk_seq
    ~or_f:Brx.mk_alt
    ~star_f:Brx.mk_star
    ~skip_f:Brx.mk_skip
    ~closed_f:ident
    ~require_f:Brx.mk_require

let rec to_boomerang_lens
    (i:Info.t)
    (d:IntToLens.t)
  : Lens.t -> MLens.t =
  Lens.fold
    ~disc_f:(fun r1 r2 s1 s2 ->
        Blenses.MLens.disconnect
          i
          (to_boomerang_regex r1)
          (to_boomerang_regex r2)
          (fun _ -> s1)
          (fun _ -> s2))
    ~concat_f:(Blenses.MLens.concat i)
    ~swap_f:(fun l1 l2 ->
        MLens.permute i [1;0] [l1;l2])
    ~union_f:(MLens.union i)
    ~compose_f:(MLens.compose i)
    ~iterate_f:(MLens.star i)
    ~identity_f:((MLens.copy i) % to_boomerang_regex)
    ~inverse_f:(MLens.invert i)
    ~permute_f:(fun il ml -> MLens.permute i (Permutation.as_int_list il) ml)
    ~closed_f:(fun i _ -> IntToLens.lookup_exn d i)

let retrieve_existing_lenses
    (relevant_regexps:Brx.t list)
    (e:CEnv.t)
  : (Lens.t * Regex.t * Regex.t) list * IntToLens.t =
  if not !Optician.Consts.use_lens_context then
    ([],IntToLens.empty)
  else
    let lens_list =
      List.filter_map
        ~f:ident
        (CEnv.fold
           (fun _ (_,v) acc -> (Bvalue.get_l_safe v)::acc)
           e
           [])
    in
    let lenses_types =
      List.filter_map
        ~f:(fun l ->
            let stype_o =
              List.find
                ~f:(Brx.equiv (Blenses.MLens.stype l))
                relevant_regexps
            in
            let vtype_o =
              List.find
                ~f:(Brx.equiv (Blenses.MLens.vtype l))
                relevant_regexps
            in
            begin match (stype_o,vtype_o) with
              | (Some stype, Some vtype) -> Some (l,stype,vtype)
              | _ -> None
            end)
        lens_list
    in

    let (_,d,lens_list) =
      List.fold_left
        ~f:(fun (i,d,lens_list) (l,s,v) ->
            let rr = Brx.to_optician_regexp v in
            let rl = Brx.to_optician_regexp s in
            let creater =
              (fun s ->
                 (Blenses.MLens.rcreater
                    l
                    (Bstring.of_string s)))
            in
            let createl =
              (fun s ->
                 (Blenses.MLens.rcreatel
                    l
                    (Bstring.of_string s)))
            in
            let putr =
              (fun s v ->
                 (Blenses.MLens.rputr
                    l
                    (Bstring.of_string s)
                    (Bstring.of_string v)))
            in
            let putl =
              (fun v s ->
                 (Blenses.MLens.rputl
                    l
                    (Bstring.of_string v)
                    (Bstring.of_string s)))
            in
            let lens =
              Lens.make_closed
                ~rr:rr
                ~rl:rl
                ~creater:creater
                ~createl:createl
                ~putr:putr
                ~putl:putl
                i
            in
            let d = IntToLens.insert d i l in
            let i = i + 1 in
            let lens_list = (lens,rl,rr)::lens_list in
            (i,d,lens_list))
        ~init:(0,IntToLens.empty,[])
        lenses_types
    in
    (lens_list,d)

let remove_skips
  : Regex.t -> Regex.t =
  Regex.fold
    ~empty_f:Regex.empty
    ~base_f:Regex.make_base
    ~concat_f:Regex.make_concat
    ~or_f:Regex.make_or
    ~star_f:Regex.make_star
    ~closed_f:Regex.make_closed
    ~skip_f:ident
    ~require_f:Regex.make_require

let remove_requires
  : Regex.t -> Regex.t =
  Regex.fold
    ~empty_f:Regex.empty
    ~base_f:Regex.make_base
    ~concat_f:Regex.make_concat
    ~or_f:Regex.make_or
    ~star_f:Regex.make_star
    ~closed_f:Regex.make_closed
    ~skip_f:Regex.make_skip
    ~require_f:ident

let synth
    (i:Info.t)
    (env:CEnv.t)
    (keep_going:float)
    (r1:Brx.t)
    (r2:Brx.t)
    (creater_exs:create_examples)
    (createl_exs:create_examples)
    (putr_exs:put_examples)
    (putl_exs:put_examples)
  : Blenses.MLens.t =
  let get_lens_size = Prefs.read Prefs.lensSizePref in
  let get_regex_size = Prefs.read Prefs.regexSizePref in
  if get_regex_size then
    Bconsts.regex_size := Brx.size r1 + Brx.size r2;
  let dumb_cost = Prefs.read Prefs.dumbCostPref in
  let dumb_cost_correct_pair = Prefs.read Prefs.dumbCostCorrectPairPref in
  let constants_cost = Prefs.read Prefs.constantsCostPref in
  let constants_cost_correct_pair = Prefs.read Prefs.constantsCostCorrectPairPref in
  let no_termination_condition = Prefs.read Prefs.noTerminationConditionPref in
  let termination_condition_25 = Prefs.read Prefs.twentyFiveTerminationConditionPref in
  let termination_condition_neg25 = Prefs.read Prefs.negTwentyFiveTerminationConditionPref in
  let no_keep_going = Prefs.read Prefs.noKeepGoingPref in
  Optician.Consts.gen_symmetric := not (Prefs.read Prefs.bijSynthPref);
  Optician.Consts.use_lens_context := not (Prefs.read Prefs.noCSPref);
  Optician.Consts.test_dumb_cost_at_correct_pair := dumb_cost_correct_pair;
  Optician.Consts.test_constants_cost_at_correct_pair := constants_cost_correct_pair;

  let subregexps = (Brx.subregexp_list r1)@(Brx.subregexp_list r2) in
  let (lss,d) = retrieve_existing_lenses subregexps env in
  let r1 = Brx.to_optician_regexp r1 in
  let r2 = Brx.to_optician_regexp r2 in
  let (r1,r2) =
    if Prefs.read Prefs.noSkipPref then
      (remove_skips r1, remove_skips r2)
    else
      (r1,r2)
  in
  let (r1,r2) =
    if Prefs.read Prefs.noRequirePref then
      (remove_requires r1, remove_requires r2)
    else
      (r1,r2)
  in
  let ans =
    to_boomerang_lens
      i
      d
      (Option.value_exn
         (Gen.gen_lens
            keep_going
            lss
            r1
            r2
            creater_exs
            createl_exs
            putr_exs
            putl_exs))
  in
  if get_lens_size then
    Bconsts.lens_size := MLens.lens_size ans;
  if dumb_cost then
    (Optician.Consts.no_intelligent_cost := true;
     let ans2 =
       to_boomerang_lens
         i
         d
         (Option.value_exn
            (Gen.gen_lens
               keep_going
               lss
               r1
               r2
               creater_exs
               createl_exs
               putr_exs
               putl_exs))
     in
     Optician.Consts.no_intelligent_cost := false;
     assert (Blenses.MLens.is_eq ans ans2);
     ans)
  else if constants_cost then
    (Optician.Consts.constants_cost := true;
     let ans2 =
       to_boomerang_lens
         i
         d
         (Option.value_exn
            (Gen.gen_lens
               0.
               lss
               r1
               r2
               creater_exs
               createl_exs
               putr_exs
               putl_exs))
     in
     Optician.Consts.constants_cost := false;
     assert (Blenses.MLens.is_eq ans ans2);
     ans)
  else if no_keep_going then
    (let ans2 =
       to_boomerang_lens
         i
         d
         (Option.value_exn
            (Gen.gen_lens
               0.
               lss
               r1
               r2
               creater_exs
               createl_exs
               putr_exs
               putl_exs))
     in
     assert (Blenses.MLens.is_eq ans ans2);
     ans)
  else if termination_condition_25 then
    (let ans2 =
       to_boomerang_lens
         i
         d
         (Option.value_exn
            (Gen.gen_lens
               25.0
               lss
               r1
               r2
               creater_exs
               createl_exs
               putr_exs
               putl_exs))
     in
     assert (Blenses.MLens.is_eq ans ans2);
     ans)
  else if termination_condition_neg25 then
    (let ans2 =
       to_boomerang_lens
         i
         d
         (Option.value_exn
            (Gen.gen_lens
               (-25.0)
               lss
               r1
               r2
               creater_exs
               createl_exs
               putr_exs
               putl_exs))
     in
     assert (Blenses.MLens.is_eq ans ans2);
     ans)
  else if no_termination_condition then
    (Optician.Consts.no_termination := true;
     let ans2 =
       to_boomerang_lens
         i
         d
         (Option.value_exn
            (Gen.gen_lens
               keep_going
               lss
               r1
               r2
               creater_exs
               createl_exs
               putr_exs
               putl_exs))
     in
     Optician.Consts.no_termination := false;
     assert (Blenses.MLens.is_eq ans ans2);
     ans)
  else
    ans
