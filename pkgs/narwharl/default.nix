{ lib, stdenv, fetchurl, runtimeShell, coreutils, ncurses }:

stdenv.mkDerivation (finalAttrs: {
  pname = "narwharl";
  version = "0.0.1";

  src = fetchurl {
    url = "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/narwharl/narwharl-${finalAttrs.version}.tar.gz";
    hash = "sha256-OTdEupJTbxYFPJgTaAyCY04yeUf//DPR/JoojBavDaU=";
  };

  buildInputs = [ ncurses ];

  postPatch = ''
    # Build as C++98 against plain ncurses; no curses C++ classes are used.
    substituteInPlace Makefile \
      --replace-fail 'LDFLAGS=-lncurses++ -lpanel -lmenu -lncurses' 'LDFLAGS=-lncurses' \
      --replace-fail 'CFLAGS=-g -c' 'CFLAGS=-std=c++98 -O2 -c'
    substituteInPlace nheader.h \
      --replace-fail '#include <ncurses/cursesapp.h>' '#include <curses.h>'

    # Constructing the global Stuffgetter uses the RNG before main() seeds it.
    substituteInPlace main.cpp \
      --replace-fail 'Stuffgetter * objget = new Stuffgetter();' 'Stuffgetter * objget = NULL;' \
      --replace-fail '  mtinit(&seed);' $'  mtinit(&seed);\n  objget = new Stuffgetter();'

    # Generation and resume read these members before allocating them, and
    # stacked items must keep their floor coordinates across save/load.
    substituteInPlace map.cpp \
      --replace-fail '  seed = sseed;' $'  seed = sseed;\n  map=NULL;\n  mlist=NULL;\n  plan=NULL;\n  xsize=0;\n  ysize=0;' \
      --replace-fail '  list_add(this->getitems(y,x),(void *)item);' $'  item->y=y;\n  item->x=x;\n  list_add(this->getitems(y,x),(void *)item);'

    # Value-returning functions that fall off the end.
    substituteInPlace newgenmap.cpp \
      --replace-fail '  placement(ly,lx,hy,hx,y,x,itemprob,monprob,0,map);' '  return placement(ly,lx,hy,hx,y,x,itemprob,monprob,0,map);' \
      --replace-fail '  }*/' $'  }*/\n  return 1;'
    substituteInPlace llist.cpp nheader.h \
      --replace-quiet 'void * list_merge' 'void list_merge' \
      --replace-quiet 'void *list_merge' 'void list_merge'
    substituteInPlace map.cpp \
      --replace-fail '  if (y > 10) {map->see(y,x);}' $'  if (y > 10) {map->see(y,x);}\n  return 0;'
    substituteInPlace creature.cpp \
      --replace-fail $'int Creature::ai(Map *map, Screen *vscreen)\n{\n}' $'int Creature::ai(Map *map, Screen *vscreen)\n{\n  return 0;\n}'
    substituteInPlace stuffread.cpp \
      --replace-fail '    list_delete(&newspelllist);' $'    list_delete(&newspelllist);\n    return NULL;'

    # Game definitions are immutable data in the store; save/ stays relative
    # to the launcher's writable state directory.
    substituteInPlace stuffread.cpp \
      --replace-fail '"defs/' "\"$out/share/narwharl/defs/"

    # Curses output passes game text as the format string; print it via %s.
    sed -i '/"%/!s/printw(\(.*\),\([^,]*\.c_str()\));/printw(\1,"%s",\2);/' screen.cpp
    if grep -nE 'printw\([^"]*c_str\(\)\);' screen.cpp | grep -v '^[0-9]*: *//'; then
      echo 'unconverted printw format strings remain' >&2
      exit 1
    fi
  '';

  dontConfigure = true;
  makeFlags = [ "CXX=${stdenv.cc.targetPrefix}c++" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 narwharl $out/libexec/narwharl/narwharl
    mkdir -p $out/share/narwharl $out/bin
    cp -r defs $out/share/narwharl/defs
    install -Dm644 -t $out/share/doc/narwharl README INSTALL CHANGELOG gpl-2.0.txt
    install -Dm644 -t $out/share/doc/narwharl/mtrand mtrand/mtreadme.txt mtrand/mtrand.h

    cat > $out/bin/narwharl <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/narwharl"
    ${coreutils}/bin/mkdir -p -- "\$state/save"
    cd -- "\$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    export TERM="\''${TERM:-xterm-256color}"
    exec $out/libexec/narwharl/narwharl "\$@"
    EOF
    chmod 555 $out/bin/narwharl
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/narwharl/narwharl
    grep -qF "$out/share/narwharl/defs/" $out/libexec/narwharl/narwharl
    for f in armor launchers monsters potions spells weapons; do
      test -s $out/share/narwharl/defs/$f.txt
    done
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal dungeon exploration roguelike";
    longDescription = ''
      NarwhaRL is Nathan Hetherington's curses roguelike with procedural maps,
      monsters, equipment, potions, spells and saved games.  The launcher keeps
      saves in $XDG_STATE_HOME/narwharl, falling back to
      ~/.local/state/narwharl, and reads game definitions from the package
      output.  An optional numeric argument sets the random seed.
    '';
    homepage = "https://code.google.com/archive/p/narwharl/";
    license = with lib.licenses; [ gpl2Plus bsd3 ];
    platforms = lib.platforms.linux;
    mainProgram = "narwharl";
  };
})
