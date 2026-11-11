{
  lib,
  stdenv,
  fetchurl,
  bison,
  flex,
  perl,
  pkg-config,
  python3,
  which,
  coreutils,
  runtimeShell,
  lua5_1,
  ncurses,
  sqlite,
  zlib,
}:

let
  # pcg.cc names Apache 2.0, but the release omits the full licence text.
  apacheLicense = fetchurl {
    url = "https://www.apache.org/licenses/LICENSE-2.0.txt";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };

  terminfo = "${ncurses}/share/terminfo";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "stoat-soup";
  version = "0.23-ish-aug26";

  # Release tag commit 5df72bd44e7113642e311008665fafda6c7baa8c; this is the
  # same codeload archive the Guix package pins.
  src = fetchurl {
    url = "https://codeload.github.com/damerell/crawl/tar.gz/refs/tags/${finalAttrs.version}";
    name = "stoat-soup-${finalAttrs.version}.tar.gz";
    hash = "sha256-UKD9aog21SLvhMN4nfhZgbcDzEQa4lUkVzMuWhreEz4=";
  };

  sourceRoot = "crawl-${finalAttrs.version}/crawl-ref/source";

  # The archive has no .git, so record the release version explicitly.
  # builddb (a prerequisite of nondebugtest) would otherwise write macros
  # to HOME/.crawl even with CRAWL_DIR set.
  postPatch = ''
    echo ${finalAttrs.version} > util/release_ver
    substituteInPlace Makefile \
      --replace-fail "HOST := \$(shell sh -c 'cc -dumpmachine || echo unknown')" \
                     "HOST := \$(shell sh -c 'gcc -dumpmachine || echo unknown')" \
      --replace-fail './$(GAME) --builddb' './$(GAME) -macro "$$CRAWL_DIR" --builddb'
    patchShebangs util test/stress
  '';

  nativeBuildInputs = [
    bison
    flex
    perl
    pkg-config
    (python3.withPackages (ps: [ ps.pyyaml ]))
    which
  ];

  buildInputs = [
    lua5_1
    ncurses
    sqlite
    zlib
  ];

  # Console build only: no tiles, sound or bundled Lua/SQLite/zlib/PCRE.
  makeFlags = [
    "prefix=${placeholder "out"}"
    "DATADIR=${placeholder "out"}/share/stoat-soup"
    "SAVEDIR="
    "SHAREDDIR="
    "SQLITE_INCLUDE_DIR=${lib.getDev sqlite}/include"
    # SQLITE_LIB keeps the Makefile default -lsqlite3; the cc wrapper
    # supplies the library path (makeFlags entries cannot contain spaces).
    "FORCE_CC=gcc"
    "FORCE_CXX=g++"
    "LUA_PACKAGE=lua5.1"
    "TILES="
    "BUILD_LUA="
    "BUILD_SQLITE="
    "BUILD_ZLIB="
    "USE_PCRE="
    "NO_TRY_GOLD=YesPlease"
  ];

  # Keep the template-heavy C++ build and the stress targets sequential.
  enableParallelBuilding = false;

  # DATA_DIR_PATH is compiled in without a source-tree fallback, so stage
  # the real install-data before the stress suite reads it.
  buildPhase = ''
    runHook preBuild
    make -j1 crawl docs "''${makeFlagsArray[@]}" $makeFlags
    make -j1 install-data "''${makeFlagsArray[@]}" $makeFlags
    runHook postBuild
  '';

  doCheck = true;
  # Upstream's full nondebugtest stress suite under util/fake_pty, with all
  # mutable files redirected into a scratch tree.
  checkPhase = ''
    runHook preCheck
    scratch=$PWD/test-state
    for d in home config data cache state runtime tmp; do mkdir -p "$scratch/$d"; done
    chmod 700 "$scratch/runtime"
    export HOME=$scratch/home XDG_CONFIG_HOME=$scratch/config \
      XDG_DATA_HOME=$scratch/data XDG_CACHE_HOME=$scratch/cache \
      XDG_STATE_HOME=$scratch/state XDG_RUNTIME_DIR=$scratch/runtime \
      TMPDIR=$scratch/tmp
    state=$scratch/state/stoat-soup
    mkdir -p "$state"
    export CRAWL_DIR=$state TERM=xterm-256color TERMINFO_DIRS=${terminfo}
    export CRAWL="timeout 595 ./crawl -macro $state -dir $state -seed 1 -no-save -name test -wizard -no-throttle"
    make -j1 nondebugtest "''${makeFlagsArray[@]}" $makeFlags
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    doc=$out/share/doc/stoat-soup
    install -Dm555 crawl $out/libexec/stoat-soup
    install -Dm444 -t $doc ../../LICENCE ../../README.md ../INSTALL.md ../CREDITS.txt
    cp -r ../docs $doc/docs
    cp -r ../docs/license $doc/license
    cp -r ../stoat-docs $doc/stoat-docs
    # These notices live in source headers rather than docs/license.
    install -Dm444 -t $doc/source-notices \
      json.cc json.h pcg.cc perlin.cc perlin.h worley.cc worley.h \
      domino.cc domino.h domino-data.h
    install -Dm444 ${apacheLicense} $doc/license/apache-2.0.txt

    mkdir -p $out/bin
    cat > $out/bin/stoat-soup <<EOF
    #!${runtimeShell}
    set -eu
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/stoat-soup"
    ${coreutils}/bin/mkdir -p "\$state"
    export CRAWL_DIR="\$state"
    export TERMINFO_DIRS="${terminfo}\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    # Inspectors such as --edit-save consume all remaining arguments, so the
    # state options come first.
    exec $out/libexec/stoat-soup -macro "\$state" -dir "\$state" "\$@"
    EOF
    chmod 555 $out/bin/stoat-soup
    runHook postInstall
  '';

  meta = {
    description = "Console Stoat Soup roguelike, a Dungeon Crawl Stone Soup variant";
    longDescription = ''
      Stoat Soup is an independently playable variant of Dungeon Crawl Stone
      Soup.  This package builds the console frontend of the pinned release
      against external Lua 5.1, ncurses, SQLite and zlib.  The launcher keeps
      saves, scores, macros and compiled caches in
      $XDG_STATE_HOME/stoat-soup, falling back to
      $HOME/.local/state/stoat-soup.
    '';
    homepage = "https://github.com/damerell/crawl";
    # Main game GPL-2.0+; domino and named contributions BSD-2; json and
    # worley MIT; perlin public domain/CC0; pcg Apache-2.0.  The MSVC
    # stdint (BSD-3), tiles/SDL, libpng and PCRE code are not built.
    license = with lib.licenses; [
      gpl2Plus
      bsd2
      mit
      publicDomain
      cc0
      asl20
    ];
    mainProgram = "stoat-soup";
    platforms = [ "x86_64-linux" ];
  };
})
