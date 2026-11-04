{ lib
, stdenv
, fetchFromGitHub
, ncurses
, coreutils
, runtimeShell
}:

stdenv.mkDerivation {
  pname = "hydra-slayer";
  version = "18.3";

  # Hydra Slayer lives in the NotEye repository; only its console build is used.
  src = fetchFromGitHub {
    owner = "zenorogue";
    repo = "noteye";
    rev = "55bb69d716a9fb269c6364f9df89d4bc260cb1a1";
    hash = "sha256-QUI+5yChNJzRTcxWOJUon5ESIqg6zQs5yVPbew6AgOI=";
  };

  buildInputs = [ ncurses ];

  # The Makefile links the historical libcurses alias.
  postPatch = ''
    substituteInPlace hydra/Makefile --replace-fail -lcurses -lncurses
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    make -C hydra hydra
    runHook postBuild
  '';

  # The game reads and writes its saves, scores and logs in the working
  # directory, so the launcher runs it from a per-user state directory.
  installPhase = ''
    runHook preInstall

    install -Dm555 hydra/hydra $out/libexec/hydra
    install -Dm444 LICENSE $out/share/doc/hydra-slayer/COPYING

    mkdir -p $out/bin
    cat > $out/bin/hydra <<'EOF'
    #!${runtimeShell}
    set -eu
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    state_root="''${XDG_STATE_HOME:-''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/hydra-slayer"
    ${coreutils}/bin/mkdir -p "$state_root"
    cd "$state_root"
    exec ${placeholder "out"}/libexec/hydra "$@"
    EOF
    chmod 555 $out/bin/hydra

    runHook postInstall
  '';

  meta = {
    description = "Console roguelike about cutting Hydra heads";
    longDescription = ''
      Hydra Slayer is a standalone console roguelike in which the player cuts
      heads from regenerating hydras.  This package builds the ncurses game
      from the NotEye repository without the NotEye graphical frontend.  The
      hydra launcher keeps saves, scores and logs in
      $XDG_STATE_HOME/hydra-slayer (default ~/.local/state/hydra-slayer).
    '';
    homepage = "https://github.com/zenorogue/noteye";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hydra";
  };
}
