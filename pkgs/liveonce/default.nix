{
  lib,
  stdenv,
  fetchurl,
  coreutils,
  ncurses,
  runtimeShell,
  util-linux,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "liveonce";
  # The homepage names 005 "the most recent version".
  version = "005";

  # www.zincland.com serves a certificate for another host name, so the
  # homepage's own HTTP link is the canonical location.
  src = fetchurl {
    url = "http://www.zincland.com/7drl/liveonce/liveonce${finalAttrs.version}.tar.gz";
    hash = "sha256-QSZS5BNkqSHRRAYw16z1nmPs5eAPtt5i4MzYNj2GfuI=";
  };

  # The archive has no top-level directory.
  unpackPhase = ''
    runHook preUnpack
    mkdir liveonce
    tar -xzf $src -C liveonce
    runHook postUnpack
  '';
  sourceRoot = "liveonce";

  # Build the curses port without SDL, read text.txt and the maps from
  # LIVEONCE_DATADIR, and declare usleep, sleep, unlink and the mem*
  # functions.  Same patch as the Guix channel.
  patches = [ ./liveonce-curses-build.patch ];

  # Remove the prebuilt Linux and Windows programs, the Microsoft and SDL
  # DLLs, the PDCurses libraries, the alphabet*.bmp fonts (screen captures
  # of unclear licence) and the SDL port, which is not built.
  prePatch = ''
    rm -r linux linux_curses windows windows_curses \
      src/gfx src/wincurses src/gfx_sdl.cpp src/gfx_sdl.h
  '';

  buildInputs = [ ncurses ];
  nativeInstallCheckInputs = [ coreutils util-linux ];

  dontConfigure = true;

  # enummaker generates glbdef.cpp and glbdef.h from source.txt.
  buildPhase = ''
    runHook preBuild
    make -C src/support/enummaker CXX="$CXX"
    make -C src/linuxport premake
    make -C src/linuxport CXX="$CXX" LIVEONCE_DATADIR=$out/share/liveonce
    runHook postBuild
  '';

  # The game reads its data from the store and writes only valley.sav,
  # relative to its working directory, so the launcher enters the state
  # directory first.
  installPhase = ''
    runHook preInstall
    install -Dm755 src/linuxport/liveonce $out/libexec/liveonce/liveonce
    install -Dm644 -t $out/share/liveonce \
      src/text.txt src/rooms/valley.map src/rooms/piecelist.map
    # LICENSE.TXT carries the BSD notice for the game, the MT19937 notice
    # for mt19937ar.c and the public domain dedication of the maps.
    install -Dm644 -t $out/share/doc/liveonce LICENSE.TXT README.TXT
    mkdir -p $out/bin
    cat > $out/bin/liveonce <<'EOF'
    #!@runtimeShell@
    set -eu
    case "''${XDG_DATA_HOME:-}" in
      /*) state="$XDG_DATA_HOME/liveonce" ;;
      *) state="''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share/liveonce" ;;
    esac
    @mkdir@ -p -- "$state"
    cd -- "$state"
    export TERMINFO_DIRS="@terminfo@''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec @libexec@/liveonce "$@"
    EOF
    substituteInPlace $out/bin/liveonce \
      --subst-var-by runtimeShell ${runtimeShell} \
      --subst-var-by mkdir ${coreutils}/bin/mkdir \
      --subst-var-by terminfo ${ncurses}/share/terminfo \
      --subst-var-by libexec $out/libexec/liveonce
    chmod 555 $out/bin/liveonce
    runHook postInstall
  '';

  # Play two sessions on an 80x30 pseudo-terminal.  The first starts a new
  # game (Timmy's welcome), shows the welcome message with w, and quits
  # with Q, which saves valley.sav in the state directory.  The second
  # must load that save, which the game deletes once loaded, so the new
  # game welcome does not appear before the requested message; quitting
  # saves again.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home TERM=xterm LC_ALL=C ESCDELAY=100
    unset XDG_DATA_HOME TERMINFO_DIRS
    mkdir -p "$HOME"
    state=$HOME/.local/share/liveonce
    save=$state/valley.sav
    welcome='Welcome to You Only Live Once!'

    # wait_for FILE TEXT: wait up to 30 seconds for TEXT in FILE.
    wait_for() {
      tries=0
      until tr -d '\000' < "$1" | grep -qF -- "$2"; do
        tries=$((tries + 1))
        [ "$tries" -le 300 ] || return 1
        sleep 0.1
      done
    }

    # feed RAW SESSION: type keys once each screen has been drawn.
    feed() {
      wait_for "$1" 'You are Timmy.' || return 1
      if [ "$2" = second ]; then
        test ! -e "$save" || return 1
      fi
      printf w
      wait_for "$1" 'Welcome Message:' || return 1
      printf '\033'
      sleep 1
      printf Q
      wait_for "$1" 'Done.' || return 1
      test -s "$save" || return 1
      # The game drops one pending key before waiting for the final one.
      sleep 0.5
      printf ' '
    }

    play() {
      raw=$TMPDIR/$1.raw
      : > "$raw"
      { feed "$raw" "$1" || touch "$TMPDIR/$1.failed"; } \
        | timeout 120 script -qefc \
            "stty rows 30 cols 80; exec $out/bin/liveonce" /dev/null > "$raw" \
        || exit 1
      test ! -e "$TMPDIR/$1.failed" || exit 1
      tr -d '\000' < "$raw" > "$TMPDIR/$1.screen"
      grep -qF 'Saving...' "$TMPDIR/$1.screen" || exit 1
      grep -qF 'Hit a key to quit.' "$TMPDIR/$1.screen" || exit 1
    }

    play first
    test -s "$save"
    # The new game welcome comes before the requested message.
    first=$(cat "$TMPDIR/first.screen")
    case "''${first%%Welcome Message:*}" in *"$welcome"*) ;; *) exit 1 ;; esac

    play second
    test -s "$save"
    second=$(cat "$TMPDIR/second.screen")
    case "''${second%%Welcome Message:*}" in *"$welcome"*) exit 1 ;; esac
    test "$(ls -A "$state")" = valley.sav
    runHook postInstallCheck
  '';

  meta = {
    description = "Seven Day Roguelike about a village's successive heroes";
    longDescription = ''
      You Only Live Once is Jeff Lait's terminal roguelike for the 2005
      Seven Day Roguelike challenge.  When the current villager dies, play
      continues as the next inhabitant of the mountain valley.  This package
      builds the curses port from source without the prebuilt programs, the
      SDL port or its bitmap fonts.  The saved game is kept in
      $XDG_DATA_HOME/liveonce/valley.sav, falling back to
      ~/.local/share/liveonce.  The game needs an 80-column terminal with at
      least 30 lines.
    '';
    homepage = "http://www.zincland.com/7drl/liveonce/";
    # Game sources and text: 3-clause BSD (Jeff Lait); mt19937ar.c: 3-clause
    # BSD (Matsumoto and Nishimura); maps: public domain.  See
    # share/doc/liveonce/LICENSE.TXT.
    license = with lib.licenses; [ bsd3 publicDomain ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "liveonce";
  };
})
