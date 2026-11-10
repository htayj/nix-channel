{ lib, stdenv, fetchFromGitHub, bison, flex, ncurses, coreutils, runtimeShell }:

let
  rev = "4ed114fc29b9d03f9b2857c730afd9563513ddad";
  # Commit time of ${rev} (2022-07-08 01:18:28 UTC), used as makedefs' build time.
  buildTime = "1657243108";
  # Parts of the upstream tree the native tty/curses build uses, as selected
  # by the tay Guix channel's sporkhack.scm; nothing else is kept.
  kept = [
    "README" "README.new_lev_comp" "README.statuscolors" "Files" "Porting"
    "dat" "doc" "include" "src" "util"
    "sys/unix/Install.unx" "sys/unix/Makefile.dat" "sys/unix/Makefile.doc"
    "sys/unix/Makefile.src" "sys/unix/Makefile.top" "sys/unix/Makefile.utl"
    "sys/unix/README.linux" "sys/unix/setup.sh" "sys/unix/unixmain.c"
    "sys/unix/unixres.c" "sys/unix/unixunix.c"
    "sys/share/ioctl.c" "sys/share/unixtty.c" "sys/share/sounds/README"
    "win/tty" "win/curses"
  ];
  # Removed from kept directories (see SOURCE-NOTICE).
  removed = [
    "doc/tmac.n" "include/bitmfile.h" "include/gem_rsc.h" "include/load_img.h"
    "include/qt_xpms.h"
  ];
  # Upstream files changed by private-state.patch or postPatch.
  modified = [
    "include/config.h" "include/unixconf.h" "src/end.c" "src/files.c"
    "sys/unix/Makefile.top" "sys/unix/unixmain.c" "util/makedefs.c"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "sporkhack";
  version = "0.7.0-0.4ed114f";

  # The archive hash equals the Git checkout's NAR hash used by Guix.
  src = fetchFromGitHub {
    owner = "k21971";
    repo = "SporkHack";
    inherit rev;
    hash = "sha256-6rz2uDkbJMCYXHUolnRObvXCxobvo/Ub2STQUe0v0FA=";
  };

  # Private writable state, from the tay Guix channel (2026-10-06).
  patches = [ ./private-state.patch ];
  patchFlags = [ "-p1" "--fuzz=0" ];

  # The NetHack General Public License requires modified files to carry
  # prominent notices stating the change and its date.  Every edit must
  # match exactly as often as expected, or the build stops.
  postPatch = ''
    fail() { echo "sporkhack postPatch: $*" >&2; exit 1; }

    # replace FILE COUNT OLD NEW: literal replacement of exactly COUNT matches.
    replace() {
      local content rest found
      content=$(cat "$1"; echo x); content=''${content%x}
      rest=''${content//"$3"/}
      found=$(( (''${#content} - ''${#rest}) / ''${#3} ))
      [ "$found" -eq "$2" ] || fail "$1: expected $2 of '$3', found $found"
      substituteInPlace "$1" --replace-fail "$3" "$4"
    }

    # notice FILE TEXT [COMMENT-START COMMENT-END]
    notice() {
      local text="Modified 2026-11-10 by the tay Nix channel: $2. See pkgs/sporkhack."
      sed -i "1i ''${3-/*} $text ''${4-*/}" "$1"
    }

    # Keep only the native build's inputs.
    mkdir $NIX_BUILD_TOP/kept
    for path in ${lib.escapeShellArgs kept}; do
      mkdir -p "$NIX_BUILD_TOP/kept/$(dirname "$path")"
      mv "$path" "$NIX_BUILD_TOP/kept/$path"
    done
    find . -mindepth 1 -delete
    mv $NIX_BUILD_TOP/kept/* .
    rm ${lib.escapeShellArgs removed}

    # Immutable data in the store; internal compression only.
    replace include/config.h 1 '#  define HACKDIR "/sporkhack-0.7.0/var"' \
      "#  define HACKDIR \"$out/share/sporkhack\""
    replace include/config.h 1 '#define COMPRESS "/bin/gzip"' \
      '/* External compressor disabled; INTERNAL_COMP is used. */'
    replace include/config.h 1 '#define COMPRESS_EXTENSION ".gz"' \
      '/* No external compressor extension. */'
    notice include/config.h "HACKDIR is this package's share/sporkhack, no external compressor, relative dump and extrainfo files, no server admin message (private-state.patch)"

    notice include/unixconf.h "VAR_PLAYGROUND from SPORKHACK_VAR_PLAYGROUND and FCMASK 0600 (private-state.patch)"
    notice sys/unix/unixmain.c "private playground required and honored with the store data directory (private-state.patch)"
    notice src/end.c "private dump and extrainfo files in the playground (private-state.patch)"
    notice src/files.c "private whereis files (private-state.patch)"

    # makedefs embeds the build clock; use the commit time instead.
    replace util/makedefs.c 1 '(void) time(&clocktim);' 'clocktim = ${buildTime}L;'
    replace util/makedefs.c 1 '(void) time((time_t *)&clocktim);' 'clocktim = ${buildTime}L;'
    notice util/makedefs.c "fixed build time (2022-07-08) for reproducible output"

    # No Git checkout at build time; the plain-text Guidebook is shipped.
    replace sys/unix/Makefile.top 1 \
      'export VCS_DESCRIPTION = git $(shell git rev-parse --short HEAD)' \
      'export VCS_DESCRIPTION = git ${rev}'
    replace sys/unix/Makefile.top 1 'recover Guidebook $(VARDAT)' 'recover $(VARDAT)'
    notice sys/unix/Makefile.top "pinned version description, Guidebook not formatted" "#" ""

    # The complete source as built, installed beside the binary below.
    cp -r --preserve=mode . $NIX_BUILD_TOP/corresponding-source
  '';

  # bison and flex regenerate the level and dungeon compilers' parsers.
  nativeBuildInputs = [ bison flex ];
  buildInputs = [ ncurses ];

  env.TZ = "UTC0";

  dontConfigure = true;

  preBuild = ''
    sh sys/unix/setup.sh
    # K&R definitions need a pre-C23 dialect; tentative definitions need -fcommon.
    makeFlagsArray+=(
      "CC=$CC"
      "CFLAGS=-O2 -g -std=gnu89 -fcommon -D_DEFAULT_SOURCE -I../include"
      "LFLAGS="
      "LEX=flex"
      "YACC=bison -y"
      "WINTTYLIB=-lncurses -ltinfo"
    )
  '';

  buildFlags = [ "all" ];
  # makedefs, lev_comp, dgn_comp and dlb outputs depend on each other.
  enableParallelBuilding = false;

  # Scripts in the corresponding source stay as distributed.
  dontPatchShebangs = true;

  # Upstream's install target targets a dgamelaunch chroot.
  installPhase = ''
    runHook preInstall

    data=$out/share/sporkhack
    doc=$out/share/doc/sporkhack
    install -Dm555 src/sporkhack $out/libexec/sporkhack-real
    install -Dm644 -t $data dat/nhdat dat/license
    install -Dm644 -t $doc README README.new_lev_comp README.statuscolors \
      doc/Guidebook.txt sys/unix/README.linux dat/license
    install -Dm644 sys/share/sounds/README $doc/sounds-README

    mkdir -p $out/bin
    cat > $out/bin/sporkhack <<'EOF'
    #!${runtimeShell}
    set -eu
    umask 077
    state="''${XDG_STATE_HOME:-''${HOME:?}/.local/state}/sporkhack"
    case $state in /*) ;; *)
      echo 'sporkhack: XDG_STATE_HOME must be an absolute path' >&2; exit 1;; esac
    # The game ignores environment values longer than 128 bytes.
    if test "$(LC_ALL=C; echo "''${#state}")" -gt 127; then
      echo 'sporkhack: state path exceeds the 128-byte environment limit' >&2; exit 1
    fi
    ${coreutils}/bin/mkdir -p -- "$state/save" "$state/dumplog"
    for file in perm record logfile xlogfile livelog wishtracker paniclog; do
      test -e "$state/$file" || : > "$state/$file"
    done
    export HACKDIR=${placeholder "out"}/share/sporkhack
    export NETHACKDIR="$HACKDIR"
    export SPORKHACK_VAR_PLAYGROUND="$state/"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    export TERM="''${TERM:-xterm-256color}"
    exec ${placeholder "out"}/libexec/sporkhack-real "$@"
    EOF
    chmod 555 $out/bin/sporkhack

    # Complete corresponding source, as required by the NetHack General
    # Public License.
    cp -r --preserve=mode $NIX_BUILD_TOP/corresponding-source $doc/source
    install -Dm644 ${./default.nix} $doc/default.nix
    install -Dm644 ${./private-state.patch} $doc/private-state.patch
    cat > $doc/SOURCE-NOTICE <<'EOF'
    SporkHack ${finalAttrs.version}: complete corresponding source

    The directory source/ holds the complete selected, patched source from
    which this package's program and data were built, exactly as compiled.
    The build regenerates headers, levels, parsers and the nhdat archive from
    these files. Original copyright and license notices are retained; the
    terms are in dat/license (NetHack General Public License).

    Upstream: https://github.com/k21971/SporkHack, commit ${rev}
    (2022-07-08). Archive hash: ${finalAttrs.src.outputHash}

    Only these parts of the upstream tree are used and kept, following the
    tay Guix channel's sporkhack.scm selection:
      ${lib.concatStringsSep " " kept}
    Other ports, graphical interfaces, tiles, encoded sound samples and binary
    resources are omitted. Removed from the kept parts, all unused by this
    build:
      doc/tmac.n: its terms forbid selling it and distributing modified
        copies. The shipped doc/Guidebook.txt is used instead.
      include/bitmfile.h: MAXON copyright with no stated grant (Atari GEM).
      include/gem_rsc.h, include/load_img.h, include/qt_xpms.h: GEM and Qt
        interface headers.
    The unfiltered upstream archive is only a build-time input; it is not
    part of this package. Distribution of that fixed-output source by a
    binary cache is outside this channel's control.

    Changes from the upstream archive. Each modified file carries a dated
    notice on its first line.
      private-state.patch (tay Guix channel, 2026-10-06; included here):
        include/unixconf.h: VAR_PLAYGROUND from SPORKHACK_VAR_PLAYGROUND;
          FCMASK 0600.
        include/config.h: DUMP_FN and EXTRAINFO_FN relative to the
          playground; SERVER_ADMIN_MSG removed.
        sys/unix/unixmain.c: the playground is required and used even with
          an explicit data directory.
        src/end.c, src/files.c: dump, extrainfo and whereis files private
          (0600) and placed in the playground.
      tay Nix channel, 2026-11-10 (default.nix postPatch):
        include/config.h: HACKDIR is this package's share/sporkhack; external
          compressor disabled (INTERNAL_COMP).
        util/makedefs.c: build time fixed at 2022-07-08 (${buildTime}).
        sys/unix/Makefile.top: VCS_DESCRIPTION pinned to the commit; the
          Guidebook is not formatted.
    No other file differs from the archive.

    The Nix build expression is default.nix in this directory. To rebuild
    without Nix, with a C compiler, bison, flex and ncurses (split libtinfo):

      cd source
      sh sys/unix/setup.sh
      TZ=UTC0 make all CFLAGS='-O2 -std=gnu89 -fcommon -D_DEFAULT_SOURCE -I../include' \
        LFLAGS= LEX=flex YACC='bison -y' WINTTYLIB='-lncurses -ltinfo'

    HACKDIR in include/config.h names this package's data directory; edit it
    for another prefix. The Nix package installs src/sporkhack as
    libexec/sporkhack-real, dat/nhdat and dat/license into share/sporkhack,
    and bin/sporkhack, which keeps saves, bones, scores, logs, locks and dumps
    in XDG_STATE_HOME/sporkhack (default ~/.local/state/sporkhack). Options
    are read from ~/.sporkrc, ~/.nethackrc or NETHACKOPTIONS.
    EOF

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    doc=$out/share/doc/sporkhack
    test -s $out/share/sporkhack/nhdat
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/sporkhack/license
    grep -qF '${rev}' $doc/SOURCE-NOTICE
    test -s $doc/default.nix
    test -s $doc/private-state.patch

    # The installed source must equal the kept upstream parts apart from the
    # modified files and the removals listed in SOURCE-NOTICE.
    pristine=$(mktemp -d)
    for path in ${lib.escapeShellArgs kept}; do
      mkdir -p "$pristine/$(dirname "$path")"
      cp -r "$src/$path" "$pristine/$path"
    done
    diff -rq $pristine $doc/source | sed "s|$pristine|A|; s|$doc/source|B|" > differences || true
    {
      for f in ${lib.escapeShellArgs modified}; do
        echo "Files A/$f and B/$f differ"
      done
      for f in ${lib.escapeShellArgs removed}; do
        echo "Only in A/$(dirname $f): $(basename $f)"
      done
    } > expected
    sort differences | diff -u <(sort expected) -
    for f in ${lib.escapeShellArgs modified}; do
      head -n1 $doc/source/$f | grep -q 'Modified 2026-11-10 by the tay Nix channel'
    done
    chmod -R u+w $pristine; rm -r $pristine

    # Relative and overlong state paths are refused.
    export HOME=$(mktemp -d)
    if XDG_STATE_HOME=relative $out/bin/sporkhack -s 2> refused; then exit 1; fi
    grep -q 'must be an absolute path' refused
    long=$HOME/$(printf '%0130d' 0)
    if XDG_STATE_HOME=$long $out/bin/sporkhack -s 2> refused; then exit 1; fi
    grep -q '128-byte' refused

    # The launcher creates private state and the game lists its (empty)
    # score file from the playground.
    export XDG_STATE_HOME=
    $out/bin/sporkhack -s > scores 2>&1 || { cat scores; exit 1; }
    cat scores
    state=$HOME/.local/state/sporkhack
    test -d $state/save && test -d $state/dumplog && test -e $state/record
    test "$(stat -c %a $state)" = 700
    test "$(stat -c %a $state/record)" = 600
    runHook postInstallCheck
  '';

  meta = {
    description = "NetHack variant with additional monsters, objects and levels, for the terminal";
    longDescription = ''
      SporkHack is a NetHack 3.4.3 variant with additional monsters, objects
      and dungeon levels. This package builds the native tty and curses
      interfaces from a fixed revision; it is silent, with no sound samples or
      playback backend. Game data is immutable in the store; saves, bones,
      scores, logs and dumps live in XDG_STATE_HOME/sporkhack. Options are
      read from ~/.sporkrc, ~/.nethackrc or NETHACKOPTIONS.
    '';
    homepage = "https://github.com/k21971/SporkHack";
    license = lib.licenses.ngpl;
    mainProgram = "sporkhack";
    platforms = [ "x86_64-linux" ];
  };
})
