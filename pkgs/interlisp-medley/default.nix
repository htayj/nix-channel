{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  bashNonInteractive,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  maiko,
  ncurses,
  procps,
  which,
  xvfb-run,
}:

let
  # Upstream release pairing Medley 260810-634d092e with Maiko 260319-9259716e.
  releaseTag = "medley-260810-634d092e_260319-9259716e";

  # Upstream-built boot images; the source repository does not contain them.
  loadups = fetchurl {
    url = "https://github.com/Interlisp/medley/releases/download/${releaseTag}/medley-260810-634d092e-loadups.tgz";
    hash = "sha256-KfCGf8BK1EbHv7htCj0KpmgjleEpnipcp93pNtm11yw=";
  };

  # maiko first: medley.command takes the first lde on PATH, and lde starts
  # the ldex beside it.  The rest are the tools the launcher calls.
  runtimePath = lib.makeBinPath [
    maiko
    coreutils
    gnugrep
    gnused
    gawk
    procps
    ncurses
    which
  ];
  sh = "${bashNonInteractive}/bin/sh";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "interlisp-medley";
  version = "260810-634d092e";

  src = fetchFromGitHub {
    owner = "Interlisp";
    repo = "medley";
    rev = "634d092ed802314ada447878418686fbfeeb3048";
    fetchSubmodules = true;
    hash = "sha256-JdE1EAymIWvUsG5qee8ZuRCuu25JpWOAARHzxTisbbQ=";
  };

  dontConfigure = true;
  dontBuild = true;
  # Lisp sources, compiled Lisp files and the launcher are installed unchanged.
  dontPatchShebangs = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    tree=$out/libexec/medley
    doc=$out/share/doc/interlisp-medley
    mkdir -p $tree/scripts $tree/docs $tree/fonts/postscriptfonts \
      $tree/internal $tree/unicode/xerox $tree/loadups $doc $out/bin

    for d in sources CLTL2 library lispusers clos rooms greetfiles doctools; do
      cp -a $d $tree/$d
    done
    cp -a scripts/medley $tree/scripts/medley
    cp -a docs/dinfo $tree/docs/dinfo
    cp -a fonts/medleydisplayfonts $tree/fonts/medleydisplayfonts
    cp -a fonts/postscriptfonts/c0 $tree/fonts/postscriptfonts/c0

    # Top-level files only: internal/envos, internal/loadups and
    # internal/venuesysouts stay out.
    find internal -maxdepth 1 -type f -exec cp -a -t $tree/internal {} +

    # Xerox character tables only; the vendor, East Asian and ISO 8859
    # tables, the XCCStoUni binary and the Xerox PDF stay out.
    find unicode/xerox -maxdepth 1 -type f \( -name '*.TXT' -o -name '*.txt' \) \
      -exec cp -a -t $tree/unicode/xerox {} +

    # apps.sysout holds optional applications outside this package's scope.
    tar -xzf ${loadups} -C $tree/loadups --strip-components=2 --no-same-owner \
      medley/loadups/full.sysout medley/loadups/lisp.sysout

    install -m644 LICENSE $tree/LICENSE
    install -m644 LICENSE $doc/LICENSE
    install -m644 ${maiko.src}/LICENSE $doc/Maiko-LICENSE
    install -m644 ${maiko.src}/NOTICE $doc/Maiko-NOTICE

    cat > $doc/PROVENANCE <<'EOF'
    Medley source: ${finalAttrs.src.rev}
    Maiko virtual machine: nixpkgs maiko ${maiko.version}, built from source
    for X11.
    Boot images: upstream medley-260810-634d092e-loadups.tgz, release
    ${releaseTag}
    Boot archive hash: ${loadups.outputHash}
    full.sysout and lisp.sysout are upstream-built images, not bootstrapped
    from source by this package.
    Medley MIT LICENSE and Maiko MIT LICENSE/NOTICE cover the shipped
    runtime; file-level notices are retained.
    Excluded: apps.sysout, Notecards, LOOPS, vendor/eastasia/iso8859 Unicode
    tables, the XCCStoUni binary, the Xerox PDF and all font trees other than
    medleydisplayfonts and postscriptfonts/c0.
    EOF

    cat > $out/bin/medley <<'EOF'
    #!${sh}
    set -eu
    # medley.command reads an inherited MAIKODIR as a Maiko build tree and
    # exits when it is not one.
    unset MAIKODIR
    export PATH='${runtimePath}'"''${PATH:+:$PATH}"
    exec ${sh} ${placeholder "out"}/libexec/medley/scripts/medley/medley.command --full "$@"
    EOF
    chmod 555 $out/bin/medley

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ xvfb-run ];
  installCheckPhase = ''
    runHook preInstallCheck

    tree=$out/libexec/medley
    test ! -e $tree/loadups/apps.sysout
    test ! -e $tree/unicode/xerox/XCCStoUni
    test -z "$(find $tree/internal -mindepth 1 -type d)"

    export HOME=$TMPDIR/medley-home SHELL=/bin/sh
    # The image's UNIX-GETENV finds no variable whose name has an underscore.
    export MEDLEYSMOKE=$TMPDIR/medley-smoke
    mkdir -p $HOME $MEDLEYSMOKE

    # Typed into the booted image through REM.CM, as upstream's loadup
    # scripts do.  The file holds only the factors; Lisp writes the products.
    # (LOGOUT NIL 0) saves the virtual memory and exits; the rest of the PROG
    # runs when that saved image is continued.
    cat > $MEDLEYSMOKE/smoke.cm <<'EOF'
    "
    (PROG ((S (IL:OPENSTREAM (IL:CONCAT (QUOTE {DSK}) (IL:UNIX-GETENV (QUOTE MEDLEYSMOKE)) (IL:L-CASE (QUOTE /marker))) (QUOTE IL:OUTPUT))))
      (IL:PRIN1 (IL:ITIMES 6007 7919) S)
      (IL:CLOSEF S)
      (IL:LOGOUT NIL 0)
      (SETQ S (IL:OPENSTREAM (IL:CONCAT (QUOTE {DSK}) (IL:UNIX-GETENV (QUOTE MEDLEYSMOKE)) (IL:L-CASE (QUOTE /resumed))) (QUOTE IL:OUTPUT)))
      (IL:PRIN1 (IL:ITIMES 6011 7919) S)
      (IL:CLOSEF S)
      (IL:LOGOUT T 0))
    (IL:LOGOUT T 1)
    "
    EOF

    # Only an exit status of 0 from the image counts; a timeout is a failure.
    boot() {
      log=$MEDLEYSMOKE/$1.log
      shift
      rc=0
      MAIKODIR=/nonexistent timeout 120 xvfb-run -a -s '-screen 0 1280x1024x24' \
        $out/bin/medley --config - --greet - --geometry 1024x768 \
          --screensize 1024x768 --noscroll "$@" > $log 2>&1 || rc=$?
      cat $log
      test "$rc" = 0
    }

    # Boot from a tree that looks like the store: read-only, epoch mtimes.
    find $out -exec touch -h -d @1 {} +
    chmod -R a-w $out

    boot fresh --rem.cm $MEDLEYSMOKE/smoke.cm
    test "$(cat $MEDLEYSMOKE/marker)" = 47569433
    grep -qF '"${maiko}/bin/lde" "'$tree/loadups/full.sysout'"' $MEDLEYSMOKE/fresh.log
    test -s $HOME/il/vmem/lisp.virtualmem
    test ! -e $MEDLEYSMOKE/resumed

    boot continued --continue
    test "$(cat $MEDLEYSMOKE/resumed)" = 47601109
    grep -qF '"${maiko}/bin/lde" "'$HOME/il/vmem/lisp.virtualmem'"' $MEDLEYSMOKE/continued.log

    chmod -R u+w $out

    runHook postInstallCheck
  '';

  meta = {
    description = "Medley Interlisp environment on the Maiko virtual machine";
    longDescription = ''
      Medley is a graphical Interlisp and Common Lisp development environment
      with the historical Lisp machine interface.  This package installs the
      pinned Medley sources and free runtime assets and runs them on the
      nixpkgs Maiko X11 virtual machine.  The full and lisp boot images are
      the hash-pinned upstream release images.  Saved virtual memory and
      configuration live under HOME/il or LOGINDIR.  `medley` starts a fresh
      full image; `medley --continue` resumes saved virtual memory.

      An X11 display is required.  The launcher's --man and --tag options do
      not work from the read-only store, --vnc needs an Xtigervnc that this
      package does not provide, and an inherited MAIKODIR is ignored.
    '';
    homepage = "https://interlisp.org";
    license = lib.licenses.mit;
    # Lisp sources plus upstream-built Maiko bytecode: the two boot images
    # and the compiled .LCOM/.DFASL files in the source tree.
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "medley";
  };
})
