{
  lib,
  ocamlPackages,
  ocaml-irc-client,
}:

ocamlPackages.buildDunePackage {
  # Lwt OpenSSL transport; same upstream revision as the core library.
  pname = "irc-client-lwt-ssl";
  inherit (ocaml-irc-client) version src;

  # Bytes is part of the supported OCaml stdlib; drop the legacy findlib
  # "bytes" stub dependency, which dune cannot resolve.
  postPatch = ''
    substituteInPlace src/lwt_ssl/dune \
      --replace-fail "result bytes irc-client lwt ssl lwt_ssl" "result irc-client lwt ssl lwt_ssl"
  '';

  minimalOCamlVersion = "4.02";

  propagatedBuildInputs = [
    ocaml-irc-client
    ocamlPackages.result
    ocamlPackages.lwt
    ocamlPackages.ssl
    ocamlPackages.lwt_ssl
  ];

  # Upstream has no test suite for the Lwt SSL transport.

  postInstall = ''
    install -Dm444 LICENSE README.md -t $out/share/doc/ocaml-irc-client-lwt-ssl
  '';

  meta = {
    description = "Lwt OpenSSL transport for the OCaml IRC client library";
    homepage = "https://github.com/johnelse/ocaml-irc-client";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
