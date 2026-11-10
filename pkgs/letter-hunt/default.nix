{
  lib,
  stdenv,
  fetchurl,
  coreutils,
  diffutils,
  ncurses,
  runtimeShell,
  util-linux,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "letter-hunt";
  # letterhunt002 is the homepage's "Bug fix Release", the most recent version.
  version = "002";

  # www.zincland.com serves a certificate for another host name, so the
  # homepage's own HTTP link is the canonical location.
  src = fetchurl {
    url = "http://www.zincland.com/7drl/letterhunt/letterhunt${finalAttrs.version}.tar.gz";
    hash = "sha256-xTOYZYgS3GqpMAdI9foPiWZdaS7hXa+or0ZP8IpvUFk=";
  };

  # The archive has no top-level directory.
  unpackPhase = ''
    runHook preUnpack
    mkdir letterhunt
    tar -xzf $src -C letterhunt
    runHook postUnpack
  '';
  sourceRoot = "letterhunt";

  # Build the curses port without SDL, read text.txt, the room pieces and the
  # word list from LETTERHUNT_DATADIR, and declare usleep, sleep, unlink and
  # the string functions.  Same patch as the Guix channel.
  patches = [ ./curses-build.patch ];

  # Remove the prebuilt Linux and Windows programs, the Microsoft and SDL
  # DLLs, the PDCurses libraries, the alphabet*.bmp fonts (screen captures of
  # unclear licence) and the SDL port, which is not built.
  prePatch = ''
    rm -r linux linux_curses windows windows_curses gfx \
      src/gfx src/wincurses src/gfx_sdl.cpp src/gfx_sdl.h
  '';

  buildInputs = [ ncurses ];

  dontConfigure = true;

  # enummaker generates glbdef.cpp and glbdef.h from source.txt.
  buildPhase = ''
    runHook preBuild
    make -C src/support/enummaker CXX="$CXX"
    make -C src/linuxport premake
    make -C src/linuxport CXX="$CXX" LETTERHUNT_DATADIR=$out/share/letter-hunt
    runHook postBuild
  '';

  # The game reads its data from the store and writes only letterhunt.sav and
  # hiscore.txt, relative to its working directory, so the launcher enters a
  # private state directory first.
  installPhase = ''
    runHook preInstall
    install -Dm755 src/linuxport/letterhunt $out/libexec/letter-hunt/letterhunt
    install -Dm644 src/text.txt $out/share/letter-hunt/text.txt
    install -Dm644 rooms/piecelist.map $out/share/letter-hunt/rooms/piecelist.map
    install -Dm644 wordlist/wordlist.txt $out/share/letter-hunt/wordlist/wordlist.txt
    # LICENSE.TXT carries the BSD notice for the game, the MT19937 notice for
    # mt19937ar.c and the public domain dedications of the maps and the Moby
    # word list.
    install -Dm644 -t $out/share/doc/letter-hunt LICENSE.TXT README.TXT

    mkdir -p $out/bin
    cat > $out/bin/letter-hunt <<'EOF'
    #!@shell@
    set -eu
    umask 077
    # Relative XDG_STATE_HOME values are ignored, as the XDG specification requires.
    case "''${XDG_STATE_HOME:-}" in
      /*) state_home=$XDG_STATE_HOME ;;
      *) state_home="''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state" ;;
    esac
    case "$state_home" in
      /*) ;;
      *) echo "letter-hunt: state directory must be absolute: $state_home" >&2; exit 1 ;;
    esac
    state=$(@coreutils@/bin/realpath -m -- "$state_home/letter-hunt")
    case "$state" in
      @storeDir@|@storeDir@/*)
        echo "letter-hunt: refusing state in the immutable store: $state" >&2; exit 1 ;;
    esac
    @coreutils@/bin/mkdir -p "$state_home"
    @coreutils@/bin/mkdir -p -m 700 "$state"
    if [ -L "$state" ] || [ ! -O "$state" ]; then
      echo "letter-hunt: $state is not a directory owned by the current user" >&2
      exit 1
    fi
    @coreutils@/bin/chmod 700 "$state"
    cd -- "$state"
    export TERMINFO_DIRS="@terminfo@''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec @out@/libexec/letter-hunt/letterhunt "$@"
    EOF
    substituteInPlace $out/bin/letter-hunt \
      --subst-var-by shell ${runtimeShell} \
      --subst-var-by coreutils ${coreutils} \
      --subst-var-by storeDir ${builtins.storeDir} \
      --subst-var-by terminfo ${ncurses}/share/terminfo \
      --subst-var-by out $out
    chmod 555 $out/bin/letter-hunt

    # Save/reload check in disposable pseudo-terminal sessions, also usable
    # after installation.
    install -Dm555 ${./smoke.sh} $out/libexec/letter-hunt/letter-hunt-smoke
    substituteInPlace $out/libexec/letter-hunt/letter-hunt-smoke \
      --subst-var-by shell ${runtimeShell} \
      --subst-var-by coreutils ${coreutils} \
      --subst-var-by diffutils ${diffutils} \
      --subst-var-by utillinux ${util-linux} \
      --subst-var-by out $out
    runHook postInstall
  '';

  # Upstream has no automated tests.  The smoke program plays a game on an
  # 80x30 pseudo-terminal, saves it, reloads it through the HOME fallback and
  # compares both saves.  It refuses a writable output, so the output is
  # read-only while it runs.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    chmod -R a-w $out
    $out/libexec/letter-hunt/letter-hunt-smoke | grep -qx LETTER_HUNT_RUNTIME_OK
    chmod -R u+w $out
    runHook postInstallCheck
  '';

  meta = {
    description = "Seven Day Roguelike about spelling words with captured letters";
    longDescription = ''
      Letter Hunt is Jeff Lait's terminal roguelike for the 2006 Seven Day
      Roguelike challenge.  The monsters are letters; capturing them in the
      right order spells words from a plain-text word list, which earns points
      and temporary power-ups.  This package builds the curses port from
      source without the prebuilt programs, the SDL port or its bitmap fonts.
      The saved game and high scores are kept in
      $XDG_STATE_HOME/letter-hunt, falling back to
      ~/.local/state/letter-hunt.  The game needs an 80-column terminal with
      at least 30 lines.
    '';
    homepage = "http://www.zincland.com/7drl/letterhunt/";
    # Game sources and text: 3-clause BSD (Jeff Lait); mt19937ar.c: 3-clause
    # BSD (Matsumoto and Nishimura); maps and Moby word list: public domain.
    # See share/doc/letter-hunt/LICENSE.TXT.
    license = with lib.licenses; [ bsd3 publicDomain ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "letter-hunt";
  };
})
