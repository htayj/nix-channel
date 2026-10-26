{ lib, stdenv, fetchzip, runtimeShell, coreutils, ncurses }:

stdenv.mkDerivation (finalAttrs: {
  pname = "atrogue";
  version = "0.3.0";

  src = fetchzip {
    url = "mirror://sourceforge/atrogue/atrogue/atrogue-${finalAttrs.version}/atrogue-${finalAttrs.version}.tar.gz";
    hash = "sha256-z3I3fpA+tevBwXGuMypQ6KWzGyg6SQOEbf1vD6lfWtE=";
  };

  buildInputs = [ ncurses ];

  postPatch = ''
    # The direction table fills all 32 bytes, leaving no NUL for strchr().
    substituteInPlace stuff.c \
      --replace-fail 'static const char str[4 * 8]' 'static const char str[]'
    # Current ncurses keeps WINDOW opaque; read the cursor through its
    # accessor macros instead of struct fields.
    substituteInPlace message.c \
      --replace-fail 'move(stdscr->_cury, stdscr->_curx - 1)' 'move(getcury(stdscr), getcurx(stdscr) - 1)' \
      --replace-fail 'move(stdscr->_cury, stdscr->_curx + 1)' 'move(getcury(stdscr), getcurx(stdscr) + 1)'
    substituteInPlace stuff.c \
      --replace-fail 'old_cursorx = curscr->_curx; old_cursory = curscr->_cury;' 'old_cursorx = getcurx(curscr); old_cursory = getcury(curscr);'
  '';

  # itchconfig is not GNU configure; upstream supports the classical
  # Makefile, whose `devel' target runs clean, config and link serially.
  dontConfigure = true;
  enableParallelBuilding = false;
  buildFlags = [ "devel" ];
  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];
  # Public inline helpers use GNU89 linkage semantics.
  env.NIX_CFLAGS_COMPILE = "-O2 -std=gnu89";

  installPhase = ''
    runHook preInstall
    install -Dm755 atrogue $out/libexec/atrogue/atrogue
    install -Dm644 docu/atrogue.6 $out/share/man/man6/atrogue.6
    install -Dm644 -t $out/share/doc/atrogue COPYING README INSTALL
    cp -r docu $out/share/doc/atrogue/docu

    # Logs and text screenshots go to the home path, which get_homepath()
    # rejects when absolute and over 50 bytes; a private working directory
    # with HOME=. keeps them bounded and out of the store.
    mkdir -p $out/bin
    cat > $out/bin/atrogue <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    state="\''${XDG_DATA_HOME:-\''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/atrogue"
    ${coreutils}/bin/mkdir -p -- "\$state"
    cd -- "\$state"
    export HOME=.
    exec $out/libexec/atrogue/atrogue "\$@"
    EOF
    chmod 555 $out/bin/atrogue
    runHook postInstall
  '';

  meta = {
    description = "Terminal roguelike with configurable dungeon exploration";
    longDescription = ''
      Atrogue is a curses-based roguelike with randomly generated dungeons,
      character roles, magic, combat, and configurable exploration
      preferences.  The launcher keeps optional logs and text screenshots in
      $XDG_DATA_HOME/atrogue, falling back to ~/.local/share/atrogue.  The
      release has no save/load support.
    '';
    homepage = "https://atrogue.sourceforge.net/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "atrogue";
  };
})
