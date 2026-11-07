{ lib, stdenv, fetchurl, unzip, runtimeShell, coreutils, SDL, libpng, zlib }:

let
  # Game translation units from upstream linux/Makefile.
  gameSources = [
    "ai" "buf" "builder" "chooser" "config" "defedit" "dircontrol"
    "display" "dpdf" "engine" "firefly" "gamedef" "gfxengine" "glbdef"
    "grammar" "item" "main" "map" "mob" "msg" "panel" "rand" "scrpos"
    "speed" "text" "thread" "thread_linux" "wordlist"
  ];
in
stdenv.mkDerivation {
  pname = "six-two-one";
  version = "2016-03-06";

  # Upstream's HTTPS endpoint has a mismatched certificate; HTTP serves the
  # same archive and the fixed hash authenticates it.
  src = fetchurl {
    url = "http://www.zincland.com/7drl/sixtwoone/sixtwoone7drl.zip";
    hash = "sha256-w1lzIZlPJaCS4rZsvu4L8EQzGvSWG8Q07GiHcKY9aEM=";
  };
  sourceRoot = "sixtwoone7drl";

  nativeBuildInputs = [ unzip ];
  buildInputs = [ SDL libpng zlib ];

  postPatch = ''
    # Prebuilt executables and libraries are never used; the checked-in
    # glbdef.cpp/h are used instead of the enum generator.
    rm -r windows
    rm linux/sixtwoone_bin
    find lib -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dll' \
      -o -name '*.exe' -o -name hmtool -o -name hmtool_debug \
      -o -name samples_c -o -name samples_c_debug \
      -o -name samples_cpp -o -name samples_cpp_debug \) -delete

    # libtcod 1.5.0 predates opaque libpng structs and the removal of its
    # typed NULL macros.
    substituteInPlace lib/libtcod-1.5.0/src/sys_sdl_img_png.c \
      --replace-fail 'info_ptr->channels' 'png_get_channels(png_ptr, info_ptr)' \
      --replace-fail 'png_infopp_NULL' 'NULL' \
      --replace-fail 'png_voidp_NULL' 'NULL'

    # Match the header's typed prototype.  The static archive does not pull
    # in sys_c.c's constructor, so initialize before loading glyphs; a later
    # startup would reset the ASCII mapping and the first-draw colour cache.
    substituteInPlace lib/libtcod-1.5.0/src/sys_sdl_c.c \
      --replace-fail 'TCOD_sys_map_ascii_to_font(asciiCode, fontCharX, fontCharY)' \
        'TCOD_sys_map_ascii_to_font(int asciiCode, int fontCharX, int fontCharY)' \
      --replace-fail 'strcpy(font_file,fontFile);' \
        'TCOD_sys_startup(); strcpy(font_file,fontFile);'

    # POSIX NAME_MAX and unlink declarations used by the game headers.
    substituteInPlace src/dircontrol.h \
      --replace-fail '#include <dirent.h>' $'#include <dirent.h>\n#include <limits.h>'
    substituteInPlace src/mygba.h \
      --replace-fail '#ifdef LINUX' $'#ifdef LINUX\n#include <unistd.h>'
  '';

  buildPhase = ''
    runHook preBuild
    tcod=lib/libtcod-1.5.0
    common="-O2 -D_GNU_SOURCE -I$tcod/include -I${lib.getDev SDL}/include -I${lib.getDev SDL}/include/SDL"
    mkdir -p build/tcod build/game

    # Private static libtcod rebuilt from the archive; the SFML backend,
    # GUI toolkit and heightmap tool are not needed.
    for f in $(find $tcod/src -name '*.c' ! -name sys_sfml_c.c | sort); do
      $CC $common -std=gnu99 -c "$f" -o "build/tcod/$(basename "$f").o"
    done
    for f in $(find $tcod/src -name '*.cpp' ! -path '*/gui/*' ! -path '*/hmtool/*' | sort); do
      $CXX $common -std=gnu++11 -c "$f" -o "build/tcod/$(basename "$f").o"
    done
    $AR crsD build/libtcod.a build/tcod/*.o

    for n in ${lib.concatStringsSep " " gameSources}; do
      $CXX $common -std=gnu++11 -DLINUX -pthread -c "src/$n.cpp" -o "build/game/$n.o"
    done
    # Audio is disabled upstream (USE_AUDIO), so SDL_mixer is not linked.
    $CXX -o build/six-two-one build/game/*.o build/libtcod.a \
      -lSDL -lpng -lz -lm -pthread
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 build/six-two-one $out/libexec/six-two-one/six-two-one

    data=$out/share/six-two-one
    install -Dm644 -t $data linux/terminal.png sixtwoone.cfg text.txt
    install -Dm644 -t $data/rooms rooms/village.map
    install -Dm644 -t $data/wordlist wordlist/wordlist.txt

    doc=$out/share/doc/six-two-one
    install -Dm644 -t $doc README.TXT src/LICENSE.TXT \
      lib/libtcod-1.5.0/LIBTCOD-LICENSE.txt \
      lib/libtcod-1.5.0/LIBTCOD-CREDITS.txt \
      lib/libtcod-1.5.0/README-SDL.txt \
      src/support/fontbuilder/OFL.txt
    cat > $doc/THIRD-PARTY-NOTICES.txt <<'EOF'
    Six Two One, original 7DRL release (2016-03-06)
    ================================================
    Canonical source: http://www.zincland.com/7drl/sixtwoone/sixtwoone7drl.zip
    SHA-256: c3597321994f25a092e2b66cbeee0bf044331af4961bc434ec688770a63d6843

    Game C++ source, generated enums, configuration and text: Jeff Lait,
    BSD-3-Clause.  The embedded mt19937ar.c is copyright Makoto Matsumoto and
    Takuji Nishimura under its three-clause BSD terms.  The complete notices
    for both are reproduced in LICENSE.TXT.

    rooms/village.map and wordlist/wordlist.txt (Moby Project): public domain,
    as explicitly declared in LICENSE.TXT.

    terminal.png is the game's Oxygen Mono glyph image (despite the .png
    suffix it has a BMP header).  Oxygen Mono is copyright 2012 Vernon Adams,
    with Reserved Font Name Oxygen.  Its SIL Open Font License 1.1 and
    copyright notice are reproduced in OFL.txt.  No other libtcod demo fonts
    are installed.

    libtcod 1.5.0, rebuilt from the same archive and statically linked into
    the game: copyright 2008,2009,2010 Jice, BSD-3-Clause.  See
    LIBTCOD-LICENSE.txt and LIBTCOD-CREDITS.txt.  No upstream executable or
    shared library is reused.

    The game links dynamically to the separately packaged Nixpkgs SDL 1.2
    compatibility layer (sdl12-compat, zlib license), libpng (libpng license)
    and zlib (zlib license); their sources and licenses come from their
    Nixpkgs derivations.  The historic LGPL SDL redistribution notice from the
    archive is kept as README-SDL.txt and in LICENSE.TXT; it describes the old
    upstream binaries, not sdl12-compat.

    Audio is disabled in upstream main.cpp (USE_AUDIO is commented out), so
    SDL_mixer and the empty music directory are neither linked nor installed.
    Windows DLLs, prebuilt Linux executables, bundled SDL and libtcod shared
    libraries, demos and their data and font assets are not installed.
    EOF

    # Upstream resolves assets and saves relative to linux/.  Rebuild that
    # layout outside the store, with only configuration and saves writable.
    mkdir -p $out/bin
    cat > $out/bin/six-two-one <<'EOF'
    #!@shell@
    set -eu
    if test "$#" -ne 0; then
      echo 'usage: six-two-one (graphical game; no command-line options)' >&2
      exit 64
    fi
    umask 077
    data='@data@'
    state="''${XDG_DATA_HOME:-''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/six-two-one"
    case "$state" in
      /*) ;;
      *) echo 'six-two-one: HOME/XDG_DATA_HOME must be absolute' >&2; exit 1 ;;
    esac
    @coreutils@/bin/mkdir -p "$state/linux" "$state/rooms" "$state/wordlist" "$state/save"
    if test ! -e "$state/sixtwoone.cfg"; then
      @coreutils@/bin/cp "$data/sixtwoone.cfg" "$state/sixtwoone.cfg"
      @coreutils@/bin/chmod 600 "$state/sixtwoone.cfg"
    fi
    @coreutils@/bin/ln -sfn "$data/terminal.png" "$state/linux/terminal.png"
    @coreutils@/bin/ln -sfn "$data/rooms/village.map" "$state/rooms/village.map"
    @coreutils@/bin/ln -sfn "$data/wordlist/wordlist.txt" "$state/wordlist/wordlist.txt"
    @coreutils@/bin/ln -sfn "$data/text.txt" "$state/text.txt"
    cd "$state/linux"
    exec '@program@'
    EOF
    substituteInPlace $out/bin/six-two-one \
      --replace-fail '@shell@' '${runtimeShell}' \
      --replace-fail '@data@' "$data" \
      --replace-fail '@coreutils@' '${coreutils}' \
      --replace-fail '@program@' "$out/libexec/six-two-one/six-two-one"
    chmod 555 $out/bin/six-two-one
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    status=0
    $out/bin/six-two-one unexpected-argument 2>/dev/null || status=$?
    test "$status" -eq 64
    runHook postInstallCheck
  '';

  meta = {
    description = "Topological word puzzle roguelike";
    longDescription = ''
      Six Two One is Jeff Lait's 2016 Seven Day Roguelike.  Explore a
      cube-like labyrinth and decode six nine-letter words before your life
      force runs out.  The game and its libtcod 1.5.0 rendering library are
      compiled from source against SDL 1.2 compatibility; platform binaries,
      demo fonts and unused music are omitted.  Configuration, world
      definitions and saved games live in $XDG_DATA_HOME/six-two-one, falling
      back to ~/.local/share/six-two-one.
    '';
    homepage = "http://www.zincland.com/7drl/sixtwoone/";
    license = with lib.licenses; [ bsd3 publicDomain ofl ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "six-two-one";
  };
}
