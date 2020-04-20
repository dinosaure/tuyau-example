let resolvers = Tuyau.empty

let ( <.> ) f g = fun x -> f (g x)

let reporter ppf =
  let report src level ~over k msgf =
    let k _ = over () ; k () in
    let with_metadata header _tags k ppf fmt =
      Format.kfprintf k ppf ("%a[%a]: " ^^ fmt ^^ "\n%!")
        Logs_fmt.pp_header (level, header)
        Fmt.(styled `Magenta string) (Logs.Src.name src) in
    msgf @@ fun ?header ?tags fmt -> with_metadata header tags k ppf fmt in
  { Logs.report } 

(* functoria *)
module Paf = Gimme.Make(Time)(Tcpip_stack_socket)
let () = Mirage_crypto_rng_unix.initialize ()
let () = Fmt_tty.setup_std_outputs ~style_renderer:`Ansi_tty ~utf_8:true ()
let () = Logs.set_reporter (reporter Fmt.stdout)
let () = Logs.set_level ~all:true (Some Logs.Debug)

open Lwt.Infix

let simple_dns_resolver ~port domain_name =
  match Unix.gethostbyname (Domain_name.to_string domain_name) with
  | { Unix.h_addr_list; _ } when Array.length h_addr_list > 0 ->
    let ip = Ipaddr_unix.V4.of_inet_addr h_addr_list.(0) |> Option.get in
    Tcpip_stack_socket.UDPV4.connect None >>= fun udpv4 ->
    Tcpip_stack_socket.TCPV4.connect None >>= fun tcpv4 ->
    Tcpip_stack_socket.connect [ Ipaddr.V4.localhost ] udpv4 tcpv4 >>= fun stack ->
    Lwt.return (Some { Tuyau_mirage_tcp.stack; keepalive= None; nodelay= false; ip; port; })
  | _ -> Lwt.return None

let https_resolver ~authenticator domain_name =
  simple_dns_resolver ~port:443 domain_name >>= function
  | None -> Lwt.return None
  | Some edn ->
    let config = Tls.Config.client ~authenticator () in
    Lwt.return (Some (edn, config))

let run ~resolvers kind domain_name =
  Paf.gimme kind ~resolvers domain_name >>= function
  | Ok body ->
    let oc = open_out "output.html" in
    output_string oc body ; Lwt.return ()
  | Error err -> Format.eprintf "<! %a\n%!" Tuyau_mirage.pp_error err ; Lwt.return ()

(* Do what you want. *)
let authenticator ~host: _ _ = Ok None

let resolvers = Tuyau_mirage.register_resolver
    ~key:Paf.TCP.endpoint ~priority:20
    (simple_dns_resolver ~port:80)
    resolvers

let resolvers = Tuyau_mirage.register_resolver
    ~key:Paf.tls_endpoint ~priority:10
    (https_resolver ~authenticator)
    resolvers

let () = match Sys.argv with
  | [| _; "--secure"; domain_name; |] ->
    let domain_name = Domain_name.(host_exn <.> of_string_exn) domain_name in
    Lwt_main.run (run (Some `Secure) ~resolvers domain_name)
  | [| _; "--insecure"; domain_name; |] ->
    let domain_name = Domain_name.(host_exn <.> of_string_exn) domain_name in
    Lwt_main.run (run (Some `Insecure) ~resolvers domain_name)
  | [| _; domain_name |] ->
    let domain_name = Domain_name.(host_exn <.> of_string_exn) domain_name in
    Lwt_main.run (run None ~resolvers domain_name)
  | _ -> Format.eprintf "%s [--secure|--insecure] domain-name\n%!" Sys.argv.(0)

