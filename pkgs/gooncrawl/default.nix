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
    name = "gooncrawl-fonts-6d304697.tar.gz";
    url = "https://codeload.github.com/crawl/crawl-fonts/tar.gz/6d3046974f35189a679a4d84b254efe82d1653b3";
    hash = "sha256-KJpZIJ32kSUEHw5BIIlL+EjzPUa/6vFBxtpXHrgyxtc=";
  };

  # pcg.cc carries the Apache copyright notice but not the licence text.
  apacheLicense = fetchurl {
    name = "gooncrawl-apache-2.0.txt";
    url = "https://www.apache.org/licenses/LICENSE-2.0.txt";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };

  # The generated level parser embeds the GNU Bison skeleton, whose notice
  # refers to the GPL-3.0 text that the release does not ship.
  gplLicense = fetchurl {
    name = "gooncrawl-gpl-3.0.txt";
    url = "https://www.gnu.org/licenses/gpl-3.0.txt";
    hash = "sha256-OXLcl0T2SZ8Pmy2/dmlvKuetivmyPd5m1q+Gyd+zaYY=";
  };

  # Shared by every invocation of the upstream Makefile.  Empty SAVEDIR and
  # SHAREDDIR leave mutable state to CRAWL_DIR, which the launchers set.
  crawlMakeFlags = [
    "prefix=${placeholder "out"}"
    "DATADIR=${placeholder "out"}/share/gooncrawl"
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
  # ctest.cc looks its data up in the source tree, so the diagnostic build
  # clears the installation directories.
  diagnosticFlags = terminalFlags ++ [
    "prefix="
    "DATADIR="
    "EXTERNAL_DEFINES=-DDEBUG -DDEBUG_TESTS"
  ];
  make = jobs: flags:
    "make -j${jobs} ${lib.escapeShellArgs (crawlMakeFlags ++ flags)}";

  # Both frontends keep saves, scores, macros and caches in a private
  # per-user directory and leave HOME alone, so ~/.crawlrc and -rc still work.
  launcher = program: ''
    #!${runtimeShell}
    set -eu
    # Relative XDG_STATE_HOME values are ignored, as the XDG specification requires.
    case ''${XDG_STATE_HOME-} in
      /*) base=$XDG_STATE_HOME ;;
      *) case ''${HOME-} in
           /*) base=$HOME/.local/state ;;
           *) echo 'gooncrawl: an absolute HOME or XDG_STATE_HOME is required' >&2; exit 1 ;;
         esac ;;
    esac
    # Resolve .. and existing symlinks before any write.
    state=$(${coreutils}/bin/realpath -m -- "$base/gooncrawl")
    case $state in
      ${builtins.storeDir}|${builtins.storeDir}/*)
        echo 'gooncrawl: refusing state in the immutable store' >&2; exit 1 ;;
    esac
    ${coreutils}/bin/mkdir -p -- "$state/macros"
    export CRAWL_DIR="$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    # The macro default is HOME/.crawl; an explicit -macro still wins.
    macro_given=
    for arg do
      case $arg in
        -[mM][aA][cC][rR][oO]|--[mM][aA][cC][rR][oO]) macro_given=yes ;;
      esac
    done
    if [ -z "$macro_given" ]; then
      set -- -macro "$state/macros" "$@"
    fi
    exec ${program} "$@"
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "gooncrawl";
  version = "2.0";

  # The v2.0 commit, not the older default branch or the prebuilt ZIP assets.
  src = fetchurl {
    name = "gooncrawl-${finalAttrs.version}.tar.gz";
    url = "https://codeload.github.com/Floodkiller/crawl/tar.gz/eb805b9c1b92935c93094ffc5c19a99ba18839d8";
    hash = "sha256-W02WdmK+HRivq+Sl3KBkIqO4qRQdU25BLP+XC/LTKlY=";
  };

  nativeBuildInputs = [ bison flex perl pkg-config which ];
  buildInputs = [
    lua5_1 ncurses sqlite zlib
    SDL2 SDL2_image SDL2_mixer freetype libpng libGL libGLU
  ];

  patches = [
    # The Jester background starts with its intended staff, robe and pies.
    ./jester-equipment.patch
    # The upstream stress bots get past the pledge menu and load their helpers.
    ./stress-pledge.patch
    ./stress-lua-loader.patch
  ];
  patchFlags = [ "-p1" "--fuzz=0" ];

  # The archive has no Git metadata, so pin the release version.  Modern
  # libstdc++ needs an explicit <ostream>.  Drop the wall-clock stamp for
  # reproducible output.  The Nix stdenv provides cc, so the upstream HOST
  # probe needs no change.
  postPatch = ''
    echo v${finalAttrs.version} > crawl-ref/source/util/release_ver
    substituteInPlace crawl-ref/source/domino.h \
      --replace-fail '#include <vector>' $'#include <vector>\n#include <ostream>'
    substituteInPlace crawl-ref/source/version.cc \
      --replace-fail '" on " __DATE__ " at " __TIME__' '" (reproducible Nix build)"'
    patchShebangs crawl-ref/source/util crawl-ref/source/test

    tar xf ${fonts} -C crawl-ref/source/contrib/fonts --strip-components=1

    # Separate trees: frontends and diagnostic builds must not share
    # objects, generated headers or selector-dependent .cflags.
    cp -r crawl-ref terminal
    cp -r crawl-ref tiles
  '';

  dontConfigure = true;

  # install-data stages the real data first: DATA_DIR_PATH has no source-tree
  # fallback, and the upstream stress tests run against it.
  buildPhase = ''
    runHook preBuild
    (cd terminal/source
     ${make "$NIX_BUILD_CORES" terminalFlags} crawl docs
     ${make "1" terminalFlags} install-data)
    (cd tiles/source
     ${make "$NIX_BUILD_CORES" tilesFlags} crawl docs
     ${make "1" tilesFlags} install-data)
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

    # Unit tests require the documented diagnostic macros.  This third tree
    # and its executable are never installed.
    cp -r crawl-ref diagnostic
    mkdir -p $scratch/unit
    (cd diagnostic/source
     export CRAWL_DIR=$scratch/unit
     ${make "$NIX_BUILD_CORES" diagnosticFlags} crawl docs
     ${make "1" diagnosticFlags} test-test)

    # Upstream stress harness with its own seed, timeouts and fake_pty driver.
    mkdir -p $scratch/stress
    (cd terminal/source
     CRAWL_DIR=$scratch/stress ${make "1" terminalFlags} nondebugtest)
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm555 terminal/source/crawl $out/libexec/gooncrawl/gooncrawl
    install -Dm555 tiles/source/crawl $out/libexec/gooncrawl/gooncrawl-tiles
    mkdir -p $out/bin
    cat > $out/bin/gooncrawl <<'EOF'
    ${launcher "${placeholder "out"}/libexec/gooncrawl/gooncrawl"}
    EOF
    cat > $out/bin/gooncrawl-tiles <<'EOF'
    ${launcher "${placeholder "out"}/libexec/gooncrawl/gooncrawl-tiles"}
    EOF
    chmod 555 $out/bin/gooncrawl $out/bin/gooncrawl-tiles

    data=$out/share/gooncrawl
    mkdir -p $data/docs/gooncrawl
    cp -r crawl-ref/docs/gooncrawl/. $data/docs/gooncrawl/

    doc=$out/share/doc/gooncrawl
    # The upstream Unix install-data omits the operative licence grant.
    install -Dm444 -t $doc README.md crawl-ref/INSTALL.txt \
      crawl-ref/licence.txt crawl-ref/CREDITS.txt
    cp -r tiles/docs $doc/docs
    mkdir -p $doc/license
    cp -r crawl-ref/docs/license/. $doc/license/
    install -Dm444 -t $doc/license/rltiles crawl-ref/source/rltiles/license.txt
    # Complete original copyright and permission headers.
    (cd crawl-ref/source
     install -Dm444 -t $doc/source-notices domino.cc domino.h domino-data.h \
       json.cc json.h worley.cc worley.h perlin.cc perlin.h pcg.cc platform.h \
       wcwidth.cc)
    install -Dm444 ${apacheLicense} $doc/license/apache-2.0.txt
    install -Dm444 ${gplLicense} $doc/license/gpl-3.0.txt
    install -Dm444 ${./font-notices.txt} $doc/license/fonts.txt
    install -Dm444 ${./font-notices.txt} $data/dat/tiles/FONT-LICENSES.txt

    runHook postInstall
  '';

  # The installed launcher prints the pinned version from a private state
  # root and leaves the supplied HOME untouched.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${runtimeShell} -n $out/bin/gooncrawl
    ${runtimeShell} -n $out/bin/gooncrawl-tiles
    test -s $out/share/gooncrawl/dat/dlua/loadmaps.lua
    test -s $out/share/gooncrawl/dat/tiles/DejaVuSans.ttf
    test -s $out/share/gooncrawl/dat/tiles/DejaVuSansMono.ttf
    test -s $out/share/gooncrawl/docs/gooncrawl/changelog.txt
    test -s $out/share/doc/gooncrawl/license/fonts.txt
    test -s $out/share/doc/gooncrawl/source-notices/pcg.cc
    scratch=$(mktemp -d)
    mkdir -p $scratch/home $scratch/state
    HOME=$scratch/home XDG_STATE_HOME=$scratch/state TERM=dumb \
      $out/bin/gooncrawl -version > $scratch/version.txt
    grep -F 'Crawl version v${finalAttrs.version}' $scratch/version.txt
    grep -F 'reproducible Nix build' $scratch/version.txt
    test -z "$(find $scratch/home -mindepth 1 -print -quit)"
    test -d $scratch/state/gooncrawl/macros
    runHook postInstallCheck
  '';

  passthru = { inherit fonts apacheLicense gplLicense; };

  meta = {
    description = "Dungeon Crawl Stone Soup variant with restored and new features";
    longDescription = ''
      Gooncrawl is an independently playable Dungeon Crawl Stone Soup variant
      with restored content, additional species and gods, and other gameplay
      changes.  This package builds the terminal frontend (gooncrawl) and the
      SDL2/OpenGL tiles frontend with sound (gooncrawl-tiles), using the exact
      upstream DejaVu fonts.  Both keep saves, scores, macros and caches in
      $XDG_STATE_HOME/gooncrawl (default ~/.local/state/gooncrawl); the
      original ~/.crawlrc lookup and command-line options are unchanged.  The
      Webtiles server is not packaged.
    '';
    homepage = "https://github.com/Floodkiller/crawl";
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
    mainProgram = "gooncrawl";
  };
})
