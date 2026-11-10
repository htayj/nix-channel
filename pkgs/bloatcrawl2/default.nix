{ lib
, stdenv
, fetchgit
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
  # Shared by the build and install-data invocations of the upstream Makefile.
  # An empty TILES selects the console frontend without SDL, fonts or sound.
  crawlMakeFlags = [
    "DATADIR=${placeholder "out"}/share/bloatcrawl2"
    "SQLITE_INCLUDE_DIR=${lib.getDev sqlite}/include"
    "SQLITE_LIB=-lsqlite3"
    "FORCE_CC=${stdenv.cc.targetPrefix}cc"
    "FORCE_CXX=${stdenv.cc.targetPrefix}c++"
    "LUA_PACKAGE=lua-5.1"
    "TILES="
    "NO_TRY_LLD=YesPlease"
    "NO_TRY_GOLD=YesPlease"
  ];

  # The species and YAML generators run under the unversioned python name.
  buildPython = python3.withPackages (ps: [ ps.pyyaml ]);
in
stdenv.mkDerivation (finalAttrs: {
  pname = "bloatcrawl2";
  version = "2.2.0";

  # The 2.2.0 tag, fetched like Guix git-fetch: no .git and no submodules.
  src = fetchgit {
    name = "bloatcrawl2-${finalAttrs.version}-source";
    url = "https://github.com/Hellmonk/bloatcrawl2";
    rev = "ff89137ce52d26b891517517c0aec9013ed8bea5";
    fetchSubmodules = false;
    hash = "sha256-RuFpxreSHs+5MSXMpyAS8jRTXTyX3gPkhQEXaJFFjaQ=";
  };

  sourceRoot = "${finalAttrs.src.name}/crawl-ref/source";

  nativeBuildInputs = [ bison flex perl pkg-config which buildPython ];
  buildInputs = [ lua5_1 ncurses sqlite zlib ];

  # The fetched tree has no .git, so pin the generated version string.  Python
  # 3.10 removed collections.MutableMapping, and modern libstdc++ no longer
  # declares iswalnum through the headers ui.cc includes.
  postPatch = ''
    echo ${finalAttrs.version} > util/release_ver
    patchShebangs util
    substituteInPlace util/species-gen.py \
      --replace-fail 'class Species(collections.MutableMapping):' \
        $'from collections.abc import MutableMapping\n\nclass Species(MutableMapping):'
    substituteInPlace ui.cc --replace-fail '#include <chrono>' $'#include <chrono>\n#include <cwctype>'
  '';

  dontConfigure = true;

  makeFlags = crawlMakeFlags;
  buildFlags = [ "crawl" ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    make install-data prefix=$out ${lib.escapeShellArgs crawlMakeFlags}
    install -Dm555 crawl $out/libexec/bloatcrawl2

    doc=$out/share/doc/bloatcrawl2
    install -Dm444 -t $doc ../../LICENSE ../CREDITS.txt
    install -Dm444 -t $doc/license ../docs/license/* rltiles/license.txt

    mkdir -p $out/bin
    cat > $out/bin/bloatcrawl2 <<'EOF'
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
      *) echo "bloatcrawl2: state directory must be absolute: $data_home" >&2; exit 1 ;;
    esac
    state=$data_home/bloatcrawl2
    ${coreutils}/bin/mkdir -p "$data_home"
    ${coreutils}/bin/mkdir -p -m 700 "$state"
    if [ -L "$state" ] || [ ! -O "$state" ]; then
      echo "bloatcrawl2: $state is not a directory owned by the current user" >&2
      exit 1
    fi
    ${coreutils}/bin/chmod 700 "$state"
    export CRAWL_DIR="$state/"
    # The game also creates a legacy ~/.crawl directory, so keep it in the same root.
    export HOME="$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec ${placeholder "out"}/libexec/bloatcrawl2 "$@"
    EOF
    chmod 555 $out/bin/bloatcrawl2

    runHook postInstall
  '';

  # The installed launcher prints the pinned version from a private data root
  # and leaves the supplied HOME untouched.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${runtimeShell} -n $out/bin/bloatcrawl2
    test -d $out/share/bloatcrawl2/dat
    test -s $out/share/doc/bloatcrawl2/LICENSE
    test -s $out/share/doc/bloatcrawl2/license/license.txt
    scratch=$(mktemp -d)
    mkdir -p $scratch/home $scratch/data
    HOME=$scratch/home XDG_DATA_HOME=$scratch/data TERM=dumb \
      $out/bin/bloatcrawl2 -version > $scratch/version.txt
    grep -F '${finalAttrs.version}' $scratch/version.txt
    test -z "$(find $scratch/home -mindepth 1 -print -quit)"
    test "$(stat -c %a $scratch/data/bloatcrawl2)" = 700
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal fork of Dungeon Crawl Stone Soup";
    longDescription = ''
      Bloatcrawl 2 is an independently playable fork of Dungeon Crawl Stone
      Soup.  This package builds its console frontend only.  The bloatcrawl2
      launcher keeps saves, scores and other mutable state in private
      $XDG_DATA_HOME/bloatcrawl2 (default ~/.local/share/bloatcrawl2).
    '';
    homepage = "https://github.com/Hellmonk/bloatcrawl2";
    # LICENSE grants GPL-2.0-or-later for the combined program; the installed
    # notices cover the bundled CC0/public-domain data and the BSD, MIT,
    # Apache-2.0, zlib, LGPL-2.1, Boost, libpng and PCRE2 (BSD-3) components.
    # Spelled out because the zlib package argument would shadow lib.licenses.zlib.
    license = [
      lib.licenses.gpl2Plus lib.licenses.cc0 lib.licenses.publicDomain
      lib.licenses.bsd2 lib.licenses.bsd3 lib.licenses.mit lib.licenses.asl20
      lib.licenses.zlib lib.licenses.lgpl21Plus lib.licenses.boost
      lib.licenses.libpng
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "bloatcrawl2";
  };
})
