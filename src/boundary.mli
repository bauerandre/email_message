open! Core.Std

type t [@@deriving sexp, bin_io, compare]

val hash : t -> int

(** Creates a boundary from the value of the "boundary" parameter in a
  Content-type header (RFC2046, p.19)
  Alias of to_string.
  *)
val create : string -> t

(** Splits an multipart body into a list of messages, and, if there are,
    an optional prologue and epilogue. *)
val split : t -> Bigstring_shared.t ->
  ( Bigstring_shared.t option *
    Bigstring_shared.t list *
    Bigstring_shared.t option)

(** Creates valid boundaries for given text. *)
val generate : ?text:Bigstring_shared.t -> ?suggest:t -> unit -> t

(** Open an close boundaries *)

(** Used when the boundary indicates a new part *)
module Open : String_monoidable.S with type t := t

(** Used when the boundary indicates that there are no more parts *)
module Close : String_monoidable.S with type t := t

(** Used when the boundary indicates the beginning of the first
  part of the message, and there is no prologue. *)
module Open_first : String_monoidable.S with type t := t

include Stringable.S with type t := t
