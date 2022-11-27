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

(* Some vague inspiration drew from
   http://c4dm.eecs.qmul.ac.uk/audioengineering/compressors/documents/Reiss-Tutorialondynamicrangecompression.pdf
   https://github.com/nwjs/chromium.src/blob/df7f8c8582b9a78c806a7fa1e9d3f3ba51f7a698/third_party/WebKit/Source/platform/audio/DynamicsCompressorKernel.cpp
   and https://github.com/velipso/sndfilter/blob/master/src/compressor.c *)

open Mm
open Source

class compress ~attack ~release ~threshold ~ratio ~knee ~track_sensitive
  ~pre_gain ~make_up_gain ~lookahead ~window ~wet (source : source) =
  let lookahead () = Frame.audio_of_seconds (lookahead ()) in
  object (self)
    inherit operator ~name:"compress" [source] as super
    val mutable effect = None
    method private wake_up a = super#wake_up a
    method stype = source#stype
    method remaining = source#remaining
    method seek = source#seek
    method self_sync = source#self_sync
    method is_ready = source#is_ready
    method abort_track = source#abort_track

    (* Current gain in dB. *)
    val mutable gain = 0.
    method gain = gain

    (* Position in ringbuffer. *)
    val mutable ringbuffer_pos = 0
    val mutable ringbuffer = [||]

    (* Averaged mean of squares. *)
    val mutable ms = 0.
    method rms = sqrt ms

    (* Make sure that the ringbuffer can hold this much. *)
    method prepare n =
      if
        n > 0
        && (Array.length ringbuffer = 0 || Audio.Mono.length ringbuffer.(0) <> n)
      then ringbuffer <- Audio.create self#audio_channels n

    method private reset =
      gain <- 0.;
      ms <- 0.

    method private get_frame buf =
      let ofs = AFrame.position buf in
      source#get buf;
      let pos = AFrame.position buf in
      let partial = AFrame.is_partial buf in
      let buf = AFrame.pcm buf in
      let chans = self#audio_channels in
      let samplerate = float (Lazy.force Frame.audio_rate) in
      let threshold = threshold () in
      let knee = knee () in
      let ratio = ratio () in
      let attack = attack () in
      let attack_coef = 1. -. exp (-1. /. (attack *. samplerate)) in
      let release = release () in
      let release_coef = 1. -. exp (-1. /. (release *. samplerate)) in
      let lookahead = lookahead () in
      let pre_gain = pre_gain () in
      let pre_gain_lin = Audio.lin_of_dB pre_gain in
      let make_up_gain = make_up_gain () in
      let window = window () in
      let window_coef = 1. -. exp (-1. /. (window *. samplerate)) in
      let wet = wet () in
      self#prepare lookahead;
      for i = ofs to pos - 1 do
        (* Apply pre_gain. *)
        if pre_gain <> 0. then
          for c = 0 to chans - 1 do
            buf.(c).(i) <- buf.(c).(i) *. pre_gain_lin
          done;
        (* Compute input. *)
        let x =
          if window = 0. then (
            (* Peak mode: maximum absolute value over chans. *)
            let x = ref 0. in
            for c = 0 to chans - 1 do
              let old =
                if lookahead = 0 then buf.(c).(i)
                else (
                  let old = ringbuffer.(c).(ringbuffer_pos) in
                  ringbuffer.(c).(ringbuffer_pos) <- buf.(c).(i);
                  old)
              in
              x := max !x (abs_float old)
            done;
            if lookahead > 0 then
              ringbuffer_pos <- (ringbuffer_pos + 1) mod lookahead;
            let x = !x in
            ms <- x *. x;
            x)
          else (
            (* Smoothed RMS mode. *)
            let x = ref 0. in
            for c = 0 to chans - 1 do
              let old =
                if lookahead = 0 then buf.(c).(i)
                else (
                  let old = ringbuffer.(c).(ringbuffer_pos) in
                  ringbuffer.(c).(ringbuffer_pos) <- buf.(c).(i);
                  old)
              in
              x := !x +. (old *. old)
            done;
            if lookahead > 0 then
              ringbuffer_pos <- (ringbuffer_pos + 1) mod lookahead;
            ms <- ms +. (window_coef *. ((!x /. float chans) -. ms));
            sqrt ms)
        in
        (* From now on, we work in the dB domain, which gives better fidelity
           than the linear domain. *)
        let x = max (-80.) (Audio.dB_of_lin x) in
        (* Shape input. *)
        let x' =
          let x' =
            if x <= threshold -. (knee /. 2.) then x
            else if x < threshold +. (knee /. 2.) then (
              (* Second order interpolation for the knee. *)
              let a = x -. threshold +. (knee /. 2.) in
              x +. (((1. /. ratio) -. 1.) *. a *. a /. (2. *. knee)))
            else threshold +. ((x -. threshold) /. ratio)
          in
          x'
        in
        (* if x >= threshold then Printf.printf "%f => %f (%f)\tratio: %f\n%!" x x' (threshold +. (x -. threshold) /. ratio) ratio; *)
        (* Target gain (dB). *)
        let target = x' -. x in
        (* if x >= threshold then Printf.printf "gain: %f\ttarget: %f (%f -> %f)\n%!" gain target x x'; *)
        (* if gain > target then Printf.printf "Attack (%f -> %f)\tcoef: %f\n%!" gain target attack_coef; *)
        if gain > target then
          (* Attack. *)
          gain <- gain +. (attack_coef *. (target -. gain))
        else (* Release *)
          gain <- gain +. (release_coef *. (target -. gain));
        (* Finally apply gain. *)
        let gain = Audio.lin_of_dB (gain +. make_up_gain) in
        for c = 0 to chans - 1 do
          buf.(c).(i) <- buf.(c).(i) *. (1. -. wet +. (wet *. gain))
        done
      done;
      if partial && track_sensitive then self#reset
  end

let compress =
  let return_t =
    Lang.frame_t (Lang.univ_t ())
      (Frame.Fields.make ~audio:(Format_type.audio ()) ())
  in
  Lang.add_operator "compress"
    [
      ( "attack",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 50.),
        Some "Attack time (ms)." );
      ( "release",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 400.),
        Some "Release time (ms)." );
      ( "lookahead",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 0.),
        Some "Lookahead (ms)." );
      ( "threshold",
        Lang.getter_t Lang.float_t,
        Some (Lang.float (-10.)),
        Some "Threshold level (dB)." );
      ( "track_sensitive",
        Lang.bool_t,
        Some (Lang.bool false),
        Some "Reset on every track." );
      ( "knee",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 1.),
        Some "Knee width (dB)." );
      ( "pre_gain",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 0.),
        Some "Pre-amplification (dB)." );
      ( "gain",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 0.),
        Some "Post-amplification (dB)." );
      ( "ratio",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 2.),
        Some "Gain reduction ratio (reduction is ratio:1)." );
      ( "window",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 0.),
        Some "RMS window length (second). `0.` means peak mode." );
      ( "wet",
        Lang.getter_t Lang.float_t,
        Some (Lang.float 1.),
        Some
          "How much of input sound to output (between 0 and 1, 0 means only \
           original sound, 1 means only compressed sound)." );
      ("", Lang.source_t return_t, None, None);
    ]
    ~return_t ~category:`Audio ~descr:"Compress the signal."
    ~meth:
      [
        ( "gain",
          ([], Lang.fun_t [] Lang.float_t),
          "Gain (dB).",
          fun s -> Lang.val_fun [] (fun _ -> Lang.float s#gain) );
        ( "rms",
          ([], Lang.fun_t [] Lang.float_t),
          "RMS or peak power (linear).",
          fun s -> Lang.val_fun [] (fun _ -> Lang.float s#rms) );
      ]
    (fun p ->
      let attack = List.assoc "attack" p |> Lang.to_float_getter in
      let attack () = attack () /. 1000. in
      let release = List.assoc "release" p |> Lang.to_float_getter in
      let release () = release () /. 1000. in
      let lookahead = List.assoc "lookahead" p |> Lang.to_float_getter in
      let lookahead () = lookahead () /. 1000. in
      let threshold = List.assoc "threshold" p |> Lang.to_float_getter in
      let track_sensitive = List.assoc "track_sensitive" p |> Lang.to_bool in
      let ratio = List.assoc "ratio" p |> Lang.to_float_getter in
      let knee = List.assoc "knee" p |> Lang.to_float_getter in
      let pre_gain = List.assoc "pre_gain" p |> Lang.to_float_getter in
      let make_up_gain = List.assoc "gain" p |> Lang.to_float_getter in
      let window = List.assoc "window" p |> Lang.to_float_getter in
      let wet = List.assoc "wet" p |> Lang.to_float_getter in
      let s = List.assoc "" p |> Lang.to_source in
      new compress
        ~attack ~release ~lookahead ~ratio ~knee ~threshold ~track_sensitive
        ~pre_gain ~make_up_gain ~window ~wet s)
