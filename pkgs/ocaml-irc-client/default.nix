{
  lib,
  fetchFromGitHub,
  ocamlPackages,
}:

ocamlPackages.buildDunePackage {
  # Core library only; the lwt, unix, tls and lwt-ssl transports are separate
  # opam packages in the same repository.
  pname = "irc-client";
  # Release 0.7.1 plus a README update.
  version = "0.7.1-unstable-d6f8b2a";

  src = fetchFromGitHub {
    owner = "johnelse";
    repo = "ocaml-irc-client";
    rev = "d6f8b2a2e044bf36cc77edaf2ca261facd950d98";
    hash = "sha256-ZnE9w8rWYxYJILvOfgzqyp1d1knS6vSZRfKQfYgP8+A=";
  };

  # Bytes is part of the supported OCaml stdlib; drop the legacy findlib
  # "bytes" stub dependency, which dune cannot resolve.
  postPatch = ''
    substituteInPlace src/core/dune \
      --replace-fail "result bytes logs base64" "result logs base64"
  '';

  minimalOCamlVersion = "4.02";

  propagatedBuildInputs = with ocamlPackages; [
    base64
    logs
    result
  ];

  doCheck = true;
  checkInputs = [ ocamlPackages.ounit ];

  postInstall = ''
    install -Dm444 LICENSE README.md -t $out/share/doc/ocaml-irc-client
  '';

  meta = {
    description = "Transport-independent core of the OCaml IRC client library";
    homepage = "https://github.com/johnelse/ocaml-irc-client";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
