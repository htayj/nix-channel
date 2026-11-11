{ lib, stdenv, fetchFromGitHub, fetchurl, runtimeShell, coreutils, gzip, groff, util-linux, ncurses }:

let
  # The build expects exactly lib/lua-5.4.2; Nixpkgs only carries later 5.4
  # releases, so the matching upstream tarball is pinned separately.
  luaSrc = fetchurl {
    url = "https://www.lua.org/ftp/lua-5.4.2.tar.gz";
    hash = "sha256-EVcNl+nXMDwKWVZ+0ax8ZINAzQ2xDV/VlMCSI+8vUk8=";
  };
in
stdenv.mkDerivation {
  pname = "splicehack-rewrite";
  version = "0.8.2-0.0cf23cb";

  src = fetchFromGitHub {
    owner = "RojjaCebolla";
    repo = "SpliceHack-Rewrite";
    rev = "0cf23cb19eedd6b985502b1b8fdc86fd249a8172";
    hash = "sha256-7iRLmQtNiAqU//e4rFGdexMmMyRbcVwvW0TQo5hVn44=";
  };

  nativeBuildInputs = [ groff util-linux ];
  buildInputs = [ ncurses ];

  postPatch = ''
    # Fail when an edited pattern does not occur exactly as often as expected.
    expect_count() {
      local actual
      actual=$(grep -cE -- "$3" "$2" || true)
      if [ "$actual" != "$1" ]; then
        echo "expected $1 match(es) of '$3' in $2, found $actual" >&2
        exit 1
      fi
    }

    mkdir -p lib
    tar xzf ${luaSrc} -C lib
    test -f lib/lua-5.4.2/src/lua.h

    # Empty attribute macros break glibc's __has_attribute expansion.
    expect_count 2 include/tradstdc.h '^#define (__warn_unused_result__|warn_unused_result) /\*empty\*/'
    sed -i -E '/^#define (__warn_unused_result__|warn_unused_result) \/\*empty\*\//d' include/tradstdc.h

    # windows.c defines livelog_dump_url unconditionally and end.c always
    # calls it; declare it outside the conditional block.
    expect_count 1 include/extern.h '^extern void livelog_dump_url\(unsigned int\);[[:space:]]*$'
    expect_count 1 include/extern.h '^extern void dump_open_log\(time_t\);[[:space:]]*$'
    sed -i -E \
      -e '/^extern void livelog_dump_url\(unsigned int\);[[:space:]]*$/d' \
      -e 's/^extern void dump_open_log\(time_t\);[[:space:]]*$/extern void livelog_dump_url(unsigned int);\n&/' \
      include/extern.h
    expect_count 1 include/extern.h '^extern void livelog_dump_url\(unsigned int\);$'

    # Pirate speech is gameplay; the dump-log guard must not hide its helpers.
    expect_count 2 src/pline.c "^/\\*Ben Collver's fixes\\*/[[:space:]]*$"
    expect_count 1 src/pline.c '^/\* keep the most recent DUMPLOG_MSG_COUNT messages \*/[[:space:]]*$'
    awk '
      /^\/\*Ben Collver.s fixes\*\/[[:space:]]*$/ && !closed { print "#endif"; closed = 1 }
      /^\/\* keep the most recent DUMPLOG_MSG_COUNT messages \*\/[[:space:]]*$/ { print "#if defined(DUMPLOG) || defined(DUMPHTML)" }
      { print }
    ' src/pline.c > src/pline.c.new
    mv src/pline.c.new src/pline.c

    # Ten records name glyphs absent from this rewrite's symbol vocabulary.
    stale='^[[:blank:]]*S_(furnace|buzzsaw_trap|whirlwind_trap|ice_block_trap|sin|zouthern):'
    expect_count 10 dat/symbols "$stale"
    sed -i -E "/$stale/d" dat/symbols

    # Per-user configuration instead of a global sysconf; the launcher
    # supplies private writable state while HACKDIR stays immutable.
    expect_count 1 include/config.h '^#define SYSCF([[:space:]]|$)'
    expect_count 1 include/config.h '^#define SYSCF_FILE[[:space:]]'
    sed -i -E \
      -e 's|^#define SYSCF([[:space:]]\|$).*$|/* #define SYSCF */|' \
      -e 's|^#define SYSCF_FILE[[:space:]].*$|/* #define SYSCF_FILE */|' \
      include/config.h
    expect_count 1 include/unixconf.h '^/\*[[:space:]]+#define VAR_PLAYGROUND'
    sed -i -E 's|^/\*[[:space:]]+#define VAR_PLAYGROUND.*$|#define VAR_PLAYGROUND nh_getenv("SPLICEHACK_VAR_PLAYGROUND")|' include/unixconf.h

    # Lua comes only from the pinned origin; the download target fails.
    for pattern in '^fetch-lua: fetch-Lua[[:space:]]*$' '^fetch-Lua:[[:space:]]*$' \
        '^[[:blank:]]+\( mkdir -p lib && cd lib &&' '^[[:blank:]]+curl -R -O ' \
        '^[[:blank:]]+tar zxf lua-' '^[[:blank:]]+-rm include/nhlua.h[[:space:]]*$' \
        '^[[:blank:]]+rats\.lua[[:space:]]*$'; do
      expect_count 1 sys/unix/Makefile.top "$pattern"
    done
    sed -i -E \
      -e 's/^fetch-lua: fetch-Lua[[:space:]]*$/fetch-lua:/' \
      -e 's/^fetch-Lua:[[:space:]]*$/fetch-Lua:\n\t@false/' \
      -e '/^[[:blank:]]+\( mkdir -p lib && cd lib &&/d' \
      -e '/^[[:blank:]]+curl -R -O /d' \
      -e '/^[[:blank:]]+tar zxf lua-/d' \
      -e '/^[[:blank:]]+-rm include\/nhlua.h[[:space:]]*$/d' \
      -e 's/^[[:blank:]]+rats\.lua[[:space:]]*$/\trats.lua banquet.lua brass.lua darkforest.lua foogardens.lua gemarray.lua ice.lua icewaste.lua laboratory.lua mephisto.lua statuary.lua void.lua/' \
      sys/unix/Makefile.top
    expect_count 0 sys/unix/Makefile.top 'curl'

    # makedefs validates SOURCE_DATE_EPOCH against the wall clock.
    expect_count 1 util/makedefs.c '\(void\) time\(&clocktim\);'
    sed -i 's|(void) time(&clocktim);|clocktim = (time_t) 1628715174;|' util/makedefs.c

    # groff reads the tab and inline comment as part of the .so filename.
    expect_count 1 doc/Guidebook.mn '^\.so tmac\.nh[[:blank:]]+'
    sed -i -E 's|^\.so tmac\.nh[[:blank:]]+.*$|.so tmac.nh|' doc/Guidebook.mn

    substituteInPlace sys/unix/setup.sh --replace-fail /bin/sh ${runtimeShell}
    ${runtimeShell} sys/unix/setup.sh sys/unix/hints/linux-minimal
  '';

  dontConfigure = true;
  # Generated headers, Lua, makedefs and dlb have undeclared ordering needs.
  enableParallelBuilding = false;

  preBuild = ''
    export SOURCE_DATE_EPOCH=1628715174 TZ=UTC0
    makeFlagsArray+=(
      "CC=$CC"
      "LINK=$CC"
      "CFLAGS=-O2 -std=gnu99 -fcommon -D_DEFAULT_SOURCE -DLUA_USE_POSIX -I../include -DDLB -DREPRODUCIBLE_BUILD -DNOMAIL -DNOSHELL -DNOUSER_SOUNDS -DFCMASK=0600 -DHACKDIR=\\\"$out/share/splicehack-rewrite\\\" -DCOMPRESS=\\\"${gzip}/bin/gzip\\\" -DCOMPRESS_EXTENSION=\\\".gz\\\""
      "WINTTYLIB=-lncurses -ltinfo"
      "GITINFO=0"
    )
  '';
  buildFlags = [ "all" ];

  # Upstream install removes playgrounds and mixes mutable files with data.
  installPhase = ''
    runHook preInstall
    data=$out/share/splicehack-rewrite
    doc=$out/share/doc/splicehack-rewrite
    install -Dm555 src/nethack $out/libexec/splicehack-rewrite-real
    install -Dm444 -t $data dat/nhdat dat/license dat/symbols
    install -Dm444 -t $doc README src/isaac64.c doc/spl-sources.txt \
      doc/spl-changelog.txt dat/license
    install -Dm444 doc/Guidebook $doc/Guidebook.txt
    install -Dm444 lib/lua-5.4.2/doc/readme.html $doc/lua-readme.html

    mkdir -p $out/bin
    cat > $out/bin/splicehack-rewrite <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    state="\''${XDG_DATA_HOME:-\''${HOME:?HOME must be set}/.local/share}/splicehack-rewrite"
    config="\''${XDG_CONFIG_HOME:-\''${HOME:?HOME must be set}/.config}/splicehack-rewrite"
    export SPLICEHACK_VAR_PLAYGROUND="\$state/"
    # nh_getenv() rejects values over 128 bytes; count bytes, not characters.
    if test "\$(printf %s "\$SPLICEHACK_VAR_PLAYGROUND" | ${coreutils}/bin/wc -c)" -gt 128; then
      echo 'splicehack-rewrite: state path exceeds 128 bytes' >&2
      exit 1
    fi
    if test "\$(printf %s "\$config" | ${coreutils}/bin/wc -c)" -gt 128; then
      echo 'splicehack-rewrite: config path exceeds 128 bytes' >&2
      exit 1
    fi
    ${coreutils}/bin/mkdir -p -- "\$state/save" "\$state/whereis" "\$config"
    for file in perm record logfile xlogfile livelog paniclog; do
      test -e "\$state/\$file" || : > "\$state/\$file"
    done
    export HOME="\$config" HACKDIR=$data NETHACKDIR=$data
    export TERM="\''${TERM:-xterm-256color}"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/splicehack-rewrite-real "\$@"
    EOF
    chmod 555 $out/bin/splicehack-rewrite
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for f in nhdat license symbols; do test -s $out/share/splicehack-rewrite/$f; done
    for f in README Guidebook.txt isaac64.c lua-readme.html license spl-sources.txt spl-changelog.txt; do
      test -s $out/share/doc/splicehack-rewrite/$f
    done
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/splicehack-rewrite/license
    grep -qF 'Permission is hereby granted' $out/share/doc/splicehack-rewrite/lua-readme.html
    grep -qF 'CC0' $out/share/doc/splicehack-rewrite/isaac64.c
    grep -qF "$out/share/splicehack-rewrite" $out/libexec/splicehack-rewrite-real
    grep -qF '${gzip}/bin/gzip' $out/libexec/splicehack-rewrite-real
    grep -qF SPLICEHACK_VAR_PLAYGROUND $out/libexec/splicehack-rewrite-real
    ${runtimeShell} -n $out/bin/splicehack-rewrite
    runHook postInstallCheck
  '';

  meta = {
    description = "SpliceHack's NetHack 3.7 rewrite for the terminal";
    longDescription = ''
      SpliceHack Rewrite is an independently playable NetHack 3.7 variant with
      new monsters, roles, races and dungeon features. This package builds the
      tty interface from fixed upstream sources, including embedded Lua 5.4.2,
      with offline data generation. Game data stays in the store; saves,
      scores, locks, logs and configuration live in private XDG directories.
    '';
    homepage = "https://github.com/RojjaCebolla/SpliceHack-Rewrite";
    license = [ lib.licenses.ngpl lib.licenses.mit lib.licenses.cc0 ];
    mainProgram = "splicehack-rewrite";
    platforms = [ "x86_64-linux" ];
  };
}
