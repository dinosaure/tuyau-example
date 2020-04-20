open Lwt.Infix

let response_handler ~f _ response body =
  let buf = Buffer.create 0x100 in
  let th, wk = Lwt.wait () in
  let on_eof () =
    Format.eprintf "[#] on EOF.\n%!" ;
    Httpaf.Body.close_reader body ;
    Lwt.wakeup_later wk () in
  let rec on_read payload ~off ~len =
    Format.eprintf "[#] on (%d byte(s).\n%!" len ;
    Buffer.add_string buf (Bigstringaf.substring payload ~off ~len) ;
    Httpaf.Body.schedule_read body ~on_eof ~on_read in
  Httpaf.Body.schedule_read body ~on_eof ~on_read ;
  Lwt.async (fun () -> th >>= fun () -> f response (Buffer.contents buf))

module Make (Time : Mirage_time.S) (StackV4 : Mirage_stack.V4) = struct
  let ( >>? ) = Lwt_result.bind
  let ( <.> ) f g = fun x -> f (g x)

  module Paf = Paf.Make(Time)(StackV4)
  include Paf

  let failf fmt = Format.kasprintf (fun err -> raise (Failure err)) fmt

  let error_handler _ = function
    | `Exn (Send_error err)
    | `Exn (Recv_error err)
    | `Exn (Close_error err) ->
      failf "Impossible to start a transmission: %s" err
    | `Invalid_response_body_length _ ->
      failf "Invalid response body-length"
    | `Malformed_response _ ->
      failf "Malformed response"
    | `Exn _exn -> ()
  
  let gimme ~resolvers kind domain_name =
    let headers = Httpaf.Headers.of_list [ "Host", "localhost" ] in
    let th, wk = Lwt.wait () in
    let f _ body = Lwt.wakeup_later wk body ; Lwt.return () in
    let response_handler = response_handler ~f in
    let fiber = match kind with
    | None ->
      let request = Httpaf.Request.create ~headers `GET
          (Fmt.strf "https://%a/" Domain_name.pp domain_name) in
      Paf.request ~resolvers ~response_handler ~error_handler domain_name request
    | Some `Secure ->
      let request = Httpaf.Request.create ~headers `GET
          (Fmt.strf "https://%a/" Domain_name.pp domain_name) in
      Paf.request ~key:tls_endpoint ~resolvers ~response_handler ~error_handler domain_name request
    | Some `Insecure ->
      let request = Httpaf.Request.create ~headers `GET
          (Fmt.strf "http://%a/" Domain_name.pp domain_name) in
      Paf.request ~key:TCP.endpoint ~resolvers ~response_handler ~error_handler domain_name request in
    fiber >>? fun body ->
    Format.eprintf "Connection established.\n%!" ;
    Httpaf.Body.close_writer body ; (* nothing to send *)
    Format.eprintf "Start to receive a response.\n%!" ;
    th >>= fun body -> Lwt.return (Ok body)
end
