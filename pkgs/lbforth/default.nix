{ lib, stdenv, fetchFromGitHub, sbcl }:

stdenv.mkDerivation (finalAttrs: {
  pname = "lbforth";
  # Upstream has no release tags.
  version = "0-unstable-2023-02-13";

  # The lisp submodule is the forth-metacompiler used for bootstrapping
  # (40b99c09628f616d94649009ba9894340088d77c).
  src = fetchFromGitHub {
    owner = "larsbrinkhoff";
    repo = "lbForth";
    rev = "912433b150b64252070116a5fd5c1a29ff29b26d";
    fetchSubmodules = true;
    hash = "sha256-CSIN7cPua01TcGw6CUYNv2jSie8riPzysf2ArO6c+0c=";
  };

  nativeBuildInputs = [ sbcl ];

  enableParallelBuilding = false;

  postPatch = ''
    patchShebangs lisp/lisp.sh targets/c/run.sh test

    # The bootstrap comes from the source; never let make fetch it.
    substituteInPlace targets/c/bootstrap.mk \
      --replace-fail 'git submodule update --init' 'test -f lisp/meta.lisp'

    # Embed the configured system directory instead of the source tree.
    substituteInPlace targets/c/forth.mk \
      --replace-fail 's\" src/\"' 's\" $(sysdir)/\"'

    # Search-path entries are dictionary names truncated to 15 bytes, so an
    # absolute store path cannot be a search path.  Open files below sysdir
    # directly before trying the remaining (current directory) path.
    substituteInPlace src/kernel.fth \
      --replace-fail '   s" src/" searched \ UGLY HACK' "" \
      --replace-fail '   sysdir searched' "" \
      --replace-fail ": search-file   ['] search-paths ['] ?open traverse-wordlist ?error ;" \
        ": search-file 2dup sysdir here 0 +string +string r/o open-file ?include if ['] search-paths ['] ?open traverse-wordlist ?error else drop then ;"
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    # Stage 1: SBCL metacompiles the bootstrap kernel against the sources.
    make b-forth TARGET=c M32= sysdir=src
    # Stage 2: the self-hosted kernel, embedding the installed system path.
    make c-forth TARGET=c M32= sysdir=$out/share/lbForth
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 c-forth $out/bin/forth
    mkdir -p $out/share/lbForth
    cp -r src/. $out/share/lbForth/
    cp -r lib targets $out/share/lbForth/
    install -Dm644 -t $out/share/doc/lbforth LICENSE README.md INSTALL
    runHook postInstall
  '';

  # Upstream's native host suite, run against the installed system files.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    make test-standard test-image test-lib TARGET=c M32= sysdir=$out/share/lbForth
    (cd "$TMPDIR" && echo '2 3 + . bye' | $out/bin/forth) | grep -F '5'
    runHook postInstallCheck
  '';

  meta = {
    description = "Self-hosted Forth interpreter";
    longDescription = ''
      lbForth implements a subset of Forth94 and can regenerate its kernel
      from Forth source.  This package bootstraps the portable C target with
      the pinned Common Lisp metacompiler, then builds the self-hosted
      interpreter, which loads its system wordsets from the store.
    '';
    homepage = "https://github.com/larsbrinkhoff/lbForth";
    license = lib.licenses.gpl3Only;
    mainProgram = "forth";
    platforms = [ "x86_64-linux" ];
  };
})
