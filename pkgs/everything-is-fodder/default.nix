{ lib, stdenv, fetchurl, unzip, SDL, libpng, zlib, runtimeShell, coreutils }:

let
  # Object list from upstream linux/Makefile.  mt19937ar.c is included by
  # rand.cpp, not compiled separately.
  gameObjects = [
    "ai" "buf" "builder" "chooser" "config" "dircontrol" "display" "dpdf"
    "engine" "firefly" "gamedef" "gfxengine" "glbdef" "grammar" "item" "main"
    "map" "mob" "msg" "panel" "rand" "scrpos" "speed" "text" "thesaurus"
    "thread" "thread_linux"
  ];
in
stdenv.mkDerivation {
  pname = "everything-is-fodder";
  version = "2017-03-12";

  # The HTTPS endpoint has a mismatched certificate; the fixed hash
  # authenticates the archive served over HTTP.
  src = fetchurl {
    url = "http://www.zincland.com/7drl/fodder/fodder7drl.zip";
    hash = "sha256-/3o6cK5lz+yqapqv5omCH4ylZkeJMPHBgPrv5m1beis=";
  };

  nativeBuildInputs = [ unzip ];
  buildInputs = [ SDL libpng zlib ];

  postPatch = ''
    # Only source participates: drop bundled executables and libraries.
    rm -r windows linux/fodder_bin
    find lib \( -name '*.so' -o -name '*.so.*' -o -name '*.dll' -o -name '*.exe' \
      -o -name 'hmtool' -o -name 'hmtool_debug' -o -name 'samples_c' -o -name 'samples_c_debug' \
      -o -name 'samples_cpp' -o -name 'samples_cpp_debug' \) -type f -delete

    # libtcod 1.5.0 predates opaque libpng structs and its typed NULL macros.
    substituteInPlace lib/libtcod-1.5.0/src/sys_sdl_img_png.c \
      --replace-fail 'info_ptr->channels' 'png_get_channels(png_ptr, info_ptr)' \
      --replace-fail 'png_infopp_NULL' 'NULL' \
      --replace-fail 'png_voidp_NULL' 'NULL'
    # Typed prototype instead of K&R implicit ints; initialize before font
    # setup because the static archive does not pull sys_c.c's constructor.
    substituteInPlace lib/libtcod-1.5.0/src/sys_sdl_c.c \
      --replace-fail 'TCOD_sys_map_ascii_to_font(asciiCode, fontCharX, fontCharY)' \
        'TCOD_sys_map_ascii_to_font(int asciiCode, int fontCharX, int fontCharY)' \
      --replace-fail 'strcpy(font_file,fontFile);' \
        'TCOD_sys_startup(); strcpy(font_file,fontFile);'
    # POSIX declarations used by the game headers.
    substituteInPlace src/dircontrol.h \
      --replace-fail '#include <dirent.h>' $'#include <dirent.h>\n#include <limits.h>'
    substituteInPlace src/mygba.h \
      --replace-fail '#ifdef LINUX' $'#ifdef LINUX\n#include <unistd.h>'
  '';

  # Upstream links prebuilt libtcod; rebuild the vendored 1.5.0 statically,
  # since the game uses its API.  USE_AUDIO stays disabled in main.cpp.
  buildPhase = ''
    runHook preBuild
    vendor=lib/libtcod-1.5.0
    common="-O2 -D_GNU_SOURCE -I$vendor/include -I${lib.getDev SDL}/include/SDL"
    mkdir -p build/tcod-c build/tcod-cpp build/game
    # The 2010 libtcod C predates GCC 14 turning these diagnostics into errors;
    # keep them as warnings for the vendored C only.
    cCompat="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=incompatible-pointer-types -Wno-error=int-conversion"
    for f in $vendor/src/*.c; do
      if [ "$(basename "$f")" = sys_sfml_c.c ]; then continue; fi
      $CC $common -std=gnu99 $cCompat -c "$f" -o "build/tcod-c/$(basename "$f").o"
    done
    for f in $vendor/src/*.cpp; do
      $CXX $common -std=gnu++11 -c "$f" -o "build/tcod-cpp/$(basename "$f").o"
    done
    $AR crsD build/libtcod.a build/tcod-c/*.o build/tcod-cpp/*.o
    for n in ${lib.concatStringsSep " " gameObjects}; do
      $CXX $common -std=gnu++11 -DLINUX -pthread -c "src/$n.cpp" -o "build/game/$n.o"
    done
    $CXX -o build/everything-is-fodder build/game/*.o build/libtcod.a \
      -lSDL -lpng -lz -lm -pthread
    runHook postBuild
  '';

  # The game reads ../fodder.cfg, ../text.txt, ../rooms and ./terminal.png and
  # writes ../save relative to its working directory, so run it from a
  # private state tree with store assets linked in.
  installPhase = ''
    runHook preInstall
    install -Dm555 build/everything-is-fodder $out/libexec/everything-is-fodder/everything-is-fodder
    data=$out/share/everything-is-fodder
    install -Dm444 -t $data linux/terminal.png fodder.cfg text.txt
    install -Dm444 -t $data/rooms rooms/village.map
    doc=$out/share/doc/everything-is-fodder
    install -Dm444 -t $doc README.TXT 7drlchanges.TXT src/LICENSE.TXT \
      lib/libtcod-1.5.0/LIBTCOD-LICENSE.txt lib/libtcod-1.5.0/LIBTCOD-CREDITS.txt \
      lib/libtcod-1.5.0/README-SDL.txt \
      src/support/fontbuilder/OFL.txt
    install -Dm444 -t $doc/upstream-linux linux/Makefile linux/BUILD.TXT

    mkdir -p $out/bin
    cat > $out/bin/everything-is-fodder <<'EOF'
    #!${runtimeShell}
    set -eu
    if test "$#" -ne 0; then
        echo 'usage: everything-is-fodder (graphical game; no command-line options)' >&2
        exit 64
    fi
    umask 077
    data='${placeholder "out"}/share/everything-is-fodder'
    state="''${XDG_DATA_HOME:-''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/everything-is-fodder"
    case "$state" in
        /*) ;;
        *) echo 'everything-is-fodder: HOME/XDG_DATA_HOME must be absolute' >&2; exit 1 ;;
    esac
    '${coreutils}/bin/mkdir' -p "$state/linux" "$state/rooms" "$state/save"
    if test ! -e "$state/fodder.cfg"; then
        '${coreutils}/bin/cp' "$data/fodder.cfg" "$state/fodder.cfg"
        '${coreutils}/bin/chmod' 600 "$state/fodder.cfg"
    fi
    '${coreutils}/bin/ln' -sfn "$data/terminal.png" "$state/linux/terminal.png"
    '${coreutils}/bin/ln' -sfn "$data/rooms/village.map" "$state/rooms/village.map"
    '${coreutils}/bin/ln' -sfn "$data/text.txt" "$state/text.txt"
    cd "$state/linux"
    exec '${placeholder "out"}/libexec/everything-is-fodder/everything-is-fodder'
    EOF
    chmod 555 $out/bin/everything-is-fodder
    runHook postInstall
  '';

  meta = {
    description = "Jeff Lait's 2017 Seven Day Roguelike about transmuting objects into elemental coins";
    longDescription = ''
      Everything Is Fodder is Jeff Lait's 2017 Seven Day Roguelike.  Explore
      random dungeons, transmute objects into elemental coins and spend them
      on spells on the quest to defeat the demon lord Ba'zlbub.  The game and
      its libtcod 1.5.0 rendering library are compiled from source.
      Configuration and saved games persist under
      $XDG_DATA_HOME/everything-is-fodder, falling back to
      ~/.local/share/everything-is-fodder.
    '';
    homepage = "http://www.zincland.com/7drl/fodder/";
    # Game, libtcod and MT19937: BSD-3; rooms/village.map: public domain;
    # Oxygen Mono glyph atlas (linux/terminal.png): OFL 1.1.
    license = with lib.licenses; [ bsd3 publicDomain ofl ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "everything-is-fodder";
  };
}
