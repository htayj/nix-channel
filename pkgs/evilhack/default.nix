{ lib, stdenv, fetchFromGitHub, bison, flex, groff, pkg-config, ncurses
, coreutils, gzip, runtimeShell }:

let
  rev = "c444f6a3ab1e9f16d0676961dba86f628e91c6ba";
  # Commit time of ${rev}, used as makedefs' build time.
  buildTime = "1783867340";
  # Optional graphical, font and encoded sound assets, the X11 icons, the
  # Xcode settings and the restrictive news macros, as removed by the tay
  # Guix channel's evilhack.scm.  None of them is used by the tty/curses build.
  removedFiles = [
    "win/X11/nh32icon" "win/X11/nh56icon" "win/X11/nh72icon"
    "sys/unix/XCode.xcconfig" "doc/tmac.n" "doc/tmac.nh"
  ];
  removedPattern = ".*\\.(uue?|hqx|png|PNG|xpm|xbm|bdf)$";
  # Upstream files changed by private-state.patch or postPatch.
  modified = [
    "sys/unix/unixmain.c" "sys/unix/setup.sh" "sys/unix/Makefile.src"
    "sys/unix/Makefile.top" "sys/unix/Makefile.doc" "sys/unix/hints/linux"
    "include/config.h" "include/unixconf.h" "doc/Guidebook.mn"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "evilhack";
  version = "0.9.3";

  # The archive hash equals the Git checkout's NAR hash used by Guix.
  src = fetchFromGitHub {
    owner = "k21971";
    repo = "EvilHack";
    inherit rev;
    hash = "sha256-tqwLTCmz1/8924x197g2eVinpUcY2fn87JvXYGUTN3c=";
  };

  # Private writable state, from the tay Guix channel (2026-10-03).
  patches = [ ./private-state.patch ];
  patchFlags = [ "-p1" "--fuzz=0" ];

  # The NetHack General Public License requires modified files to carry
  # prominent notices stating the change and its date.  Every edit must
  # match exactly as often as expected, or the build stops.
  postPatch = ''
    fail() { echo "evilhack postPatch: $*" >&2; exit 1; }

    # replace FILE COUNT OLD NEW: literal replacement of exactly COUNT matches.
    replace() {
      local content rest found
      content=$(cat "$1"; echo x); content=''${content%x}
      rest=''${content//"$3"/}
      found=$(( (''${#content} - ''${#rest}) / ''${#3} ))
      [ "$found" -eq "$2" ] || fail "$1: expected $2 of '$3', found $found"
      substituteInPlace "$1" --replace-fail "$3" "$4"
    }

    # regex FILE COUNT ERE SED-REPLACEMENT: replace exactly COUNT matching lines.
    regex() {
      local found
      found=$(grep -cE "$3" "$1" || true)
      [ "$found" -eq "$2" ] || fail "$1: expected $2 lines matching '$3', found $found"
      sed -i -E "s~$3.*\$~$4~" "$1"
    }

    # notice FILE TEXT [LINE] [COMMENT-START] [COMMENT-END]
    notice() {
      local text="Modified 2026-11-10 by the tay Nix channel: $2. See pkgs/evilhack."
      sed -i "''${3-1}i ''${4-/*} $text ''${5-*/}" "$1"
    }

    rm ${lib.escapeShellArgs removedFiles}
    find . -regextype posix-extended -regex ${lib.escapeShellArg removedPattern} -delete

    # Build-input shell instead of /bin/sh.
    replace sys/unix/setup.sh 6 /bin/sh ${runtimeShell}
    notice sys/unix/setup.sh "build-input shell" 2 "#" ""
    replace sys/unix/Makefile.src 1 'SHELL=/bin/sh' 'SHELL=${runtimeShell}'
    notice sys/unix/Makefile.src "build-input shell" 1 "#" ""

    # Optimized standalone build: no global sysconf, server, dump, live log,
    # tile or real-time features; private state below the user's data
    # directory; gzip from an input for save compression.
    replace sys/unix/hints/linux 1 \
      'CFLAGS=-g3 -O0 -I../include -DNOTPARMDECL -fno-common' \
      'CFLAGS=-O2 -g0 -std=gnu17 -I../include -DNOTPARMDECL -fno-common'
    regex sys/unix/hints/linux 9 \
      '^CFLAGS\+=-D(SYSCF|HACKDIR|VAR_PLAYGROUND|DGAMELAUNCH|LIVELOG_ENABLE|DUMPLOG|DUMPHTML|TTY_TILES_ESCCODES|REALTIME_ON_BOTL)' \
      '# omitted: host, server and optional asset integration'
    replace sys/unix/hints/linux 1 '/bin/gzip' '${gzip}/bin/gzip'
    replace sys/unix/hints/linux 1 'CFLAGS+=-DCURSES_GRAPHICS' \
      'CFLAGS+=-DCURSES_GRAPHICS -DNOMAIL -DNOSHELL -DNOUSER_SOUNDS -DREPRODUCIBLE_BUILD -DVAR_PLAYGROUND=\".\"'
    regex sys/unix/hints/linux 2 '^WIN(SRC \+= tile\.c|OBJ \+= tile\.o)' \
      '# omitted: tty tile assets are not shipped'
    notice sys/unix/hints/linux "optimized gnu17 standalone build, no sysconf/server/dump/live-log/tile/real-time options, private playground, absolute gzip, no mail/shell/user sounds, reproducible build" 1 "#" ""

    regex include/config.h 1 '^#define SYSCF[[:space:]]' '/* #define SYSCF */'
    regex include/config.h 1 '^#define SYSCF_FILE[[:space:]]' '/* #define SYSCF_FILE */'
    notice include/config.h "no global server configuration (SYSCF, SYSCF_FILE)"
    regex include/unixconf.h 1 '^#define SERVER_ADMIN_MSG[[:space:]]' '/* #define SERVER_ADMIN_MSG */'
    notice include/unixconf.h "standalone game, no server admin messages"
    notice sys/unix/unixmain.c "score, save, bones, lock and trouble files below EVILHACK_STATE (private-state.patch)"

    # Original MIT formatter (tay Guix channel) instead of the inherited
    # news macros, whose terms forbid selling and modified distribution.
    install -m644 ${./guide.tmac} doc/guide.tmac
    regex doc/Guidebook.mn 1 '^\.so tmac\.nh' '.\\" formatter doc/guide.tmac is loaded by the Makefile'
    regex doc/Guidebook.mn 1 '^\.if !\\n\(nH \.so doc/tmac\.nh' '.\\" no legacy formatter fallback'
    notice doc/Guidebook.mn "formatted with the MIT doc/guide.tmac instead of tmac.n and tmac.nh" 1 '.\\"' ""
    replace sys/unix/Makefile.doc 4 'tmac.n tmac.nh' 'guide.tmac'
    replace sys/unix/Makefile.doc 2 'tbl tmac.n -' 'tbl guide.tmac -'
    # GNU groff has no 'el' warning category.
    replace sys/unix/Makefile.doc 1 ' -Wel' ""
    # Every generated guide is installed, so formatting failures are fatal.
    replace sys/unix/Makefile.doc 1 '	-$(GUIDECMD)' '	$(GUIDECMD)'
    printf '\nSHELL := %s\n.SHELLFLAGS := -ec -o pipefail\n' ${runtimeShell} >> sys/unix/Makefile.doc
    notice sys/unix/Makefile.doc "MIT guide formatter, no -Wel, fatal guide pipeline errors" 1 "#" ""

    # The server-only random seed is neither needed nor installed.
    replace sys/unix/Makefile.top 1 'check-dlb serverseed' 'check-dlb'
    notice sys/unix/Makefile.top "no server-only seed generation" 1 "#" ""

    # The checked-in plain-text guide is regenerated from Guidebook.mn.
    rm doc/Guidebook.txt

    # The complete source as built, installed beside the binary below.
    cp -r --preserve=mode . $NIX_BUILD_TOP/corresponding-source
  '';

  nativeBuildInputs = [ bison flex groff pkg-config ];
  buildInputs = [ ncurses ];

  dontConfigure = true;

  preBuild = ''
    export SOURCE_DATE_EPOCH=${buildTime} TZ=UTC0
    sh sys/unix/setup.sh sys/unix/hints/linux
    makeFlagsArray+=("CC=$CC" "LINK=$CC" "LEX=flex" "YACC=bison -y" "GITINFO=0")
  '';

  buildFlags = [ "all" ];
  # makedefs, lev_comp, dgn_comp and dlb outputs depend on each other.
  enableParallelBuilding = false;

  # Scripts in the corresponding source stay as built.
  dontPatchShebangs = true;

  # Upstream's install target targets a shared system playground.
  installPhase = ''
    runHook preInstall

    data=$out/share/evilhack
    doc=$out/share/doc/evilhack
    install -Dm555 src/evilhack $out/libexec/evilhack-real
    install -Dm644 -t $data dat/nhdat dat/license dat/symbols
    install -Dm644 -t $doc LICENSE README README.md doc/Guidebook.txt \
      doc/evilhack-changelog.md sys/unix/README.linux include/isaac64.h \
      src/isaac64.c

    mkdir -p $out/bin
    cat > $out/bin/evilhack <<'EOF'
    #!${runtimeShell}
    set -eu
    umask 077
    data_home="''${XDG_DATA_HOME:-''${HOME:?}/.local/share}"
    case $data_home in /*) ;; *)
      echo 'evilhack: XDG_DATA_HOME must be an absolute path' >&2; exit 1;; esac
    state=$(${coreutils}/bin/realpath -m -- "$data_home/evilhack")
    # The game ignores environment values longer than 128 bytes; the
    # playground name adds 18 bytes to the state path.
    if test "$(LC_ALL=C; echo "''${#state}")" -gt 100; then
      echo 'evilhack: state path exceeds 100 bytes' >&2; exit 1
    fi
    ${coreutils}/bin/mkdir -p -- "$state/save"
    ${coreutils}/bin/chmod 700 -- "$state" "$state/save"
    for file in perm record logfile xlogfile paniclog; do
      test -e "$state/$file" || : > "$state/$file"
    done
    playground=$(${coreutils}/bin/mktemp -d "$state/playground.XXXXXX")
    cleanup() { ${coreutils}/bin/rm -rf -- "$playground"; }
    trap cleanup EXIT
    for file in nhdat license symbols; do
      ${coreutils}/bin/ln -s "@data@/$file" "$playground/$file"
    done
    export HOME="$state" EVILHACK_STATE="$state/"
    export HACKDIR="$playground" NETHACKDIR="$playground"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    export TERM="''${TERM:-xterm-256color}"
    cd "$playground"
    # The game stays in the terminal's foreground process group and handles
    # keyboard signals itself; hangup and termination of this launcher are
    # forwarded so the game can save before the playground is removed.
    @real@ "$@" <&0 &
    child=$!
    trap ':' INT QUIT
    trap 'kill -HUP "$child" 2>/dev/null || :' HUP
    trap 'kill -TERM "$child" 2>/dev/null || :' TERM
    status=0
    while :; do
      if wait "$child"; then status=0; else status=$?; fi
      kill -0 "$child" 2>/dev/null || break
    done
    exit "$status"
    EOF
    substituteInPlace $out/bin/evilhack \
      --replace-fail @data@ $data \
      --replace-fail @real@ $out/libexec/evilhack-real
    chmod 555 $out/bin/evilhack

    # Complete corresponding source, as required by the NetHack General
    # Public License, with this package's build files.
    cp -r --preserve=mode $NIX_BUILD_TOP/corresponding-source $doc/source
    install -Dm644 ${./default.nix} $doc/default.nix
    install -Dm644 ${./private-state.patch} $doc/private-state.patch
    install -Dm644 ${./guide.tmac} $doc/guide.tmac
    cat > $doc/SOURCE-NOTICE <<'EOF'
    EvilHack ${finalAttrs.version}: complete corresponding source

    The directory source/ holds the complete selected, patched source from
    which this package's program, data and guide were built. Original
    copyright and license notices are retained; the game terms are in
    LICENSE and dat/license (NetHack General Public License).

    Upstream: https://github.com/k21971/EvilHack, commit ${rev}.
    Archive hash: ${finalAttrs.src.outputHash}

    Removed, following the tay Guix channel's evilhack.scm: encoded,
    image and font assets (*.uu, *.uue, *.hqx, *.png, *.PNG, *.xpm, *.xbm,
    *.bdf), win/X11/nh32icon, nh56icon and nh72icon,
    sys/unix/XCode.xcconfig, and doc/tmac.n and doc/tmac.nh, whose terms
    forbid selling and distributing modified copies. doc/Guidebook.txt is
    regenerated by the build. The unfiltered upstream archive is only a
    build-time input and is not part of this package.

    Changes from the upstream archive, each carrying a dated notice near
    its first line:
      private-state.patch (tay Guix channel, 2026-10-03; included here):
        sys/unix/unixmain.c: private state prefix from EVILHACK_STATE.
      tay Nix channel, 2026-11-10 (default.nix postPatch):
        ${lib.concatStringsSep " " modified}
        Build-input shell; optimized gnu17 standalone build without
        sysconf, server, dump, live-log, tile and real-time options;
        absolute gzip; no mail, shell escape or user sounds; fixed build
        time ${buildTime}; MIT guide formatter doc/guide.tmac (added,
        tay Guix channel) with fatal formatting errors; no serverseed.

    Bundled ISAAC64 (include/isaac64.h, src/isaac64.c): Timothy B.
    Terriberry, CC0. doc/guide.tmac: MIT license, notice in the file.

    The Nix build expression is default.nix in this directory. Without Nix,
    with a C compiler, bison, flex, groff, pkg-config, gzip and ncurses:

      cd source
      sh sys/unix/setup.sh sys/unix/hints/linux
      SOURCE_DATE_EPOCH=${buildTime} TZ=UTC0 make all LEX=flex \
        YACC='bison -y' GITINFO=0

    bin/evilhack keeps saves, bones, scores, logs, locks and options
    (.evilhackrc) private in XDG_DATA_HOME/evilhack (default
    ~/.local/share/evilhack) and runs the game in a temporary playground
    there that links the immutable data in share/evilhack.
    EOF

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    doc=$out/share/doc/evilhack
    readelf=''${READELF:-readelf}
    $readelf -h $out/libexec/evilhack-real | grep -q 'ELF64'
    $readelf -d $out/libexec/evilhack-real | grep -q 'NEEDED.*libncursesw'
    for f in nhdat license symbols; do test -s $out/share/evilhack/$f; done
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/evilhack/license
    grep -qF 'EvilHack' $doc/Guidebook.txt
    test "$(wc -l < $doc/Guidebook.txt)" -gt 1000
    test -z "$(find $out -name 'tmac.n' -o -name 'tmac.nh')"
    grep -qF '${rev}' $doc/SOURCE-NOTICE
    for f in default.nix private-state.patch guide.tmac LICENSE isaac64.c; do
      test -s $doc/$f
    done
    for f in ${lib.escapeShellArgs modified} doc/guide.tmac; do
      test -s $doc/source/$f
    done
    for f in ${lib.escapeShellArgs (lib.remove "sys/unix/setup.sh" modified)}; do
      head -n 1 $doc/source/$f | grep -qF 'Modified 2026-11-10 by the tay Nix channel'
    done
    sed -n 2p $doc/source/sys/unix/setup.sh | grep -qF 'Modified 2026-11-10 by the tay Nix channel'
    ${runtimeShell} -n $out/bin/evilhack
    if grep -rlF --binary-files=text "$PWD" $out; then
      echo 'evilhack: build directory referenced in the output' >&2; exit 1
    fi
    $out/libexec/evilhack-real --version | grep -qF '0.9.3'
    runHook postInstallCheck
  '';

  meta = {
    description = "EvilHack terminal dungeon exploration game";
    longDescription = ''
      EvilHack is an independently playable NetHack variant with additional
      monsters, items, roles and dungeon branches.  This package builds its
      standalone Unix tty and curses interfaces and keeps saves, scores,
      bones, locks, logs and options private below the user's XDG data
      directory.  Optional graphical and sound assets are excluded.
    '';
    homepage = "https://github.com/k21971/EvilHack";
    license = with lib.licenses; [ ngpl cc0 mit ];
    mainProgram = "evilhack";
    platforms = [ "x86_64-linux" ];
  };
})
