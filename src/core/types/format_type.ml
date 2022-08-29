(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2022 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

 *****************************************************************************)

type Type.custom += Type of Content.format
type Type.constr_t += InternalMedia

let get = function Type c -> c | _ -> assert false

let handler f =
  {
    Type.typ = Type f;
    copy_with = (fun _ c -> Type (Content.duplicate (get c)));
    occur_check = (fun _ _ c -> ignore (get c));
    filter_vars =
      (fun _ l c ->
        ignore (get c);
        l);
    repr = (fun _ _ c -> `Constr (Content.string_of_format (get c), []));
    satisfies_constraint = (fun _ _ -> raise Type.Unsatisfied_constraint);
    subtype = (fun _ c c' -> Content.merge (get c) (get c'));
    sup =
      (fun _ c c' ->
        Content.merge (get c) (get c');
        c);
    to_string = (fun c -> Content.string_of_format (get c));
  }

let internal_media : Type.constr =
  object (self)
    method t = InternalMedia
    method descr = "an internal media type (none, pcm, yuva420p or midi)"

    method satisfied b =
      let is_internal name =
        try
          let kind = Content.kind_of_string name in
          Content.is_internal_kind kind
        with Content.Invalid -> false
      in
      let b = Type.demeth b in
      match b.Type.descr with
        | Type.Constr { constructor } when is_internal constructor -> ()
        | Type.Custom { Type.typ; satisfies_constraint } ->
            satisfies_constraint typ self
        | Type.Var { contents = Type.Free v } ->
            if
              not
                (List.exists (fun c -> c#t = InternalMedia) v.Type.constraints)
            then v.Type.constraints <- self :: v.Type.constraints
        | _ -> raise Type.Unsatisfied_constraint
  end

let descr f = Type.Custom (handler f)