{
  lib,
  stdenv,
  fetchurl,
  ncurses,
  runtimeShell,
}:

stdenv.mkDerivation {
  pname = "corerl";
  # The article describes this dated source as the 1 KiB CoreRL release.
  version = "1kib-20131024";

  src = fetchurl {
    url = "https://www.roguelikeeducation.org/vault/core/1kcore.c";
    name = "corerl-1kib-20131024.c";
    hash = "sha256-BdVYRLMPv65yvYerniZTnPuCMuVAvA0M5QsE1tE2niQ=";
  };

  dontUnpack = true;
  dontConfigure = true;

  buildInputs = [ ncurses ];

  # Keep the upstream single-file build command; GNU89 accepts the source's
  # intentionally pre-C99 implicit declarations.
  buildPhase = ''
    runHook preBuild
    cp $src 1kcore.c
    $CC -std=gnu89 -O2 -o corerl 1kcore.c -lncurses
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 corerl $out/libexec/corerl/corerl
    install -Dm644 1kcore.c $out/share/doc/corerl/1kcore.c
    cat > $out/share/doc/corerl/NOTICE <<EOF
    CoreRL 1 KiB (1kib-20131024)
    Canonical source: https://www.roguelikeeducation.org/vault/core/1kcore.c
    Grant: Studio Tectorum, 'coreRL in 1kib', 2013-10-24
    https://www.roguelikeeducation.org/2.html
    "This version of the source is also released into the public domain"
    The complete, unmodified 1023-byte source is installed alongside this notice.
    EOF
    mkdir -p $out/bin
    cat > $out/bin/corerl <<EOF
    #!${runtimeShell}
    set -eu
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/corerl/corerl "\$@"
    EOF
    chmod 555 $out/bin/corerl
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/corerl/corerl
    test "$(wc -c < $out/share/doc/corerl/1kcore.c)" -eq 1023
    runHook postInstallCheck
  '';

  meta = {
    description = "One-kilobyte terminal roguelike";
    longDescription = ''
      CoreRL is a tiny curses roguelike from Studio Tectorum's Roguelike
      Education article, built from its complete 1023-byte public-domain C
      source with GNU89 and ncurses.  Use the arrow keys to move and q to
      quit.  Bumping into enemies removes them; moving onto the stairs
      advances to the next level.  The game keeps no save or configuration
      files.
    '';
    homepage = "https://www.roguelikeeducation.org/2.html";
    license = lib.licenses.publicDomain;
    platforms = lib.platforms.linux;
    mainProgram = "corerl";
  };
}
