{
  lib,
  stdenv,
  fetchFromGitHub,
  sbcl,
}:

stdenv.mkDerivation {
  pname = "modus";
  # modus.asd declares 0.2.0; upstream has no tags.
  version = "0.2.0-unstable-2026-08-12";

  src = fetchFromGitHub {
    owner = "modus-lisp";
    repo = "modus";
    rev = "501f2ee2069e98210627e53ce487f23eabca9032";
    hash = "sha256-0pU84qYd66VXXm49K8uSR6pMj6EZJNXU5YLKwAX1uZY=";
  };

  nativeBuildInputs = [ sbcl ];

  # The image writer marks its output executable through a fixed FHS path.
  postPatch = ''
    substituteInPlace mvm/build-generic-cli.lisp \
      --replace-fail '"/bin/chmod"' "\"$(type -P chmod)\""
  '';

  dontConfigure = true;
  # The executable is a hand-assembled static ELF image: one RWE LOAD segment
  # whose memory size far exceeds its file size, and no dynamic section.
  dontStrip = true;
  dontPatchELF = true;

  # Upstream's hosted x86-64 Linux image build: SBCL cross-compiles Modus's
  # own sources into a standalone ELF.  MODUS_NO_JIT is upstream's documented
  # rollback to the interpreter image; the default JIT image prints translator
  # diagnostics on stdout at every start, which breaks silent --eval and exact
  # script output.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    export MODUS_NO_JIT=1
    export MODUS_CLI_OUT=$PWD/modus-cli
    sbcl --dynamic-space-size 4096 --script mvm/build-generic-cli.lisp
    test -x modus-cli
    runHook postBuild
  '';

  # Upstream resolves the Quicklisp-style setup file and its bundled offline
  # systems against the working directory; default that root to the installed
  # assets.  It is a DEFVAR, so a caller may bind another root first.
  installPhase = ''
    runHook preInstall
    install -Dm555 modus-cli $out/bin/modus
    install -Dm644 -t $out/share/modus/modus-quicklisp modus-quicklisp/setup.lisp
    install -Dm644 -t $out/share/modus/systems systems/sha1.tar
    substituteInPlace $out/share/modus/modus-quicklisp/setup.lisp \
      --replace-fail '(defvar *modus-quicklisp-root* "")' \
                     "(defvar *modus-quicklisp-root* \"$out/share/modus/\")"
    install -Dm644 -t $out/share/doc/modus LICENSE README.md QUICKLOAD.md
    mkdir -p $out/share/doc/modus/third-party-notices
    tar -xOf systems/sha1.tar sha1-20211020-git/LICENSE.txt \
      > $out/share/doc/modus/third-party-notices/sha1-LICENSE.txt
    runHook postInstall
  '';

  # Upstream's test suites boot images under QEMU.  Run the installed
  # evaluator instead: an --eval error exits nonzero, and --eval alone prints
  # nothing.  Loading the bundled sha1 system proves the installed root.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    run() {
      $out/bin/modus --noinform --no-userinit --no-sysinit --non-interactive "$@"
    }
    run --eval '(unless (= (+ 1 2) 3) (error "self-check failed"))' \
      > "$TMPDIR/silent.txt"
    test ! -s "$TMPDIR/silent.txt"
    if run --eval '(error "expected failure")' > /dev/null 2>&1; then
      echo 'an --eval error did not fail the process' >&2
      exit 1
    fi
    run --eval "(load \"$out/share/modus/modus-quicklisp/setup.lisp\")" \
      --eval '(ql:quickload :sha1)' \
      --eval '(print (sha1:sha1-hex "abc"))' > "$TMPDIR/sha1.txt"
    grep -qF '"A9993E364706816ABA3E25717850C26C9CD0D89D"' "$TMPDIR/sha1.txt"
    runHook postInstallCheck
  '';

  meta = {
    description = "Self-hosting Common Lisp implementation with a hosted command-line image";
    longDescription = ''
      Modus is a Common Lisp implementation that compiles to its own MVM
      bytecode and native code and can rebuild itself.  This package builds
      the hosted x86-64 Linux modus executable from source with SBCL.  It runs
      as an ordinary process with an SBCL-style command line (--eval, --load,
      --script, --non-interactive) and an interactive REPL.  The offline
      Quicklisp-style loader and its bundled sha1 system are installed under
      share/modus.  QEMU and bare-metal images are not included.
    '';
    homepage = "https://github.com/modus-lisp/modus";
    # Modus is MIT; the installed systems/sha1.tar is Apache 2.0.
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "modus";
    # The build emits an x86-64 Linux ELF image only.
    platforms = [ "x86_64-linux" ];
  };
}
