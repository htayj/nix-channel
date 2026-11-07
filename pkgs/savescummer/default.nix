{ lib, stdenv, fetchurl, ncurses, coreutils, runtimeShell }:

stdenv.mkDerivation (finalAttrs: {
  pname = "savescummer";
  version = "002";

  # The homepage's own HTTP link; the site's TLS certificate names another host.
  src = fetchurl {
    url = "http://www.zincland.com/7drl/savescummer/savescummer${finalAttrs.version}.tar.gz";
    hash = "sha256-eTzJzJ1IaiJwlxS6INc4JmVgg/gp4sXy1tOqQHS/Cs4=";
  };

  buildInputs = [ ncurses ];

  # The sources use CRLF line endings.  Every match below lies within one
  # line and GNU make ignores the CR before LF, so the files keep their
  # endings and the data files stay byte-identical.
  postPatch = ''
    # Prebuilt programs, Microsoft and SDL DLLs, PDCurses libraries, bitmap
    # fonts, and the SDL and Windows ports are not used.
    rm -r linux linux_curses windows windows_curses mac gfx \
      src/gfx src/wincurses src/winport src/gfx_sdl.cpp src/gfx_sdl.h

    # Build the curses port (see src/macport/BUILD.TXT) instead of SDL.
    substituteInPlace src/linuxport/Makefile \
      --replace-fail '../gfx_sdl.o' '../gfx_curses.o' \
      --replace-fail 'g++ -O3 `sdl-config --cflags` -c $< -o $@' \
                     '$(CXX) $(CXXFLAGS) -DUSE_CURSES -c $< -o $@' \
      --replace-fail 'g++ -O3 -o $(TARGET) $(OFILES) `sdl-config --libs`' \
                     '$(CXX) $(CXXFLAGS) -o $(TARGET) $(OFILES) -lncurses' \
      --replace-fail 'cd .. ; ' 'cd .. && '
    substituteInPlace src/support/enummaker/Makefile \
      --replace-fail 'g++ -O3' '$(CXX) $(CXXFLAGS)'

    # Current glibc and GCC no longer declare these implicitly.
    substituteInPlace src/gfx_curses.cpp \
      --replace-fail '#include <assert.h>' \
                     $'#include <assert.h>\n#include <string.h>\n#include <unistd.h>'
    substituteInPlace src/hiscore.cpp \
      --replace-fail '#include <fstream>' $'#include <string.h>\n#include <fstream>'
    substituteInPlace src/main.cpp \
      --replace-fail '#include <time.h>' $'#include <time.h>\n#include <unistd.h>'

    # Read-only data comes from the store; the saved game and high scores
    # are still written relative to the working directory.
    substituteInPlace src/text.cpp \
      --replace-fail '"../text.txt"' "\"$out/share/savescummer/text.txt\""
    substituteInPlace src/map.cpp \
      --replace-fail '"../rooms/piecelist.map"' \
                     "\"$out/share/savescummer/rooms/piecelist.map\""
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    make -C src/support/enummaker CXX=c++ CXXFLAGS=-O2
    # enummaker generates glbdef.cpp and glbdef.h from source.txt.
    make -C src/linuxport premake
    make -C src/linuxport -j$NIX_BUILD_CORES \
      CXX=${stdenv.cc.targetPrefix}c++ CXXFLAGS=-O2
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 src/linuxport/savescummer $out/libexec/savescummer/savescummer
    install -Dm644 src/text.txt $out/share/savescummer/text.txt
    install -Dm644 rooms/piecelist.map $out/share/savescummer/rooms/piecelist.map
    install -Dm644 -t $out/share/doc/savescummer LICENSE.TXT README.TXT

    # The launcher keeps savescummer.sav and hiscore.txt in a per-user
    # state directory.
    mkdir -p $out/bin
    cat > $out/bin/savescummer <<'EOF'
    #!${runtimeShell}
    set -eu
    case "''${XDG_STATE_HOME:-}" in
      /*) state="$XDG_STATE_HOME/savescummer" ;;
      *) state="''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state/savescummer" ;;
    esac
    ${coreutils}/bin/mkdir -p -- "$state"
    cd -- "$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec @out@/libexec/savescummer/savescummer "$@"
    EOF
    substituteInPlace $out/bin/savescummer --replace-fail '@out@' "$out"
    chmod 555 $out/bin/savescummer
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/savescummer/savescummer
    test -s $out/share/savescummer/text.txt
    test -s $out/share/savescummer/rooms/piecelist.map
    grep -qaF "$out/share/savescummer/text.txt" $out/libexec/savescummer/savescummer
    grep -qaF "$out/share/savescummer/rooms/piecelist.map" $out/libexec/savescummer/savescummer
    grep -qF "Jeff Lait" $out/share/doc/savescummer/LICENSE.TXT
    ${runtimeShell} -n $out/bin/savescummer
    test -z "$(find $out \( -iname '*.bmp' -o -iname '*.dll' -o -iname '*.exe' -o -iname '*sdl*' \) -print)"
    runHook postInstallCheck
  '';

  meta = {
    description = "Seven Day Roguelike played by rewinding and restoring saves";
    longDescription = ''
      Save Scummer is a terminal roguelike by Jeff Lait.  The hero moves on
      its own; the player advances and rewinds time and keeps ten backup save
      slots.  This package builds the curses port from source.  The launcher
      keeps the saved game and high scores in $XDG_STATE_HOME/savescummer,
      falling back to ~/.local/state/savescummer.  The game needs an
      80-column terminal with at least 30 lines.
    '';
    homepage = "http://www.zincland.com/7drl/savescummer/";
    # LICENSE.TXT: 3-clause BSD for the game code, text and mt19937ar.c;
    # the room maps are public domain.  Nine sources keep a stale
    # "PROPRIETARY" template header that this archive-wide notice covers.
    license = [ lib.licenses.bsd3 lib.licenses.publicDomain ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "savescummer";
  };
})
