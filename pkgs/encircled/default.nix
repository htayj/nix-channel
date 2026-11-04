{
  lib,
  stdenv,
  fetchurl,
  unzip,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "encircled";
  # The archive's changelog and terminal-size check identify 0.4.3; its
  # separate readme still says 0.2.
  version = "0.4.3";

  src = fetchurl {
    url = "https://dl.dropbox.com/s/ldw5k988ryubtli/encircled.zip";
    name = "encircled-${finalAttrs.version}.zip";
    hash = "sha256-X8MVfAuYazr2LF0ZYgGHAWj86gSGg2JvXQKOHjhbmeI=";
  };

  sourceRoot = "encircled";

  nativeBuildInputs = [ unzip ];
  buildInputs = [ ncurses ];

  # Drop the archive's prebuilt Windows binaries, and bound the postmortem
  # report filename read into its 30-byte buffer.
  postPatch = ''
    rm -f encircled.exe pdcurses.dll libgcc_s_dw2-1.dll libstdc++-6.dll
    substituteInPlace encircled.cpp \
      --replace-fail 'getstr(fname);' 'getnstr(fname, sizeof fname - 1);'
  '';

  dontConfigure = true;

  # Upstream's KILL_ESCAPE define is unused.
  buildPhase = ''
    runHook preBuild
    $CXX -std=c++11 -O3 encircled.cpp -o encircled -lncurses
    runHook postBuild
  '';

  # The only file the game writes is an explicitly requested postmortem
  # report in the working directory, so no launcher is needed.
  installPhase = ''
    runHook preInstall
    install -Dm555 encircled $out/bin/encircled
    install -d $out/share/doc/encircled
    cat > $out/share/doc/encircled/SOURCE-NOTICE <<'EOF'
    Encircled 0.4.3 is built from the author-linked archive
    https://dl.dropbox.com/s/ldw5k988ryubtli/encircled.zip
    (465808 bytes, SHA-256
    5fc3157c0b986b3af62c5d196201870168fcea048683626f5d028e1e385b99e2).

    encircled.cpp line 46 states:
    // This code is public domain. Do anything you want with it...

    Its four keypad constants are copied from PDCurses, whose core is in
    the public domain.

    The report filename prompt uses getnstr bounded to the buffer instead
    of getstr.  The archive's Windows binaries, Makefile, readme and
    changelog are not installed.
    EOF
    runHook postInstall
  '';

  meta = {
    description = "Tactical positioning roguelike for a color terminal";
    longDescription = ''
      Encircled is a standalone ASCII roguelike written for a 60-hour
      challenge.  Attacks happen automatically when the terrain around the
      wielder and target matches the weapon's patterns.  It requires an 80 by
      30 color terminal.  An explicitly requested postmortem report is
      written to the working directory; there is no save or load.
    '';
    homepage = "https://kleinroguelikes.blogspot.com/p/games.html";
    license = lib.licenses.publicDomain;
    platforms = [ "x86_64-linux" ];
    mainProgram = "encircled";
  };
})
