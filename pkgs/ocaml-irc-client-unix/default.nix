{
  lib,
  ocamlPackages,
  ocaml-irc-client,
}:

ocamlPackages.buildDunePackage {
  # Unix blocking-I/O transport; same upstream revision as the core library.
  pname = "irc-client-unix";
  inherit (ocaml-irc-client) version src;

  # Bytes is part of the supported OCaml stdlib; drop the legacy findlib
  # "bytes" stub dependency, which dune cannot resolve.
  postPatch = ''
    substituteInPlace src/unix/dune \
      --replace-fail "result bytes irc-client unix" "result irc-client unix"
  '';

  minimalOCamlVersion = "4.02";

  propagatedBuildInputs = [
    ocaml-irc-client
    ocamlPackages.result
  ];

  # Upstream has no test suite for the Unix transport.

  postInstall = ''
    install -Dm444 LICENSE README.md -t $out/share/doc/ocaml-irc-client-unix
  '';

  meta = {
    description = "Unix blocking-I/O transport for the OCaml IRC client library";
    homepage = "https://github.com/johnelse/ocaml-irc-client";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
