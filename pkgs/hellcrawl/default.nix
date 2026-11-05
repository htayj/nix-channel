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
    "DATADIR=${placeholder "out"}/share/hellcrawl"
    "SQLITE_INCLUDE_DIR=${lib.getDev sqlite}/include"
    "SQLITE_LIB=-lsqlite3"
    "FORCE_CC=${stdenv.cc.targetPrefix}cc"
    "FORCE_CXX=${stdenv.cc.targetPrefix}c++"
    "LUA_PACKAGE=lua-5.1"
    "TILES="
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "hellcrawl";
  version = "5.7";

  src = fetchFromGitHub {
    owner = "Hellmonk";
    repo = "hellcrawl";
    rev = "8abd87763372e1c1be472510ac55faeff7b0dca7";
    hash = "sha256-6bCnOCXeV1ysgW3XCU0wDMPh2deb2lCL0GcGz+VIpYA=";
  };

  sourceRoot = "${finalAttrs.src.name}/crawl-ref/source";

  nativeBuildInputs = [ bison flex perl pkg-config which ];
  buildInputs = [ lua5_1 ncurses sqlite zlib ];

  # The fetched tree has no .git, so pin the generated version string, and
  # add the header that modern libstdc++ no longer pulls in transitively.
  postPatch = ''
    echo ${finalAttrs.version} > util/release_ver
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
    install -Dm555 crawl $out/libexec/hellcrawl

    doc=$out/share/doc/hellcrawl
    install -Dm444 -t $doc ../licence.txt ../CREDITS.txt
    install -Dm444 -t $doc/license ../docs/license/* rltiles/license.txt

    mkdir -p $out/bin
    cat > $out/bin/hellcrawl <<'EOF'
    #!${runtimeShell}
    set -eu
    state="''${XDG_DATA_HOME:-''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/hellcrawl"
    ${coreutils}/bin/mkdir -p "$state"
    export CRAWL_DIR="$state"
    # The game also has legacy ~/.crawl lookups, so keep them in the same root.
    export HOME="$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec ${placeholder "out"}/libexec/hellcrawl "$@"
    EOF
    chmod 555 $out/bin/hellcrawl

    runHook postInstall
  '';

  meta = {
    description = "Terminal fork of Dungeon Crawl Stone Soup";
    longDescription = ''
      Hellcrawl is an independently playable, streamlined fork of Dungeon
      Crawl Stone Soup.  This package builds its console frontend.  The
      hellcrawl launcher keeps saves, logs and other mutable state in
      $XDG_DATA_HOME/hellcrawl (default ~/.local/share/hellcrawl).
    '';
    homepage = "https://github.com/Hellmonk/hellcrawl";
    # Console code and data are GPL-2.0-or-later; bundled perlin, json,
    # worley and pcg sources carry the remaining licenses.
    license = with lib.licenses; [ gpl2Plus bsd2 cc0 publicDomain mit asl20 ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "hellcrawl";
  };
})
