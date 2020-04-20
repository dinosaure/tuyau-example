# An example of how to use tuyau

This project is experimental and use `paf` as a plumbery between
HTTP/AF and TLS - which is really new and can have some bugs.

So, the project can fail but the fault is more about `paf` than `tuyau` which
just dispatch correctly which implementation we want to use.

The project is easy to use:
```sh
$ dune exec bin/example.exe -- [--insecure|--secure] domain-name
$ dune exec bin/example.exe -- --secure twitter.com
```

It produces a simple `output.html`.

The most interesting part is into the `gimme` project (or `paf`) which provides
an abstract way to download such contents. It does not do the choice to use TLS
or not but it can enforce to use it with the `?key` parameter.

Then, if the ressource is not available with TLS, we fallback to a simple TCP 
connection. It can enforce to directly use the TCP connection however (with `--insecure`).
This example show that the user can be aware about the underlying used protocol (with `?key`)
or just let to `tuyau` to try any way to communicate with our peer.
