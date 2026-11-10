{ lib, stdenv, fetchFromGitHub, bison, flex, ncurses, groff, util-linux, coreutils, runtimeShell }:

let
  rev = "9a4c7671a8d8de6c0a7ab4718382b49cf5ec61f5";
  # Commit time of ${rev} (2015-03-11 12:27:57 UTC), used as makedefs' build time.
  buildTime = "1426076877";
  # Parts of the upstream tree the terminal build uses; nothing else is kept,
  # so the build itself shows the installed source to be complete.
  kept = [
    "configure" "README" "Files" "Porting" "src" "include" "util" "dat" "doc"
    "sys/autoconf" "sys/unix" "sys/share/ioctl.c" "sys/share/unixtty.c"
    "sys/winnt/win32api.h" "win/tty"
  ];
  # Removed from kept directories (see SOURCE-NOTICE).
  removed = [
    "doc/tmac.n" "include/bitmfile.h" "include/gem_rsc.h" "include/load_img.h"
    "include/qt_xpms.h"
  ];
  # Upstream files changed below, in the order listed in SOURCE-NOTICE.
  modified = [
    "include/config.h" "include/unixconf.h" "src/files.c" "src/objects.c"
    "sys/unix/unixmain.c" "util/makedefs.c" "win/tty/termcap.c"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "acehack";
  version = "3.6.0-0.9a4c767";

  # Historical mirror; AceHack has no release tags.  This is master's final
  # commit.  The archive hash equals the Git checkout's NAR hash.
  src = fetchFromGitHub {
    owner = "deepy";
    repo = "acehack";
    inherit rev;
    hash = "sha256-6LzFws7O+tXcD+cjWQiGMJ/RQAsEhmfk8PxQDvvqW6U=";
  };

  # The NetHack General Public License requires modified files to carry
  # prominent notices stating the change and its date.  Every edit must
  # match exactly as often as expected, or the build stops.
  postPatch = ''
    fail() { echo "acehack postPatch: $*" >&2; exit 1; }

    # replace FILE COUNT OLD NEW: literal replacement of exactly COUNT matches.
    replace() {
      local content rest found
      content=$(cat "$1"; echo x); content=''${content%x}
      rest=''${content//"$3"/}
      found=$(( (''${#content} - ''${#rest}) / ''${#3} ))
      [ "$found" -eq "$2" ] || fail "$1: expected $2 of '$3', found $found"
      substituteInPlace "$1" --replace-fail "$3" "$4"
    }

    notice() {
      sed -i "1i /* Modified 2026-11-10 by the tay Nix channel: $2. See pkgs/acehack/default.nix. */" "$1"
    }

    # Keep only the terminal build's inputs.
    mkdir $NIX_BUILD_TOP/kept
    for path in ${lib.escapeShellArgs kept}; do
      mkdir -p "$NIX_BUILD_TOP/kept/$(dirname "$path")"
      mv "$path" "$NIX_BUILD_TOP/kept/$path"
    done
    find . -mindepth 1 -delete
    mv $NIX_BUILD_TOP/kept/* .
    rm ${lib.escapeShellArgs removed}

    # Immutable data in the store; the playground comes from the launcher.
    replace include/config.h 1 \
      "#  define HACKDIR \"'you need to run AceHack via the shelldir to set directories correctly'\"" \
      "#  define HACKDIR \"$out/share/acehack\""
    notice include/config.h "HACKDIR is this package's share/acehack"

    replace include/unixconf.h 1 \
      '/* #define VAR_PLAYGROUND "/var/lib/games/nethack" */' \
      '#define VAR_PLAYGROUND (nh_getenv("ACEHACK_VAR_PLAYGROUND") ? nh_getenv("ACEHACK_VAR_PLAYGROUND") : ".")'
    replace include/unixconf.h 1 '#define MAIL' '/* #define MAIL */'
    replace include/unixconf.h 1 '#define FCMASK	0660' '#define FCMASK	0600'
    replace include/unixconf.h 1 '#define SHELL	' '/* #define SHELL */	'
    notice include/unixconf.h "playground from ACEHACK_VAR_PLAYGROUND, no mail or shell escape, private file mode"

    # With internal compression COMPRESS_EXTENSION is undefined, but
    # verify_savefile appends it unconditionally.
    replace src/files.c 1 '  Strcat(buf, COMPRESS_EXTENSION);' '#ifdef COMPRESS_EXTENSION
  Strcat(buf, COMPRESS_EXTENSION);
#endif'
    notice src/files.c "verify_savefile without COMPRESS_EXTENSION"

    # Without MAIL the mail scroll stays in the object table, keeping the
    # historical object indices.
    replace src/objects.c 1 '#ifdef MAIL' '#if 1'
    notice src/objects.c "mail scroll kept without MAIL"

    # Multiplayer lock files go into the private playground, not a shared
    # directory chosen when configuring.
    replace sys/unix/unixmain.c 1 \
      'fqn_prefix[MPLOCKPREFIX] = MPLOCKLOC "/";' \
      'fqn_prefix[MPLOCKPREFIX] = fqn_prefix[SCOREPREFIX];'
    notice sys/unix/unixmain.c "multiplayer lock files in the playground"

    # makedefs embeds the build clock; use the commit time instead.
    replace util/makedefs.c 1 '(void) time(&clocktim);' 'clocktim = ${buildTime};'
    replace util/makedefs.c 1 '(void) time((time_t *)&clocktim);' 'clocktim = ${buildTime};'
    notice util/makedefs.c "fixed build time (2015-03-11) for reproducible output"

    # ncurses declares tparm with a prototype; configure probes -lcurses for
    # it, misses ncurses and leaves the conflicting K&R declaration enabled.
    replace win/tty/termcap.c 1 'extern char *tparm();' ""
    notice win/tty/termcap.c "tparm declaration taken from curses.h"

    # The complete source as built, installed beside the binary below.
    cp -r --preserve=mode . $NIX_BUILD_TOP/corresponding-source
  '';

  # bison and flex regenerate the level and dungeon compilers' parsers.
  nativeBuildInputs = [ bison flex groff util-linux ];
  buildInputs = [ ncurses ];

  env = {
    # ncurses provides the curses functions and its split libtinfo tgetent.
    LIBS = "-ltinfo";
    TZ = "UTC0";
    # Unused after the unixmain.c change; fixed so configure output does
    # not depend on the build machine's mounts.
    MPLOCKLOC = "/nonexistent";
    # The Guidebook is formatted in installPhase, without tmac.n in the tree.
    ac_cv_prog_HAVE_NROFF = "no";
    # K&R definitions need a pre-C23 dialect.
    NIX_CFLAGS_COMPILE = "-std=gnu89";
  };

  configureFlags = [
    "--enable-tty-graphics" "--disable-x11-graphics" "--disable-sdl-graphics"
    "--disable-gl-graphics" "--disable-mswin-graphics"
    "--with-owner=no" "--with-group=no"
    "--with-compression=no"
  ];

  # Upstream's source Makefile drops configure's LIBS.
  makeFlags = [ "LIBS=-lm -ltinfo" ];
  buildFlags = [ "all" ];
  # makedefs, lev_comp, dgn_comp and dlb outputs depend on each other.
  enableParallelBuilding = false;

  # Installed scripts in the corresponding source stay as distributed.
  dontPatchShebangs = true;

  # Upstream's install target sets games ownership and setgid modes.
  installPhase = ''
    runHook preInstall

    data=$out/share/acehack
    doc=$out/share/doc/acehack
    install -Dm555 src/acehack $out/libexec/acehack-real
    install -Dm555 util/recover $out/libexec/recover
    install -Dm644 -t $data dat/nhdat dat/license
    install -Dm644 -t $doc dat/license README doc/fixes36.0
    install -Dm644 -t $out/share/man/man6 doc/nethack.6 doc/recover.6

    # Format the Guidebook with the original tmac.n from the unmodified
    # archive; that macro file is not redistributed.
    tbl $src/doc/tmac.n doc/Guidebook.mn | nroff -c -Tascii | col -bx > Guidebook.txt
    grep -q 'AceHack\|NetHack' Guidebook.txt
    install -Dm644 Guidebook.txt $doc/Guidebook.txt

    mkdir -p $out/bin
    cat > $out/bin/acehack <<'EOF'
    #!${runtimeShell}
    set -eu
    umask 077
    state="''${XDG_DATA_HOME:-''${HOME:?}/.local/share}/acehack"
    config="''${XDG_CONFIG_HOME:-''${HOME:?}/.config}/acehack"
    case $state:$config in /*:/*) ;; *)
      echo 'acehack: XDG paths must be absolute' >&2; exit 1;; esac
    # The game ignores environment values longer than 128 bytes.
    if test "$(LC_ALL=C; echo "''${#state}")" -gt 127; then
      echo 'acehack: data path exceeds the 128-byte environment limit' >&2; exit 1
    fi
    ${coreutils}/bin/mkdir -p -- "$state/save" "$state/dumps" "$config"
    for file in perm record logfile xlogfile livelog; do
      test -e "$state/$file" || : > "$state/$file"
    done
    unset NETHACKDIR HACKDIR
    export ACEHACK_VAR_PLAYGROUND="$state/"
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    # .acehackrc is read from HOME.
    export HOME="$config"
    exec ${placeholder "out"}/libexec/acehack-real "$@"
    EOF
    chmod 555 $out/bin/acehack

    # Complete corresponding source, as required by the NetHack General
    # Public License.
    cp -r --preserve=mode $NIX_BUILD_TOP/corresponding-source $doc/source
    install -Dm644 ${./default.nix} $doc/default.nix
    cat > $doc/SOURCE-NOTICE <<'EOF'
    AceHack ${finalAttrs.version}: complete corresponding source

    The directory source/ holds the complete source code from which this
    package's programs and data were built, exactly as compiled. The build
    regenerates all headers, levels and the nhdat archive from these files.

    Upstream: https://github.com/deepy/acehack, commit ${rev}
    (2015-03-11), a mirror of Alex Smith's AceHack.
    Archive hash: ${finalAttrs.src.outputHash}

    Only these parts of the upstream tree are used and kept:
      ${lib.concatStringsSep " " kept}
    Other ports, graphical interfaces, sound samples and wiki pages are
    omitted. Removed from the kept parts, all unused by this build:
      doc/tmac.n: its terms forbid selling it and distributing modified
        copies. It is used, unmodified and from the upstream archive, only
        to format the installed Guidebook.txt from doc/Guidebook.mn.
      include/bitmfile.h: MAXON copyright with no stated grant (Atari GEM).
      include/gem_rsc.h, include/load_img.h, include/qt_xpms.h: GEM and
        Qt interface headers.

    Changes from the upstream archive, made 2026-11-10 by the tay Nix
    channel. Each modified file carries a dated notice on its first line.
      include/config.h: HACKDIR is this package's share/acehack.
      include/unixconf.h: VAR_PLAYGROUND from ACEHACK_VAR_PLAYGROUND;
        MAIL and SHELL disabled; FCMASK 0600.
      src/files.c: verify_savefile appends COMPRESS_EXTENSION only if defined.
      src/objects.c: the mail scroll stays in the object table.
      sys/unix/unixmain.c: multiplayer lock files in the playground.
      util/makedefs.c: build time fixed at 2015-03-11 (${buildTime}).
      win/tty/termcap.c: tparm declaration taken from curses.h.
    No other file differs from the archive.

    The Nix build expression is default.nix in this directory. To rebuild
    without Nix, with a C compiler and ncurses (with split libtinfo):

      cd source
      LIBS=-ltinfo CFLAGS='-O2 -std=gnu89' \
        MPLOCKLOC=/nonexistent ac_cv_prog_HAVE_NROFF=no ./configure \
        --prefix=PREFIX --enable-tty-graphics --disable-x11-graphics \
        --disable-sdl-graphics --disable-gl-graphics \
        --disable-mswin-graphics --with-owner=no --with-group=no \
        --with-compression=no
      make all LIBS='-lm -ltinfo'

    HACKDIR in include/config.h names this package's data directory; edit
    it for another prefix. The Nix package installs src/acehack as
    libexec/acehack-real, dat/nhdat and dat/license into share/acehack, and
    bin/acehack, which keeps saves, scores, logs and dumps in
    XDG_DATA_HOME/acehack and reads .acehackrc from XDG_CONFIG_HOME/acehack.
    EOF

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    doc=$out/share/doc/acehack
    test -x $out/libexec/recover
    test -s $out/share/acehack/nhdat
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/acehack/license
    grep -qF '${rev}' $doc/SOURCE-NOTICE
    test -s $doc/default.nix

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

    # The launcher creates private state and the game lists its (empty)
    # score file from the store data directory.
    export HOME=$(mktemp -d) XDG_DATA_HOME= XDG_CONFIG_HOME=
    $out/bin/acehack -s > scores 2>&1 || { cat scores; exit 1; }
    cat scores
    test -d $HOME/.local/share/acehack/save
    test -e $HOME/.local/share/acehack/record
    test "$(stat -c %a $HOME/.local/share/acehack)" = 700
    runHook postInstallCheck
  '';

  meta = {
    description = "NetHack variant focused on interface improvements, for the terminal";
    longDescription = ''
      AceHack is Alex Smith's historical NetHack 3.4.3 variant that keeps
      gameplay close to the original while improving the interface. This
      package builds the final commit of its public mirror with the terminal
      interface. Saves, scores, logs and dumps live in XDG_DATA_HOME/acehack;
      configuration (.acehackrc) in XDG_CONFIG_HOME/acehack.
    '';
    homepage = "https://github.com/deepy/acehack";
    license = lib.licenses.ngpl;
    mainProgram = "acehack";
    platforms = [ "x86_64-linux" ];
  };
})
