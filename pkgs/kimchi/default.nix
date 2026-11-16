{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, bison
, flex
, perl
, pkg-config
, which
, python3
, lua5_1
, ncurses
, sqlite
, zlib
, coreutils
, runtimeShell
}:

let
  # pcg.cc identifies Apache 2.0, but the release omits the licence text.
  apacheLicense = fetchurl {
    name = "kimchi-apache-2.0.txt";
    url = "https://www.apache.org/licenses/LICENSE-2.0.txt";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };

  # Shared by every invocation of the upstream Makefile.  The empty selectors
  # build the console frontend from system libraries only; empty SAVEDIR and
  # SHAREDDIR leave mutable state to CRAWL_DIR, which the launcher sets.
  crawlMakeFlags = [
    "prefix=${placeholder "out"}"
    "DATADIR=${placeholder "out"}/share/kimchi"
    "SAVEDIR="
    "SHAREDDIR="
    "SQLITE_INCLUDE_DIR=${lib.getDev sqlite}/include"
    "SQLITE_LIB=-lsqlite3"
    "FORCE_CC=${stdenv.cc.targetPrefix}cc"
    "FORCE_CXX=${stdenv.cc.targetPrefix}c++"
    "LUA_PACKAGE=lua-5.1"
    "TILES="
    "WEBTILES="
    "SOUND="
    "BUILD_ALL="
    "COPY_FONTS="
    "BUILD_LUA="
    "BUILD_SQLITE="
    "BUILD_ZLIB="
    "USE_PCRE="
    "NO_TRY_LLD=YesPlease"
    "NO_TRY_GOLD=YesPlease"
  ];
  make = jobs: "make -j${jobs} ${lib.escapeShellArgs crawlMakeFlags}";

  # The species generator runs under the unversioned python name; the stress
  # adapter runs under python3.
  buildPython = python3.withPackages (ps: [ ps.pyyaml ]);
in
stdenv.mkDerivation (finalAttrs: {
  pname = "kimchi";
  version = "1.3.2";

  # The kimchi-1.3.2 tag, without submodules.
  src = fetchFromGitHub {
    owner = "kimjoy2002";
    repo = "crawl";
    rev = "8f533dcfe5fe76833cb636531bae56e3bf106556";
    hash = "sha256-XKYHesz1RqGABDHdTR5RPoLCMeztvgtEnzgsQt/B+dw=";
  };

  sourceRoot = "${finalAttrs.src.name}/crawl-ref/source";

  # The docs target writes into ../docs, outside the source root.
  postUnpack = ''
    chmod -R u+w ${finalAttrs.src.name}
  '';

  nativeBuildInputs = [ bison flex perl pkg-config which buildPython ];
  buildInputs = [ lua5_1 ncurses sqlite zlib ];

  # The fetched tree has no .git, so pin the generated version string.  Python
  # 3.10 removed collections.MutableMapping, and modern libstdc++ needs an
  # explicit <ostream>.
  #
  # The fork shows an Artificer equipment menu before the upstream stress bots
  # start.  stress-pty.py replaces fake_pty for the tests and answers that one
  # prompt with the original bundle of wands.  builddb gets the macro path so
  # it does not create HOME/.crawl.
  postPatch = ''
    echo kimchi-${finalAttrs.version} > util/release_ver
    substituteInPlace util/species-gen.py \
      --replace-fail 'class Species(collections.MutableMapping):' \
        $'from collections.abc import MutableMapping\n\nclass Species(MutableMapping):'
    substituteInPlace domino.h \
      --replace-fail '#include <vector>' $'#include <vector>\n#include <ostream>'

    cp ${./stress-pty.py} util/kimchi-stress-pty.py
    substituteInPlace Makefile \
      --replace-fail 'util/fake_pty test/stress/run' \
        'python3 util/kimchi-stress-pty.py test/stress/run' \
      --replace-fail './$(GAME) --builddb' './$(GAME) -macro "$$CRAWL_DIR" --builddb'
    patchShebangs util test
  '';

  dontConfigure = true;

  # install-data stages the real data first: DATA_DIR_PATH has no source-tree
  # fallback, and the upstream stress tests run against it.
  buildPhase = ''
    runHook preBuild
    ${make "$NIX_BUILD_CORES"} crawl docs
    ${make "1"} install-data
    runHook postBuild
  '';

  # The upstream stress suite with its own seed and all ten fixtures.
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
    state=$scratch/state/kimchi
    mkdir -p "$state"
    export CRAWL_DIR=$state
    export TERM=xterm-256color
    export TERMINFO_DIRS=${ncurses}/share/terminfo
    export CRAWL="timeout --foreground 595 ./crawl -macro $state -dir $state -seed 1 -no-save -name test -wizard -no-throttle"
    ${make "1"} nondebugtest
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm555 crawl $out/libexec/kimchi

    doc=$out/share/doc/kimchi
    install -Dm444 -t $doc ../../LICENSE ../INSTALL.txt ../CREDITS.txt
    cp -r $out/share/kimchi/docs $doc/docs
    mkdir -p $doc/license
    cp -r ../docs/license/. $doc/license/
    # Complete original copyright and permission headers.
    (cd ${finalAttrs.src}/crawl-ref/source
     install -Dm444 -t $doc/source-notices json.cc json.h pcg.cc \
       perlin.cc perlin.h worley.cc worley.h \
       domino.cc domino.h domino-data.h platform.h)
    install -Dm444 ${apacheLicense} $doc/license/apache-2.0.txt

    mkdir -p $out/bin
    cat > $out/bin/kimchi <<'EOF'
    #!${runtimeShell}
    set -eu
    state="''${XDG_DATA_HOME:-''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/kimchi"
    ${coreutils}/bin/mkdir -p "$state"
    export CRAWL_DIR="$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    # Inspectors such as --edit-save consume all remaining arguments, so the
    # defaults come first.
    exec ${placeholder "out"}/libexec/kimchi -macro "$state" -dir "$state" "$@"
    EOF
    chmod 555 $out/bin/kimchi

    runHook postInstall
  '';

  # The installed launcher prints the pinned version from a private data root
  # and leaves the supplied HOME untouched.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${runtimeShell} -n $out/bin/kimchi
    test -s $out/share/kimchi/dat/dlua/loadmaps.lua
    test -s $out/share/doc/kimchi/LICENSE
    test -s $out/share/doc/kimchi/license/apache-2.0.txt
    test -s $out/share/doc/kimchi/source-notices/pcg.cc
    scratch=$(mktemp -d)
    mkdir -p $scratch/home $scratch/data
    HOME=$scratch/home XDG_DATA_HOME=$scratch/data TERM=dumb \
      $out/bin/kimchi -version > $scratch/version.txt
    grep -F 'Crawl version kimchi-${finalAttrs.version}' $scratch/version.txt
    test -z "$(find $scratch/home -mindepth 1 -print -quit)"
    test -d $scratch/data/kimchi
    runHook postInstallCheck
  '';

  passthru = { inherit apacheLicense; };

  meta = {
    description = "Korean console Dungeon Crawl Stone Soup variant";
    longDescription = ''
      Kimchi is an independently playable Korean variant of Dungeon Crawl
      Stone Soup, based on the 0.24 series.  This package builds the console
      frontend of the pinned release with the complete console game data and
      upstream documentation, without the graphical submodules.  The kimchi
      launcher keeps saves, scores, macros and compiled caches in
      $XDG_DATA_HOME/kimchi (default ~/.local/share/kimchi) and forwards the
      game's own options.
    '';
    homepage = "https://github.com/kimjoy2002/crawl";
    # The game is GPL-2.0-or-later; domino and named historical contributions
    # are BSD-2, json and worley MIT, perlin public domain/CC0, pcg Apache-2.0.
    license = with lib.licenses; [ gpl2Plus bsd2 mit publicDomain cc0 asl20 ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "kimchi";
  };
})
