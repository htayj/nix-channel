{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  sbcl,
  openssl,
}:

let
  sbclWithLibraries = sbcl.withPackages (ps: with ps; [
    alexandria
    bordeaux-threads
    cl-interpol
    cl-ppcre
    dexador
    jonathan
    local-time
    quri
    str
    unix-opts
  ]);
in
stdenv.mkDerivation {
  pname = "qbcl";
  # qbcl.asd declares 0.1.0; upstream has no tags.  The Guix channel pins
  # 167edfe, whose login cannot read the session cookie from the list that
  # this fast-http returns for Set-Cookie; upstream fixed that in 1a630f7.
  version = "0.1.0-unstable-2026-08-29";

  src = fetchFromGitHub {
    owner = "htayj";
    repo = "qbcl";
    rev = "29717b1dc32066cb0416c1b99431a6d93baef50e";
    hash = "sha256-pscUinMh+O3osgtjYuyvLfBGqJE13TYe9BhelSTFK1c=";
  };

  nativeBuildInputs = [
    makeWrapper
    sbclWithLibraries
  ];

  # Upstream commits a prebuilt executable; build from source instead.
  postPatch = ''
    rm qbcl
  '';

  dontConfigure = true;
  # The program is the SBCL runtime with the Lisp core appended; stripping or
  # rewriting the ELF file would drop or misplace the core.
  dontStrip = true;
  dontPatchELF = true;

  # Runtime options are saved so the SBCL runtime leaves every argument,
  # including --help and --version, to the program.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR/home
    export QBCL_IMAGE=$TMPDIR/image/qbcl
    mkdir -p "$HOME" "$TMPDIR/image"
    cat > "$TMPDIR/build.lisp" <<'EOF'
    (require :asdf)
    (asdf:load-asd (truename "qbcl.asd"))
    (asdf:load-system "qbcl")
    (sb-ext:save-lisp-and-die
     (uiop:getenv "QBCL_IMAGE")
     :executable t
     :save-runtime-options t
     :compression (and (member :sb-core-compression *features*) t)
     :toplevel (lambda ()
                 (sb-ext:disable-debugger)
                 (let ((code (qbcl:main (rest sb-ext:*posix-argv*))))
                   (uiop:quit (if (integerp code) code 0)))))
    EOF
    sbcl --noinform --non-interactive --no-userinit --no-sysinit \
      --load "$TMPDIR/build.lisp"
    test -x "$QBCL_IMAGE"
    runHook postBuild
  '';

  # The saved image reopens libssl and libcrypto by soname when it starts.
  installPhase = ''
    runHook preInstall
    install -Dm755 "$QBCL_IMAGE" $out/libexec/qbcl/qbcl
    makeWrapper $out/libexec/qbcl/qbcl $out/bin/qbcl \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ openssl ]}
    install -Dm644 -t $out/share/doc/qbcl README.md
    runHook postInstall
  '';

  # Starting the program at all proves that the saved image finds OpenSSL.
  # The torrent inspector is the one command that needs no qBittorrent.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/qbcl version > "$TMPDIR/version.txt"
    grep -qxF 'qbcl 0.1.0' "$TMPDIR/version.txt"
    $out/bin/qbcl help > "$TMPDIR/help.txt"
    grep -qxF 'Usage: qbcl [command] [options] [args...]' "$TMPDIR/help.txt"
    printf 'd8:announce20:http://tracker/x.ann4:infod6:lengthi1048576e4:name8:demo.bin12:piece lengthi262144e6:pieces20:AAAAAAAAAAAAAAAAAAAAee' \
      > "$TMPDIR/demo.torrent"
    $out/bin/qbcl lstor "$TMPDIR/demo.torrent" > "$TMPDIR/lstor.txt"
    grep -qxF 'Name:         demo.bin' "$TMPDIR/lstor.txt"
    grep -qxF 'Tracker:      http://tracker/x.ann' "$TMPDIR/lstor.txt"
    grep -qxF 'Size:         1.00 MiB' "$TMPDIR/lstor.txt"
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line qBittorrent controller";
    homepage = "https://github.com/htayj/qbcl";
    license = lib.licenses.gpl2Plus;
    mainProgram = "qbcl";
    platforms = [ "x86_64-linux" ];
  };
}
