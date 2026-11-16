{
  lib,
  stdenv,
  fetchurl,
  unzip,
  pkg-config,
  SDL2,
  SDL2_ttf,
  sqlite,
  liberation_ttf,
  coreutils,
  runtimeShell,
  xvfb,
  xdotool,
  xwd,
  imagemagick,
}:

let
  # The C++ translation units of exalt.vcproj, in its original order.
  units = [
    "buff" "creature" "npc" "pc" "stats" "status" "attr" "item"
    "itemstack" "area" "cell" "cellfeature" "door" "level" "lightsrc"
    "warp" "world" "gameobj" "quality" "cmd" "gamefunc" "input" "main"
    "msg" "msgmanager" "birthstate" "gamestate" "helpstate" "mainstate"
    "logger" "random" "bitmap" "extio" "tokenizer" "db" "astar" "fov"
    "font" "fontmanager" "itemfact" "monsterfact" "box2i" "colors"
    "cstring" "infobrowser" "look" "maindisplay" "menubox" "menuoption"
    "prompt" "terminal" "vertex2i" "levelfact" "dungen" "dunroom"
    "duntemp" "duntempman" "duntheme" "maze" "simplegen" "simpletheme"
    "ai" "aidata" "aimanager" "aistate" "melee" "attackmelee" "follow"
    "moveto" "tracksmell" "wait"
  ];
in
stdenv.mkDerivation {
  pname = "exalt";
  # The archive is 0.3.0; src/compiledef.h makes the game report v 0.3.1.
  version = "0.3.0";

  src = fetchurl {
    url = "mirror://sourceforge/exaltengine/exalt-0.3.0.zip";
    hash = "sha256-6xLcMkdhBbAl+92r+5FjT27UctMBcnDM8fArZtD088k=";
  };

  # The archive has no top-level directory.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    unzip -q $src -d source
    cd source
    runHook postUnpack
  '';

  # Windows import libraries, the leak detector and the private SQLite and
  # zlib copies are unused.  The bundled fonts are not installed: two are
  # never selected and have nonfree or unclear terms, and Liberation Mono
  # comes from Nixpkgs instead.  The sources have CRLF line endings and the
  # patches are written against LF.
  prePatch = ''
    rm -r lib src/sqlite src/zlib src/vld vld.dll
    rm data/fonts/*.ttf
    find src -type f \( -name '*.cpp' -o -name '*.h' \) -exec sed -i 's/\r$//' {} +
  '';

  # SDL2 and SDL_ttf replace the Win32 terminal and font code; POSIX calls
  # and an SDL event loop replace the Win32 input, directory and error
  # dialog code.  Same patches as the Guix channel.
  patches = [
    ./sdl-rendering.patch
    ./platform.patch
  ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];

  nativeBuildInputs = [
    unzip
    pkg-config
  ];
  buildInputs = [
    SDL2
    SDL2_ttf
    sqlite
  ];

  dontConfigure = true;

  # Upstream only has a Visual C++ project.  -std=gnu++11 because the code
  # assigns the iterator returned by map::erase.
  buildPhase = ''
    runHook preBuild
    if [ "$(printf '%s\n' ${toString units} | sort)" != "$(cd src && ls *.cpp | sed 's/\.cpp$//' | sort)" ]; then
      echo "the unit list differs from src/*.cpp" >&2
      exit 1
    fi
    mkdir build
    flags="-std=gnu++11 -O2 -Isrc $(pkg-config --cflags sdl2 SDL2_ttf sqlite3)"
    printf '%s\n' ${toString units} | xargs -P "$NIX_BUILD_CORES" -I{} \
      $CXX $flags -c src/{}.cpp -o build/{}.o
    $CXX -o build/exalt $(printf 'build/%s.o ' ${toString units}) \
      $(pkg-config --libs sdl2 SDL2_ttf sqlite3)
    runHook postBuild
  '';

  # The game opens data/, its SQLite cache, saves and log.xml relative to the
  # working directory, so the launcher runs it in a private state directory
  # whose asset entries link to the store.
  installPhase = ''
    runHook preInstall
    install -Dm755 build/exalt $out/libexec/exalt/exalt
    mkdir -p $out/share/exalt
    cp -r data $out/share/exalt/data
    rmdir $out/share/exalt/data/save
    ln -s ${liberation_ttf}/share/fonts/truetype/LiberationMono-Regular.ttf \
      $out/share/exalt/data/fonts/liberation.ttf

    doc=$out/share/doc/exalt
    install -Dm644 copying.txt $doc/copying.txt
    install -Dm644 \
      ${liberation_ttf}/share/doc/liberation-fonts-${liberation_ttf.version}/LICENSE \
      $doc/LIBERATION-LICENSE.txt
    cat > $doc/NOTICE <<'EOF'
    Exalt 0.3.0, Copyright (C) 2009-2010 Jake Keel, GPL-3.0-or-later
    (copying.txt).  Source archive published 2010-10-18:
    https://downloads.sourceforge.net/project/exaltengine/exalt-0.3.0.zip

    This build is modified.  Two patches from 2026-10-15 replace the Win32
    terminal, font, keyboard, event loop and file system code with SDL2,
    SDL_ttf and POSIX calls; the game logic and the five terminal windows
    are upstream's.  SQLite, SDL2 and SDL_ttf come from Nixpkgs.

    The archive's three font files are not installed.  The game only ever
    selects Liberation Mono; data/fonts/liberation.ttf links to Liberation
    Mono Regular @liberation@ from Nixpkgs (SIL Open Font License 1.1,
    LIBERATION-LICENSE.txt) in place of the bundled 1.04 file, so glyph
    shapes can differ from the original release.
    EOF
    substituteInPlace $doc/NOTICE --subst-var-by liberation ${liberation_ttf.version}

    mkdir -p $out/bin
    cat > $out/bin/exalt <<'EOF'
    #!@shell@
    set -eu
    if [ "$#" -ne 0 ]; then
      echo 'usage: exalt (graphical game; no command-line options)' >&2
      exit 64
    fi
    umask 077
    # Relative XDG_DATA_HOME values are ignored, as the XDG specification requires.
    case "''${XDG_DATA_HOME:-}" in
      /*) data_home=$XDG_DATA_HOME ;;
      *) data_home="''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share" ;;
    esac
    case "$data_home" in
      /*) ;;
      *) echo "exalt: state directory must be absolute: $data_home" >&2; exit 1 ;;
    esac
    state=$(@coreutils@/bin/realpath -m -- "$data_home/exalt")
    case "$state" in
      @storeDir@|@storeDir@/*)
        echo "exalt: refusing state in the immutable store: $state" >&2; exit 1 ;;
    esac
    # data/db (SQLite), data/save and log.xml are written here.
    @coreutils@/bin/mkdir -p -- "$state/data/save"
    for asset in display fonts help templates worlds log.xsl; do
      @coreutils@/bin/ln -sfnT -- "@out@/share/exalt/data/$asset" "$state/data/$asset"
    done
    cd -- "$state"
    exec @out@/libexec/exalt/exalt
    EOF
    substituteInPlace $out/bin/exalt \
      --subst-var-by shell ${runtimeShell} \
      --subst-var-by coreutils ${coreutils} \
      --subst-var-by storeDir ${builtins.storeDir} \
      --subst-var-by out $out
    chmod 555 $out/bin/exalt
    runHook postInstall
  '';

  # Upstream has no automated tests.  The smoke script starts a new game
  # under Xvfb, moves, toggles the Inventory window and ends the game.
  doInstallCheck = true;
  nativeInstallCheckInputs = [
    xvfb
    xdotool
    xwd
    imagemagick
  ];
  installCheckPhase = ''
    runHook preInstallCheck
    if find $out -type f \( -iname '*.dll' -o -iname '*.lib' -o -iname '*.ttf' \) | grep .; then
      echo "Windows binaries or bundled fonts were installed" >&2
      exit 1
    fi
    sh ${./smoke.sh} $out
    runHook postInstallCheck
  '';

  meta = {
    description = "Multiwindow fantasy roguelike engine with a pre-alpha sample game";
    longDescription = ''
      Exalt is Jake Keel's graphical fantasy roguelike engine and pre-alpha
      sample game.  This package builds the original 0.3.0 C++ sources with
      an SDL2 and SDL_ttf port of the Windows interface, keeping the five
      terminal windows, world selection, character creation and game logic.
      Liberation Mono from Nixpkgs replaces the bundled font.  Upstream
      never finished loading saved games.  The SQLite cache, saves and log
      live in $XDG_DATA_HOME/exalt, falling back to ~/.local/share/exalt.
    '';
    homepage = "https://sourceforge.net/projects/exaltengine/";
    license = lib.licenses.gpl3Plus;
    mainProgram = "exalt";
    platforms = [ "x86_64-linux" ];
  };
}
