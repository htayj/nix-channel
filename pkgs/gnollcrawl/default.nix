{ lib
, stdenv
, fetchurl
, bison
, flex
, perl
, pkg-config
, which
, lua5_1
, ncurses
, sqlite
, zlib
, SDL2
, SDL2_image
, SDL2_mixer
, freetype
, libpng
, libGL
, libGLU
, coreutils
, runtimeShell
}:

let
  # The exact crawl-fonts gitlink of the game release.
  fonts = fetchurl {
    name = "gnollcrawl-fonts-6d304697.tar.gz";
    url = "https://codeload.github.com/crawl/crawl-fonts/tar.gz/6d3046974f35189a679a4d84b254efe82d1653b3";
    hash = "sha256-KJpZIJ32kSUEHw5BIIlL+EjzPUa/6vFBxtpXHrgyxtc=";
  };

  # pcg.cc carries the Apache copyright notice but not the licence text.
  apacheLicense = fetchurl {
    name = "gnollcrawl-apache-2.0.txt";
    url = "https://www.apache.org/licenses/LICENSE-2.0.txt";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };

  # Shared by every invocation of the upstream Makefile.  Empty SAVEDIR and
  # SHAREDDIR leave mutable state to CRAWL_DIR, which the launchers set.
  crawlMakeFlags = [
    "prefix=${placeholder "out"}"
    "DATADIR=${placeholder "out"}/share/gnollcrawl"
    "SAVEDIR="
    "SHAREDDIR="
    "SQLITE_INCLUDE_DIR=${lib.getDev sqlite}/include"
    "SQLITE_LIB=-lsqlite3"
    "FORCE_CC=${stdenv.cc.targetPrefix}cc"
    "FORCE_CXX=${stdenv.cc.targetPrefix}c++"
    "LUA_PACKAGE=lua-5.1"
    "WEBTILES="
    "USE_LUAJIT="
    "USE_PCRE="
    "BUILD_ALL="
    "BUILD_LUA="
    "BUILD_SQLITE="
    "BUILD_ZLIB="
    "BUILD_PCRE="
    "BUILD_FREETYPE="
    "BUILD_LIBPNG="
    "BUILD_SDL2="
    "BUILD_SDL2IMAGE="
    "BUILD_SDL2MIXER="
    "NO_TRY_GOLD=YesPlease"
  ];
  terminalFlags = [ "TILES=" "SOUND=" ];
  tilesFlags = [
    "TILES=y"
    "SOUND=y"
    "COPY_FONTS=y"
    "SYS_PROPORTIONAL_FONT="
    "SYS_MONOSPACED_FONT="
  ];
  make = flags: "make -j1 ${lib.escapeShellArgs (crawlMakeFlags ++ flags)}";

  # Both frontends keep saves, scores, macros and caches in a private
  # per-user directory and leave HOME alone, so ~/.crawlrc and -rc still work.
  launcher = program: ''
    #!${runtimeShell}
    set -eu
    umask 077
    # Relative XDG_DATA_HOME values are ignored, as the XDG specification requires.
    case "''${XDG_DATA_HOME:-}" in
      /*) data_home=$XDG_DATA_HOME ;;
      *) data_home="''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share" ;;
    esac
    case "$data_home" in
      /*) ;;
      *) echo "gnollcrawl: state directory must be absolute: $data_home" >&2; exit 1 ;;
    esac
    state=$(${coreutils}/bin/realpath -m -- "$data_home/gnollcrawl")
    case "$state" in
      ${builtins.storeDir}|${builtins.storeDir}/*)
        echo "gnollcrawl: refusing state in the immutable store: $state" >&2; exit 1 ;;
    esac
    ${coreutils}/bin/mkdir -p "$data_home"
    ${coreutils}/bin/mkdir -p -m 700 "$state"
    if [ -L "$state" ] || [ ! -O "$state" ]; then
      echo "gnollcrawl: $state is not a directory owned by the current user" >&2
      exit 1
    fi
    ${coreutils}/bin/chmod 700 "$state"
    export CRAWL_DIR="$state/"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec ${program} "$@"
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "gnollcrawl";
  version = "0.19-GnollCrawlA";

  src = fetchurl {
    name = "gnollcrawl-${finalAttrs.version}.tar.gz";
    url = "https://codeload.github.com/Dracunos/gnollcrawl/tar.gz/a8ffd03080715e6321eadab873c62b14f58ff646";
    hash = "sha256-9nZn3GuJa6L1PkzWzqZlnUqTOKBv7e+3/552Cky3QdU=";
  };

  nativeBuildInputs = [ bison flex perl pkg-config which ];
  buildInputs = [
    lua5_1 ncurses sqlite zlib
    SDL2 SDL2_image SDL2_mixer freetype libpng libGL libGLU
  ];

  # This release mixes CRLF and LF in its C/C++ sources and Makefile.  Only
  # code is normalized, before the LF patch; data, fonts and docs stay exact.
  prePatch = ''
    find crawl-ref/source -type f \
      \( -name '*.cc' -o -name '*.h' -o -name '*.c' -o -name '*.cpp' \) \
      -exec sed -i 's/\r$//' {} +
    sed -i 's/\r$//' crawl-ref/source/Makefile
  '';

  # Macros default to CRAWL_DIR instead of HOME/.crawl.
  patches = [ ./platform.patch ];
  patchFlags = [ "-p1" "--fuzz=0" ];

  # The archive has no Git metadata, so pin the release version.  Modern
  # libstdc++ needs explicit <ostream> and <functional>.  Sort the generated
  # map list and drop the wall-clock stamp for reproducible output.  The Nix
  # stdenv provides cc, so the upstream HOST probe needs no change.
  postPatch = ''
    echo ${finalAttrs.version} > crawl-ref/source/util/release_ver
    substituteInPlace crawl-ref/source/domino.h \
      --replace-fail '#include <vector>' $'#include <vector>\n#include <ostream>'
    substituteInPlace crawl-ref/source/AppHdr.h \
      --replace-fail '#include <stdint.h>' $'#include <stdint.h>\n#include <functional>'
    substituteInPlace crawl-ref/source/Makefile \
      --replace-fail "find dat -name '*.des'|sed s:dat/::|" \
                     "find dat -name '*.des'|LC_ALL=C sort|sed s:dat/::|"
    substituteInPlace crawl-ref/source/version.cc \
      --replace-fail '__DATE__ " at " __TIME__' '"reproducible Nix build"'
    patchShebangs crawl-ref/source/util crawl-ref/source/test

    tar xf ${fonts} -C crawl-ref/source/contrib/fonts --strip-components=1

    # Separate trees: frontends and diagnostic builds must not share
    # objects, generated headers or selector-dependent .cflags.
    cp -r crawl-ref terminal
    cp -r crawl-ref tiles
  '';

  dontConfigure = true;
  enableParallelBuilding = false;

  # install-data stages the real data first: DATA_DIR_PATH has no source-tree
  # fallback, and the upstream tests run against it.
  buildPhase = ''
    runHook preBuild
    (cd terminal/source
     ${make terminalFlags} crawl docs
     ${make terminalFlags} install-data)
    (cd tiles/source
     ${make tilesFlags} crawl docs
     ${make tilesFlags} install-data)
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    scratch=$NIX_BUILD_TOP/test-state
    for entry in HOME:home XDG_CONFIG_HOME:config XDG_DATA_HOME:data \
                 XDG_CACHE_HOME:cache XDG_STATE_HOME:state \
                 XDG_RUNTIME_DIR:runtime TMPDIR:tmp; do
      dir=$scratch/''${entry#*:}
      mkdir -p "$dir"
      export "''${entry%%:*}=$dir"
    done
    chmod 700 "$XDG_RUNTIME_DIR"
    export TERM=xterm-256color
    export TERMINFO_DIRS=${ncurses}/share/terminfo

    # Upstream stress harness with its own defaults and fake_pty driver.
    mkdir -p $scratch/stress
    (cd terminal/source
     CRAWL_DIR=$scratch/stress ${make terminalFlags} nondebugtest)

    # Unit tests require the documented diagnostic macros.  This third tree
    # and its executable are never installed; its data stays in scratch.
    cp -r crawl-ref diagnostic
    mkdir -p $scratch/unit
    (cd diagnostic/source
     flags=(${lib.escapeShellArgs terminalFlags} 'EXTERNAL_DEFINES=-DDEBUG -DDEBUG_TESTS'
            "DATADIR=$scratch/unit-data")
     export CRAWL_DIR=$scratch/unit
     ${make [ ]} "''${flags[@]}" crawl docs
     ${make [ ]} "''${flags[@]}" install-data
     # The Lua test loader resolves scripts and fixtures via DATA_DIR_PATH.
     cp -r test $scratch/unit-data/test
     ${make [ ]} "''${flags[@]}" test-test)
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm555 terminal/source/crawl $out/libexec/gnollcrawl
    install -Dm555 tiles/source/crawl $out/libexec/gnollcrawl-tiles
    mkdir -p $out/bin
    cat > $out/bin/gnollcrawl <<'EOF'
    ${launcher "${placeholder "out"}/libexec/gnollcrawl"}
    EOF
    cat > $out/bin/gnollcrawl-tiles <<'EOF'
    ${launcher "${placeholder "out"}/libexec/gnollcrawl-tiles"}
    EOF
    chmod 555 $out/bin/gnollcrawl $out/bin/gnollcrawl-tiles

    doc=$out/share/doc/gnollcrawl
    install -Dm444 -t $doc README.md crawl-ref/INSTALL.txt \
      crawl-ref/licence.txt crawl-ref/CREDITS.txt
    cp -r tiles/docs $doc/docs
    mkdir -p $doc/license
    cp -r crawl-ref/docs/license/. $doc/license/
    install -Dm444 -t $doc/license/rltiles crawl-ref/source/rltiles/license.txt
    # Complete original copyright and permission headers.
    (cd crawl-ref/source
     install -Dm444 -t $doc/source-notices domino.cc domino.h domino_data.h \
       json.cc json.h worley.cc worley.h perlin.cc perlin.h pcg.cc platform.h)
    install -Dm444 ${apacheLicense} $doc/license/apache-2.0.txt
    install -Dm444 ${./font-licenses.txt} $doc/license/fonts.txt
    install -Dm444 ${./font-licenses.txt} \
      $out/share/gnollcrawl/dat/tiles/FONT-LICENSES.txt

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${runtimeShell} -n $out/bin/gnollcrawl
    ${runtimeShell} -n $out/bin/gnollcrawl-tiles
    test -s $out/share/gnollcrawl/dat/dlua/loadmaps.lua
    test -s $out/share/gnollcrawl/dat/tiles/DejaVuSans.ttf
    test -s $out/share/gnollcrawl/dat/tiles/DejaVuSansMono.ttf
    test -s $out/share/doc/gnollcrawl/license/fonts.txt
    test -s $out/share/doc/gnollcrawl/source-notices/pcg.cc
    scratch=$(mktemp -d)
    mkdir -p $scratch/home $scratch/data
    HOME=$scratch/home XDG_DATA_HOME=$scratch/data TERM=dumb \
      $out/bin/gnollcrawl -version > $scratch/version.txt
    grep -F '${finalAttrs.version}' $scratch/version.txt
    test -z "$(find $scratch/home -mindepth 1 -print -quit)"
    test "$(stat -c %a $scratch/data/gnollcrawl)" = 700
    runHook postInstallCheck
  '';

  passthru = { inherit fonts apacheLicense; };

  meta = {
    description = "Gnoll-focused Dungeon Crawl Stone Soup variant";
    longDescription = ''
      Gnollcrawl is an independently playable Dungeon Crawl Stone Soup
      variant with gnoll encounters, no experience gain and no hunger.  This
      package builds the terminal frontend (gnollcrawl) and the SDL2/OpenGL
      tiles frontend with sound (gnollcrawl-tiles), using the exact upstream
      DejaVu fonts.  Both keep saves, scores, macros and caches in private
      $XDG_DATA_HOME/gnollcrawl (default ~/.local/share/gnollcrawl); the
      original ~/.crawlrc lookup is unchanged.
    '';
    homepage = "https://github.com/Dracunos/gnollcrawl";
    # licence.txt grants GPL-2.0-or-later for the game; only part of the
    # artwork has a separate CC0 grant.  Installed notices cover the BSD
    # domino/platform, MIT json/worley, Apache-2.0 PCG and public-domain
    # parts, plus the Bitstream Vera and Arev font terms.
    license = [
      lib.licenses.gpl2Plus lib.licenses.bsd2 lib.licenses.bsd3
      lib.licenses.cc0 lib.licenses.publicDomain lib.licenses.mit
      lib.licenses.asl20 lib.licenses.bitstreamVera
      {
        fullName = "Arev Fonts License";
        url = "https://dejavu-fonts.github.io/License.html";
        free = true;
        redistributable = true;
      }
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "gnollcrawl";
  };
})
