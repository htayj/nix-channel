{ lib
, stdenv
, fetchFromGitHub
, bison
, flex
, perl
, pkg-config
, which
, lua5_1
, ncurses
, sqlite
, zlib
, coreutils
, runtimeShell
}:

let
  # Shared by the build and install-data invocations of the upstream Makefile.
  # An empty TILES selects the console frontend without SDL, fonts or sound.
  crawlMakeFlags = [
    "DATADIR=${placeholder "out"}/share/bcrawl"
    "SQLITE_INCLUDE_DIR=${lib.getDev sqlite}/include"
    "SQLITE_LIB=-lsqlite3"
    "FORCE_CC=${stdenv.cc.targetPrefix}cc"
    "FORCE_CXX=${stdenv.cc.targetPrefix}c++"
    "LUA_PACKAGE=lua-5.1"
    "TILES="
    "NO_TRY_LLD=YesPlease"
    "NO_TRY_GOLD=YesPlease"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "bcrawl";
  version = "1.42.1";

  # The bcrawl-1.42.1 tag.
  src = fetchFromGitHub {
    owner = "b-crawl";
    repo = "bcrawl";
    rev = "d9800d219b5e0ab840c8065e44f875fa19dd63ff";
    hash = "sha256-fVtL+6zlJOzec+9e7FADcuZp2Ld2tvf+zgB/eYfDx8o=";
  };

  sourceRoot = "${finalAttrs.src.name}/crawl-ref/source";

  nativeBuildInputs = [ bison flex perl pkg-config which ];
  buildInputs = [ lua5_1 ncurses sqlite zlib ];

  # The fetched tree has no .git, so pin the generated version string, and
  # add the header that modern libstdc++ no longer pulls in transitively.
  postPatch = ''
    echo bcrawl-${finalAttrs.version} > util/release_ver
    patchShebangs util
    substituteInPlace domino.h --replace-fail '#include <vector>' $'#include <vector>\n#include <ostream>'
  '';

  dontConfigure = true;

  makeFlags = crawlMakeFlags;
  buildFlags = [ "crawl" ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    make install-data prefix=$out ${lib.escapeShellArgs crawlMakeFlags}
    install -Dm555 crawl $out/libexec/bcrawl

    doc=$out/share/doc/bcrawl
    install -Dm444 -t $doc ../../LICENSE ../CREDITS.txt
    install -Dm444 -t $doc/license ../docs/license/* rltiles/license.txt

    mkdir -p $out/bin
    cat > $out/bin/bcrawl <<'EOF'
    #!${runtimeShell}
    set -eu
    state="''${XDG_DATA_HOME:-''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/bcrawl"
    ${coreutils}/bin/mkdir -p "$state"
    export CRAWL_DIR="$state"
    # The game also has legacy ~/.crawl and ~/.crawlrc lookups, so keep them in the same root.
    export HOME="$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec ${placeholder "out"}/libexec/bcrawl "$@"
    EOF
    chmod 555 $out/bin/bcrawl

    runHook postInstall
  '';

  # The installed launcher prints the pinned version from a private data
  # root and leaves the supplied HOME untouched.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    scratch=$(mktemp -d)
    mkdir -p $scratch/home $scratch/data
    HOME=$scratch/home XDG_DATA_HOME=$scratch/data TERM=dumb \
      $out/bin/bcrawl -version > $scratch/version.txt
    grep -F '${finalAttrs.version}' $scratch/version.txt
    test -z "$(find $scratch/home -mindepth 1 -print -quit)"
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal fork of Dungeon Crawl Stone Soup";
    longDescription = ''
      Bcrawl is an independently playable fork of Dungeon Crawl Stone Soup.
      This package builds its console frontend only.  The bcrawl launcher
      keeps saves, scores and other mutable state in $XDG_DATA_HOME/bcrawl
      (default ~/.local/share/bcrawl).
    '';
    homepage = "https://github.com/b-crawl/bcrawl";
    # LICENSE grants GPL-2.0-or-later for the combined program; the copied
    # notices cover the bundled CC0 data and the BSD, MIT, Apache-2.0, zlib,
    # libpng and LGPL-2.1 components.
    # Spelled out because the zlib package argument would shadow lib.licenses.zlib.
    license = [
      lib.licenses.gpl2Plus lib.licenses.cc0 lib.licenses.bsd2 lib.licenses.bsd3
      lib.licenses.mit lib.licenses.asl20 lib.licenses.zlib lib.licenses.libpng
      lib.licenses.lgpl21Plus
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "bcrawl";
  };
})
