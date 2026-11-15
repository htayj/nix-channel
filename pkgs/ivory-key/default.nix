{
  lib,
  stdenv,
  fetchFromGitHub,
  sbcl,
}:

stdenv.mkDerivation {
  pname = "ivory-key";
  # ivory-key.asd declares 0.1.0; upstream has no tags.
  version = "0.1.0-unstable-2026-08-14";

  src = fetchFromGitHub {
    owner = "htayj";
    repo = "ivory-key";
    rev = "fbe557a9786ef4cf1a185f96913c3bd51d1c0231";
    hash = "sha256-DqqPWRt1iB1kbyWsfCPYvquU9zQMLb1nWnnYVDlRZV4=";
  };

  nativeBuildInputs = [ sbcl ];

  dontConfigure = true;
  # The program is the SBCL runtime with the Lisp core appended; stripping or
  # rewriting the ELF file would drop or misplace the core.
  dontStrip = true;
  dontPatchELF = true;

  # The system depends only on UIOP, which ships with SBCL's ASDF.  Runtime
  # options are saved so the SBCL runtime leaves every argument, including
  # --help and --version, to the program.  SIGPIPE keeps its default action:
  # with SBCL's handler a report written to a pipe whose reader has gone
  # blocks forever instead of ending the program.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR/home
    export IVORY_KEY_IMAGE=$TMPDIR/image/ivory-key
    mkdir -p "$HOME" "$TMPDIR/image"
    cat > "$TMPDIR/build.lisp" <<'EOF'
    (require :asdf)
    (asdf:load-asd (truename "ivory-key.asd"))
    (asdf:load-system "ivory-key")
    (sb-ext:save-lisp-and-die
     (uiop:getenv "IVORY_KEY_IMAGE")
     :executable t
     :save-runtime-options t
     :compression (and (member :sb-core-compression *features*) t)
     :toplevel (lambda ()
                 (sb-ext:disable-debugger)
                 (sb-sys:enable-interrupt sb-unix:sigpipe :default)
                 (uiop:quit (ivory-key.cli:main))))
    EOF
    sbcl --noinform --non-interactive --no-userinit --no-sysinit \
      --load "$TMPDIR/build.lisp"
    test -x "$IVORY_KEY_IMAGE"
    runHook postBuild
  '';

  # Upstream's hermetic suite.  Its optional backend evidence looks for
  # xkbcli, kanata and qmk on PATH and records them as skipped when absent.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    sbcl --noinform --non-interactive --no-userinit --no-sysinit \
      --eval '(require :asdf)' \
      --eval '(asdf:load-asd (truename "ivory-key.asd"))' \
      --eval '(asdf:test-system "ivory-key/tests")' \
      | tee "$TMPDIR/tests.log"
    grep -qE '^[1-9][0-9]* Ivory Key tests passed\.$' "$TMPDIR/tests.log"
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 "$IVORY_KEY_IMAGE" $out/bin/ivory-key
    install -Dm644 -t $out/share/doc/ivory-key README.md LICENSE
    cp -r docs $out/share/doc/ivory-key/docs
    mkdir -p $out/share/ivory-key
    cp -r devices layouts realizations topologies manna-cadet-project.ivory \
      $out/share/ivory-key/
    runHook postInstall
  '';

  # Runs the installed program on the shipped example project: usage, syntax
  # check of every example, a full level report, and the same report written
  # to a pipe whose reader has already exited, which must end the program
  # with SIGPIPE (128 + 13).
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    examples=$out/share/ivory-key
    $out/bin/ivory-key help > "$TMPDIR/help.txt"
    grep -qxF 'Usage: ivory-key COMMAND [ARGUMENTS...]' "$TMPDIR/help.txt"
    $out/bin/ivory-key check $examples/*/*.ivory
    $out/bin/ivory-key levels --project $examples/manna-cadet-project.ivory \
      --composition manna-cadet-linux > "$TMPDIR/levels.txt"
    grep -qxF 'levels for manna-cadet' "$TMPDIR/levels.txt"
    exec 3> >(:)
    wait $!
    status=0
    timeout 60 $out/bin/ivory-key levels \
      --project $examples/manna-cadet-project.ivory \
      --composition manna-cadet-linux >&3 || status=$?
    exec 3>&-
    if [ "$status" != 141 ]; then
      echo "closed pipe: expected exit status 141, got $status" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Declarative keyboard-layout compiler";
    homepage = "https://github.com/htayj/ivory-key";
    license = lib.licenses.gpl3Plus;
    mainProgram = "ivory-key";
    platforms = [ "x86_64-linux" ];
  };
}
