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
(* /src/boomerang.ml                                                          *)
(* Boomerang main function                                                    *)
(* $Id: boomerang.ml 4607 2009-08-03 16:53:28Z ddavi $ *)
(******************************************************************************)

(* Trivial front end; all command-line arguments are explicit *)

module P = Lbase.Prelude             

let () =
  P.load ();
  Bbase.Toplevel.toplevel "boomerang"
    
