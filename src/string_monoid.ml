open Core.Std

module Underlying = struct
  type t =
    | String of String.t
    | Bigstring of Bigstring.t
    | Char of char
  ;;

  let length = function
    | String str    -> String.length str
    | Bigstring str -> Bigstring.length str
    | Char _ -> 1
  ;;

  let blit_string ~src =
    match src with
    | String src ->
      (fun ?(src_pos=0) ?src_len:(len=(String.length src)) ~dst ?(dst_pos=0) () ->
         String.blit ~src ~src_pos ~len ~dst ~dst_pos)
    | Bigstring src -> Bigstring.To_string.blito ~src
    | Char c ->
      (fun ?(src_pos=0) ?(src_len=1) ~dst ?(dst_pos=0) () ->
         match src_pos, src_len with
         | 0, 1     -> dst.[dst_pos] <- c
         | (0|1), 0 -> ()
         | _, _     -> invalid_arg "index out of bounds")
  ;;

  let blit_bigstring ~src =
    match src with
    | String src -> Bigstring.From_string.blito ~src
    | Bigstring src -> Bigstring.blito ~src
    | Char c ->
      (fun ?(src_pos=0) ?(src_len=1) ~dst ?(dst_pos=0) () ->
         match src_pos, src_len with
         | 0, 1     -> dst.{dst_pos} <- c
         | (0|1), 0 -> ()
         | _, _     -> invalid_arg "index out of bounds")
  ;;

  let output_channel ~channel = function
    | String str -> Out_channel.output_string channel str
    | Bigstring bstr -> Bigstring.really_output channel bstr
    | Char c -> Out_channel.output_char channel c
  ;;

  let output_unix ~writer = function
    | String str -> Async.Std.Writer.write writer str
    | Bigstring bstr -> Async.Std.Writer.write_bigstring writer bstr
    | Char c -> Async.Std.Writer.write_char writer c
  ;;
end

type t =
  | List of (int * t list)
  | Leaf of Underlying.t
;;

let empty = List (0,[]);;

let of_string s =
  if String.is_empty s then
    empty
  else
    Leaf (Underlying.String s)
;;

let of_bigstring bs =
  if 0 = Bigstring.length bs
  then empty
  else Leaf (Underlying.Bigstring bs)
;;

let of_char c = Leaf (Underlying.Char c);;

let nl = of_char '\n';;

let length = function
  | List (len, _) -> len
  | Leaf underlying -> Underlying.length underlying
;;

(**
   The plus operation is not associative over individual representations,
   but is associative over the quotient space with the equivalence
   relationship
   x ~ y == (to_string x) = (to_string y)
*)
let plus a b =
  match a, b with
  | b, List (0,_)          -> b
  | List (0, _), b         -> b
  | List (len, _) , b      -> List (len + (length b), [a;b])
  | Leaf a', List (len, l) -> List ((Underlying.length a') + len, a :: l)
  | Leaf x, Leaf y  -> List (Underlying.((length x) + (length y)), [a;b])
;;


let concat ?(sep=empty) ts =
  (* Fold right is more efficient than fold_left, as it will create a
     flat List node *)
  match ts with
  | []      -> empty
  | t :: ts ->
    plus t
      (List.fold_right ts
         ~f:(fun t ts -> plus sep (plus t ts))
         ~init:empty)
;;

let concat_underlying ~of_underlying ?sep strs =
  let sep = Option.map sep ~f:of_underlying in
  let ts = List.map strs ~f:of_underlying in
  concat ?sep ts
;;

let concat_string = concat_underlying ~of_underlying:of_string;;
(*
   let __UNUSED_VALUE__concat_bigstring =
   concat_underlying ~of_underlying:of_bigstring;;
*)

type blitter =
  src:Underlying.t -> ?src_pos:int -> ?src_len:int -> ?dst_pos:int -> unit -> unit
;;

let blit ~(dst_blit:blitter) t =
  let rec blit dst_pos t =
    match t with
    | Leaf src -> dst_blit ~src ~dst_pos ()
    | List (len, srcs) ->
      let len' = List.fold_left srcs ~init:dst_pos
                   ~f:(fun dst_pos t ->
                     blit dst_pos t;
                     dst_pos + (length t))
      in
      assert ((len' - dst_pos) = len)
  in
  blit 0 t
;;

let to_string t =
  let dst = String.create (length t) in
  blit ~dst_blit:(Underlying.blit_string ~dst) t;
  dst
;;

let to_bigstring t =
  let dst = Bigstring.create (length t) in
  blit ~dst_blit:(Underlying.blit_bigstring ~dst) t;
  dst
;;

let output ~dst_output t =
  let rec output t =
    match t with
    | Leaf underlying -> dst_output underlying
    | List (_,ts) -> List.iter ~f:output ts
  in
  output t
;;

let output_channel t channel =
  output ~dst_output:(Underlying.output_channel ~channel) t
;;

let output_unix t writer =
  output ~dst_output:(Underlying.output_unix ~writer) t
;;


