{ lib, stdenv, fetchurl, unzip, runtimeShell, coreutils, SDL, libpng, zlib }:

let
  # Game translation units from upstream src/linux/Makefile.
  gameSources = [
    "ai" "buf" "chooser" "config" "dircontrol" "display" "dpdf" "engine"
    "firefly" "gfxengine" "glbdef" "grammar" "item" "main" "map" "mob"
    "msg" "panel" "rand" "scrpos" "simulator" "speed" "text" "thread"
    "thread_linux"
  ];
in
stdenv.mkDerivation {
  pname = "the-smiths-hand";
  version = "2014-03-16";

  # Upstream's HTTPS endpoint has a mismatched certificate; HTTP serves the
  # same archive and the fixed hash authenticates it.
  src = fetchurl {
    url = "http://www.zincland.com/7drl/smith/smith7drl.zip";
    hash = "sha256-okXiazBdH/nsJbzIdjXU6AAPFn4lY7XiaaPtDBnire4=";
  };
  sourceRoot = "smith7drl";

  nativeBuildInputs = [ unzip ];
  buildInputs = [ SDL libpng zlib ];

  postPatch = ''
    # Prebuilt executables and libraries are never used.
    rm -r windows
    rm linux/smith_bin
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
    # in sys_c.c's constructor, so initialize before loading glyphs.
    substituteInPlace lib/libtcod-1.5.0/src/sys_sdl_c.c \
      --replace-fail 'TCOD_sys_map_ascii_to_font(asciiCode, fontCharX, fontCharY)' \
        'TCOD_sys_map_ascii_to_font(int asciiCode, int fontCharX, int fontCharY)' \
      --replace-fail 'strcpy(font_file,fontFile);' \
        'TCOD_sys_startup(); strcpy(font_file,fontFile);'

    # POSIX NAME_MAX and unlink declarations.
    substituteInPlace src/dircontrol.h \
      --replace-fail '#include <dirent.h>' $'#include <dirent.h>\n#include <limits.h>'
    substituteInPlace src/map.cpp \
      --replace-fail '#include <fstream>' $'#include <fstream>\n#include <unistd.h>'

    # The archive has no music, and windowed mode suits small displays.
    substituteInPlace smith.cfg \
      --replace-fail 'enable = true' 'enable = false' \
      --replace-fail 'full = true' 'full = false'
  '';

  buildPhase = ''
    runHook preBuild
    tcod=lib/libtcod-1.5.0
    common="-O2 -D_GNU_SOURCE -I$tcod/include -I${lib.getDev SDL}/include -I${lib.getDev SDL}/include/SDL"
    mkdir -p build/tcod build/game

    # Regenerate glbdef.cpp/h from source.txt with the source-built enummaker,
    # as upstream's premake target does.
    $CXX -O2 -std=gnu++11 src/support/enummaker/enummaker.cpp \
      -o build/enummaker
    (cd src && ../build/enummaker source.txt)

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
    $CXX -o build/smith build/game/*.o build/libtcod.a \
      -lSDL -lpng -lz -lm -pthread
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 build/smith $out/libexec/the-smiths-hand/smith

    data=$out/share/the-smiths-hand
    install -Dm644 -t $data linux/terminal.png smith.cfg text.txt
    install -Dm644 -t $data/rooms rooms/village.map

    doc=$out/share/doc/the-smiths-hand
    install -Dm644 -t $doc README.TXT src/LICENSE.TXT \
      lib/libtcod-1.5.0/LIBTCOD-LICENSE.txt \
      lib/libtcod-1.5.0/LIBTCOD-CREDITS.txt \
      lib/libtcod-1.5.0/README-SDL.txt
    install -Dm644 lib/libtcod-1.5.0/data/fonts/README.txt $doc/FONT-NOTICE.txt
    cat > $doc/THIRD-PARTY-NOTICES.txt <<'EOF'
    The Smith's Hand, original 7DRL release (2014-03-16)
    ====================================================
    Canonical source: http://www.zincland.com/7drl/smith/smith7drl.zip
    Snapshot version: 2014-03-16 (upstream archive Last-Modified date).
    SHA-256: a245e26b305d1ff9ec25bcc87635d4e8000f167e2563b5e269a3ed0c19e2adee

    Game C++ source, generated definitions, enummaker and text: Copyright (c)
    2010 Jeff Lait, BSD-3-Clause.  rand.cpp includes the supplied thread-safe
    mt19937ar.c, copyright 1997-2002 Makoto Matsumoto and Takuji Nishimura
    under its three-clause BSD terms.  The complete notices for both are
    reproduced in LICENSE.TXT.  Enummaker is rebuilt from source and
    regenerates glbdef.cpp/h from source.txt before game compilation.

    rooms/village.map is the original map; LICENSE.TXT declares .map files
    public domain.

    terminal.png is the original libtcod legacy terminal bitmap, identical in
    the archive's linux/ and lib/libtcod-1.5.0/ directories (SHA-256
    5e9e64246b857dc414bd0acde98820885274483580f751b9b3329b8ee86b82f4).
    FONT-NOTICE.txt reproduces libtcod's public-domain font declaration.  No
    other fonts are installed.

    libtcod 1.5.0, rebuilt from the same archive and statically linked into
    the game: copyright 2008,2009,2010 Jice, BSD-3-Clause.  See
    LIBTCOD-LICENSE.txt and LIBTCOD-CREDITS.txt.  No upstream executable or
    shared library is reused.

    The game links dynamically to the separately packaged Nixpkgs SDL 1.2
    compatibility layer (sdl12-compat, zlib license), libpng (libpng license)
    and zlib (zlib license); their sources and licenses come from their
    Nixpkgs derivations.  The historic LGPL SDL redistribution notice from the
    archive is kept as README-SDL.txt; it describes the old upstream binaries,
    not sdl12-compat.

    The installed smith.cfg is the original with music.enable and screen.full
    set to false.  Audio is disabled in upstream main.cpp (USE_AUDIO is
    commented out), so SDL_mixer and the empty music directory are neither
    linked nor installed.  Windows DLLs, prebuilt Linux executables, bundled
    SDL and libtcod shared libraries, demos and their data and fonts are not
    installed.  There are no runtime downloads.  The original Q command saves
    to smith.sav, which the game loads on startup; saves use the upstream
    host-endian format.
    EOF

    # Upstream resolves assets and saves relative to linux/.  Rebuild that
    # layout outside the store, with only configuration and saves writable.
    mkdir -p $out/bin
    cat > $out/bin/smith <<'EOF'
    #!@shell@
    set -eu
    if test "$#" -ne 0; then
      echo 'usage: smith (graphical game; no command-line options)' >&2
      exit 64
    fi
    umask 077
    data='@data@'
    state="''${XDG_DATA_HOME:-''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/the-smiths-hand"
    case "$state" in
      /*) ;;
      *) echo 'smith: HOME/XDG_DATA_HOME must be absolute' >&2; exit 1 ;;
    esac
    @coreutils@/bin/mkdir -p "$state/linux" "$state/rooms"
    if test ! -e "$state/smith.cfg"; then
      @coreutils@/bin/cp "$data/smith.cfg" "$state/smith.cfg"
      @coreutils@/bin/chmod 600 "$state/smith.cfg"
    fi
    @coreutils@/bin/ln -sfn "$data/terminal.png" "$state/linux/terminal.png"
    @coreutils@/bin/ln -sfn "$data/rooms/village.map" "$state/rooms/village.map"
    @coreutils@/bin/ln -sfn "$data/text.txt" "$state/text.txt"
    cd "$state/linux"
    exec '@program@'
    EOF
    substituteInPlace $out/bin/smith \
      --replace-fail '@shell@' '${runtimeShell}' \
      --replace-fail '@data@' "$data" \
      --replace-fail '@coreutils@' '${coreutils}' \
      --replace-fail '@program@' "$out/libexec/the-smiths-hand/smith"
    chmod 555 $out/bin/smith
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/config \
      XDG_CACHE_HOME=$TMPDIR/cache XDG_DATA_HOME=$TMPDIR/data \
      XDG_STATE_HOME=$TMPDIR/state XDG_RUNTIME_DIR=$TMPDIR/runtime
    status=0
    $out/bin/smith unexpected-argument 2>/dev/null || status=$?
    test "$status" -eq 64
    test ! -e "$XDG_DATA_HOME/the-smiths-hand"
    runHook postInstallCheck
  '';

  meta = {
    description = "Village smith roguelike with adventurer equipment trading";
    longDescription = ''
      The Smith's Hand is Jeff Lait's 2014 Seven Day Roguelike about a village
      smith.  Equip adventurers exploring an orc-infested cave, balancing
      profits against their safety.  The game and its libtcod 1.5.0 rendering
      library are compiled from source against SDL 1.2 compatibility; platform
      binaries, demo fonts and music are omitted, and default music is
      disabled.  Configuration and saved games live in
      $XDG_DATA_HOME/the-smiths-hand, falling back to
      ~/.local/share/the-smiths-hand.
    '';
    homepage = "http://www.zincland.com/7drl/smith/";
    license = with lib.licenses; [ bsd3 publicDomain ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "smith";
  };
}
