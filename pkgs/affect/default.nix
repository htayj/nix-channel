{
  lib,
  fetchFromGitHub,
  ocamlPackages,
}:

let
  # Four commits after the v0.0.0 tag.
  version = "0.0.0-unstable-2026-08-12";
in
ocamlPackages.buildTopkgPackage {
  pname = "affect";
  inherit version;

  src = fetchFromGitHub {
    owner = "dbuenzli";
    repo = "affect";
    rev = "780faa266d62f9567fd9d23f84bddc77f77087c0";
    hash = "sha256-AMmJuvMTtCyIDrwUSSSH14uD0UV7X4OiBLFy07f95AA=";
  };

  minimalOCamlVersion = "5.5";

  # Topkg watermarks only release tarballs; a Git snapshot keeps the
  # placeholder in the installed findlib metadata.
  postPatch = ''
    substituteInPlace pkg/META --replace-fail "%%VERSION_NUM%%" "${version}"
  '';

  # affect.cli is built only with Cmdliner, and its META requires it.
  propagatedBuildInputs = [ ocamlPackages.cmdliner ];

  buildPhase = ''
    runHook preBuild
    ${ocamlPackages.topkg.run} build --dev-pkg false --with-cmdliner true
    runHook postBuild
  '';

  postInstall = ''
    install -Dm444 test/quick_start.ml test/blueprint_cli.ml \
      -t $out/share/doc/affect/examples
  '';

  # Upstream's test suites need b0's testing library and are driven by b0.
  # Link and run its standalone programs against the installed libraries.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export OCAMLPATH=$OCAMLFIND_DESTDIR''${OCAMLPATH:+:$OCAMLPATH}
    ocamlfind query affect affect.unix affect.tmp affect.cli
    for name in quick_start blueprint_minimal blueprint_minimal_unix blueprint_cli; do
      ocamlfind ocamlopt -thread -package affect.unix,affect.tmp,affect.cli \
        -linkpkg test/$name.ml -o $name
      ./$name
    done
    runHook postInstallCheck
  '';

  meta = {
    description = "Structured asynchronous functions and cooperative Unix I/O for OCaml";
    homepage = "https://erratique.ch/software/affect";
    license = lib.licenses.isc;
    platforms = [ "x86_64-linux" ];
  };
}
