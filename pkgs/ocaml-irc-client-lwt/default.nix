{
  lib,
  ocamlPackages,
  ocaml-irc-client,
}:

ocamlPackages.buildDunePackage {
  # Lwt cooperative transport; same upstream revision as the core library.
  pname = "irc-client-lwt";
  inherit (ocaml-irc-client) version src;

  # Bytes is part of the supported OCaml stdlib; drop the legacy findlib
  # "bytes" stub dependency, which dune cannot resolve.
  postPatch = ''
    substituteInPlace src/lwt/dune \
      --replace-fail "result bytes irc-client lwt lwt.unix" "result irc-client lwt lwt.unix"
  '';

  minimalOCamlVersion = "4.02";

  propagatedBuildInputs = [
    ocaml-irc-client
    ocamlPackages.result
    ocamlPackages.lwt
  ];

  # Upstream has no test suite for the Lwt transport.

  postInstall = ''
    install -Dm444 LICENSE README.md -t $out/share/doc/ocaml-irc-client-lwt
  '';

  meta = {
    description = "Lwt cooperative transport for the OCaml IRC client library";
    homepage = "https://github.com/johnelse/ocaml-irc-client";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
