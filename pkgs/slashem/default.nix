{ lib, stdenv, fetchurl, bison, flex, ncurses, gzip, coreutils, runtimeShell }:

let
  rev = "aae9ef2e4c2e5b591a3bc5ded888bab1e157b20b";
  # Commit date of ${rev} (2024-02-10), used as makedefs' build time.
  buildTime = "1707587348";
  # Upstream files changed below, in the order they are listed in SOURCE-NOTICE.
  modified = [
    "include/unixconf.h" "include/config.h" "include/decl.h" "src/decl.c"
    "src/options.c" "include/extern.h" "src/botl.c" "src/display.c"
    "src/end.c" "src/potion.c" "src/tech.c" "util/lev_comp.y"
    "util/makedefs.c" "sys/autoconf/Makefile.top" "sys/autoconf/Makefile.src"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "slashem";
  version = "0.0.8E0F2-0.aae9ef2";

  # Hardfought's SLASH'EM tree, branch master at commit ${rev}.
  src = fetchurl {
    url = "https://codeload.github.com/k21971/SlashEM/tar.gz/${rev}";
    name = "slashem-${finalAttrs.version}.tar.gz";
    hash = "sha256-5Ilh7lStiwKw6YWdF6TIlfrXW7Wgs1WNO4ixTxgnmQc=";
  };

  # The NetHack General Public License requires modified files to carry
  # prominent notices stating the change and its date.  Every edit must
  # match exactly as often as expected, or the build stops.
  postPatch = ''
    fail() { echo "slashem postPatch: $*" >&2; exit 1; }

    # replace FILE COUNT OLD NEW: literal replacement of exactly COUNT matches.
    replace() {
      local content rest found
      content=$(cat "$1"; echo x); content=''${content%x}
      rest=''${content//"$3"/}
      found=$(( (''${#content} - ''${#rest}) / ''${#3} ))
      [ "$found" -eq "$2" ] || fail "$1: expected $2 of '$3', found $found"
      substituteInPlace "$1" --replace-fail "$3" "$4"
    }

    # replaceLine FILE REGEX NEW: rewrite the one line matching REGEX.
    replaceLine() {
      [ "$(grep -c -- "$2" "$1")" = 1 ] || fail "$1: expected one line matching '$2'"
      sed -i "s|$2|$3|" "$1"
    }

    notice() {
      local text="Modified 2026-11-10 by the tay Nix channel: $2. See pkgs/slashem/default.nix."
      case $1 in
        *.y) sed -i "2i /* $text */" "$1" ;;
        *Makefile*) sed -i "1i # $text" "$1" ;;
        *) sed -i "1i /* $text */" "$1" ;;
      esac
    }

    # Mutable game state lives in a per-user playground named by the launcher.
    replace include/unixconf.h 1 \
      '/* #define VAR_PLAYGROUND "/var/lib/games/nethack" */' \
      '#define VAR_PLAYGROUND nh_getenv("SLASHEM_VAR_PLAYGROUND")'
    replaceLine include/unixconf.h '^#define MAIL\([[:blank:]]\)' '/* #define MAIL */\1'
    replaceLine include/unixconf.h '^#define FCMASK[[:blank:]]*0644' '#define FCMASK 0600'
    notice include/unixconf.h "playground from SLASHEM_VAR_PLAYGROUND, no mail, private file mode"

    # Immutable data in the store; dumps in the playground; no server extrainfo.
    replace include/config.h 1 \
      '#    define HACKDIR "/slashem-0.0.8E0F2"' \
      "#    define HACKDIR \"$out/share/slashem\""
    replace include/config.h 1 \
      '#define DUMP_FN "/dgldir/userdata/%N/%n/slashem/dumplog/%t.slashem.txt"' \
      '#define DUMP_FN nh_getenv("SLASHEM_DUMPFILE")'
    replace include/config.h 1 \
      '#define EXTRAINFO_FN "/dgldir/extrainfo-sl008/%n.extrainfo"' \
      '/* #define EXTRAINFO_FN */'
    notice include/config.h "store data directory, dump file from SLASHEM_DUMPFILE, no extrainfo file"

    # The dump file name is now read from the environment at startup.
    replace include/decl.h 1 'E char dump_fn[];' 'E char *dump_fn;'
    notice include/decl.h "dump_fn is a pointer"
    replace src/decl.c 1 'char dump_fn[] = DUMP_FN;' 'char *dump_fn;'
    notice src/decl.c "dump_fn is a pointer set by initoptions"
    replace src/options.c 1 'opts = getenv(NETHACK_ENV_OPTIONS);' \
      'dump_fn = DUMP_FN ? DUMP_FN : ""; opts = getenv(NETHACK_ENV_OPTIONS);'
    notice src/options.c "initoptions sets dump_fn from DUMP_FN"

    # Prototypes required by GCC 14 and later.
    replace include/extern.h 1 'E void NDECL(initoptions);' \
      'E boolean FDECL(parse_status_color_options, (char *));
    E void NDECL(initoptions);'
    replace include/extern.h 1 'E int NDECL(doopen);' \
      '#ifdef AUTO_OPEN
    E int FDECL(doopen_indir, (int, int));
    #endif
    E int NDECL(doopen);'
    notice include/extern.h "declared parse_status_color_options and doopen_indir"
    replace src/botl.c 1 '#include "hack.h"' '#include "hack.h"
    #include "wintty.h"'
    replace src/botl.c 1 'term_end_color(color_option.color);' 'term_end_color();'
    notice src/botl.c "tty prototypes included; term_end_color takes no argument"
    replace src/display.c 1 'return ;' "return ' ';"
    notice src/display.c "absent glyph returns a blank"
    replace src/end.c 1 'void FDECL(do_vanquished, (int, BOOLEAN_P, BOOLEAN_P));' \
      'boolean FDECL(do_vanquished, (int, BOOLEAN_P, BOOLEAN_P));'
    replace src/end.c 1 '  do_vanquished(defquery, ask, FALSE);' \
      '  return do_vanquished(defquery, ask, FALSE);'
    replace src/end.c 1 'void
    do_vanquished(defquery, ask, want_dump)' 'boolean
    do_vanquished(defquery, ask, want_dump)'
    notice src/end.c "do_vanquished returns its boolean result"
    replace src/potion.c 1 'int chg, otyp = obj->otyp, otyp2;' \
      'int chg, otyp = obj->otyp; short otyp2;'
    notice src/potion.c "otyp2 is short, as artifact_name writes"
    replace src/tech.c 1 'aborttech(tech)
    {' 'aborttech(tech)
    int tech;
    {'
    notice src/tech.c "aborttech declares its int parameter"
    replace util/lev_comp.y 1 '(struct room_door *)0' '(room_door *)0'
    notice util/lev_comp.y "room_door is a typedef, not a struct tag"

    # makedefs embeds the build clock; use the commit date instead.
    replace util/makedefs.c 1 '(void) time(&clocktim);' 'clocktim = ${buildTime};'
    replace util/makedefs.c 1 '(void) time((time_t *)&clocktim);' 'clocktim = ${buildTime};'
    notice util/makedefs.c "fixed build time (2024-02-10) for reproducible output"

    # The shipped doc/Guidebook.txt is installed instead of typesetting it
    # with tmac.n, and every compiled special level goes into nhushare.
    replace sys/autoconf/Makefile.top 1 \
      ' recover$(EXEEXT) Guidebook $(CNF_SHARE_DAT)' ' recover$(EXEEXT) $(CNF_SHARE_DAT)'
    replaceLine sys/autoconf/Makefile.top '^UNSHARE_DATDLB = .*' \
      'UNSHARE_DATDLB = dungeon $(notdir $(sort $(wildcard dat\/*.lev)))'
    notice sys/autoconf/Makefile.top "Guidebook not typeset; all compiled levels archived"
    replaceLine sys/autoconf/Makefile.src '^LIBS =$' 'LIBS = @LIBS@'
    notice sys/autoconf/Makefile.src "LIBS taken from configure"

    # Neither is used by this build: tmac.n forbids sale, and the instrument
    # samples state no grant.
    rm doc/tmac.n
    rm -r sys/share/sounds

    # The complete source as built, installed beside the binary below.
    cp -r --preserve=mode . $NIX_BUILD_TOP/corresponding-source
  '';

  nativeBuildInputs = [ bison flex ];
  buildInputs = [ ncurses ];

  # ncurses provides has_colors and its split libtinfo provides tgetent.
  env = {
    LIBS = "-ltinfo";
    COMPRESS = "${gzip}/bin/gzip";
    TZ = "UTC0";
    # K&R definitions need a pre-C23 dialect; -fcommon for tentative globals.
    NIX_CFLAGS_COMPILE = "-std=gnu11 -fcommon";
  };

  # Upstream passes many non-literal strings as printf formats (makedefs.c,
  # among others); Nixpkgs' format hardening makes those warnings errors.
  hardeningDisable = [ "format" ];

  configureFlags = [
    "--enable-tty-graphics" "--disable-proxy-graphics"
    "--disable-x11-graphics" "--disable-sdl-graphics"
    "--disable-gl-graphics" "--disable-mswin-graphics"
    "--with-owner=no" "--with-group=no"
    "--with-compression=${gzip}/bin/gzip"
  ];

  buildFlags = [ "all" ];
  # makedefs, lev_comp, dgn_comp and dlb outputs depend on each other.
  enableParallelBuilding = false;

  # The launcher already has an absolute interpreter; patching would
  # rewrite scripts in the installed corresponding source.
  dontPatchShebangs = true;

  # Upstream's install target sets games ownership and setgid modes.
  installPhase = ''
    runHook preInstall

    data=$out/share/slashem
    doc=$out/share/doc/slashem
    install -Dm555 src/slashem $out/libexec/slashem-real
    install -Dm555 util/recover $out/libexec/recover
    install -Dm644 -t $data dat/nhshare dat/nhushare dat/license
    install -Dm644 doc/Guidebook.txt $data/Guidebook.txt
    install -Dm644 -t $doc LICENSE dat/license readme.txt README.34 history.txt \
      README-compile.txt Porting doc/Guidebook.txt
    install -Dm644 -t $out/share/man/man6 doc/slashem.6 doc/recover.6

    mkdir -p $out/bin
    cat > $out/bin/slashem <<'EOF'
    #!${runtimeShell}
    set -eu
    umask 077
    state="''${XDG_DATA_HOME:-''${HOME:?}/.local/share}/slashem"
    config="''${XDG_CONFIG_HOME:-''${HOME:?}/.config}/slashem"
    case $state:$config in /*:/*) ;; *)
      echo 'slashem: XDG paths must be absolute' >&2; exit 1;; esac
    export SLASHEM_VAR_PLAYGROUND="$state/"
    export SLASHEM_DUMPFILE="$state/dumps/%t.slashem.txt"
    # The game ignores environment values longer than 128 bytes.
    for path in "$SLASHEM_VAR_PLAYGROUND" "$SLASHEM_DUMPFILE" "$config"; do
      if test "$(LC_ALL=C; echo "''${#path}")" -gt 128; then
        echo 'slashem: path exceeds the 128-byte environment limit' >&2; exit 1
      fi
    done
    ${coreutils}/bin/mkdir -p -- "$state/save" "$state/dumps" "$config"
    for file in perm record logfile xlogfile paniclog; do
      test -e "$state/$file" || : > "$state/$file"
    done
    export TERMINFO_DIRS="${ncurses}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    export HOME="$config" HACKDIR=${placeholder "out"}/share/slashem NETHACKDIR=${placeholder "out"}/share/slashem
    exec ${placeholder "out"}/libexec/slashem-real "$@"
    EOF
    chmod 555 $out/bin/slashem

    # Complete corresponding source, as required by the NetHack General
    # Public License.
    cp -r --preserve=mode $NIX_BUILD_TOP/corresponding-source $doc/source
    install -Dm644 ${./default.nix} $doc/default.nix
    cat > $doc/SOURCE-NOTICE <<'EOF'
    SLASH'EM ${finalAttrs.version}: complete corresponding source

    The directory source/ holds the complete source code from which this
    package's programs and data were built, exactly as compiled. The build
    regenerates the level and dungeon compilers' parsers from util/*.y and
    util/*.l, and all headers, levels and data archives from these files.
    Upstream also ships pregenerated sys/share/*_yacc.c, *_lex.c and
    *_comp.h, which this build does not use, and the plain-text
    doc/Guidebook.txt formatted from doc/Guidebook.mn, which is installed.

    Upstream: https://github.com/k21971/SlashEM, commit ${rev}.
    Archive: ${finalAttrs.src.url}
    Archive hash: ${finalAttrs.src.outputHash}
      (nix-base32 sha256 ${builtins.convertHash { hash = finalAttrs.src.outputHash; toHashFormat = "nix32"; }})

    Changes from the upstream archive, made 2026-11-10 by the tay Nix
    channel. Each modified file carries a dated notice near its top
    (after the first line in util/lev_comp.y).
      include/unixconf.h: VAR_PLAYGROUND from SLASHEM_VAR_PLAYGROUND,
        MAIL disabled, FCMASK 0600.
      include/config.h: HACKDIR is this package's share/slashem; DUMP_FN
        from SLASHEM_DUMPFILE; EXTRAINFO_FN disabled.
      include/decl.h, src/decl.c: dump_fn is a pointer.
      src/options.c: initoptions sets dump_fn from DUMP_FN.
      include/extern.h: prototypes for parse_status_color_options and
        doopen_indir.
      src/botl.c: includes wintty.h; term_end_color takes no argument.
      src/display.c: an absent glyph returns a blank.
      src/end.c: do_vanquished returns its boolean result.
      src/potion.c: otyp2 is short, the type artifact_name writes.
      src/tech.c: aborttech declares its int parameter.
      util/lev_comp.y: room_door is used as the typedef it is.
      util/makedefs.c: build time fixed at 2024-02-10 (${buildTime}).
      sys/autoconf/Makefile.top: the Guidebook is not typeset (the shipped
        doc/Guidebook.txt is installed); every compiled level goes into
        nhushare.
      sys/autoconf/Makefile.src: LIBS taken from configure.
    Removed from the archive:
      doc/tmac.n: its terms forbid selling it; with the Guidebook not
        typeset, the build does not use it.
      sys/share/sounds: instrument samples for the Macintosh port, with
        no stated grant; the build does not use them.
    No other file differs from the archive.

    The Nix build expression is default.nix in this directory. To rebuild
    without Nix, with a C compiler, bison, flex, gzip and ncurses (with
    split libtinfo):

      cd source
      LIBS=-ltinfo CFLAGS='-O2 -std=gnu11 -fcommon' COMPRESS=/path/to/gzip \
        ./configure --prefix=PREFIX --enable-tty-graphics \
        --disable-proxy-graphics --disable-x11-graphics \
        --disable-sdl-graphics --disable-gl-graphics \
        --disable-mswin-graphics --with-owner=no --with-group=no \
        --with-compression=/path/to/gzip
      make all

    HACKDIR in include/config.h names this package's data directory; edit
    it for another prefix. The Nix package installs src/slashem as
    libexec/slashem-real, dat/nhshare, dat/nhushare and dat/license into
    share/slashem, and bin/slashem, which keeps saves, scores, dumps and
    configuration in XDG_DATA_HOME/slashem and XDG_CONFIG_HOME/slashem.
    EOF

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/slashem-real
    test -x $out/libexec/recover
    test -s $out/share/slashem/nhshare
    test -s $out/share/slashem/nhushare
    doc=$out/share/doc/slashem
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/slashem/license
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $doc/LICENSE
    grep -qF '${rev}' $doc/SOURCE-NOTICE
    test -s $doc/default.nix

    # The installed source must equal the upstream archive apart from the
    # modified files and two removals listed in SOURCE-NOTICE.
    pristine=$(mktemp -d)
    tar -xzf $src -C $pristine
    diff -rq $pristine/* $doc/source | sed "s|$pristine/[^/]*|A|; s|$doc/source|B|" > differences || true
    {
      for f in ${lib.escapeShellArgs modified}; do
        echo "Files A/$f and B/$f differ"
      done
      echo 'Only in A/doc: tmac.n'
      echo 'Only in A/sys/share: sounds'
    } > expected
    sort differences | diff -u <(sort expected) -
    for f in ${lib.escapeShellArgs modified}; do
      head -n2 $doc/source/$f | grep -q 'Modified 2026-11-10 by the tay Nix channel'
    done
    rm -r $pristine
    runHook postInstallCheck
  '';

  meta = {
    description = "Extended-magic NetHack variant for the terminal";
    longDescription = ''
      SLASH'EM (Super Lotsa Added Stuff Hack, Extended Magic) is a NetHack
      variant with additional roles, races, monsters, items and dungeon
      levels. This package builds Hardfought's source revision with the
      terminal interface. Saves, scores, logs and dumps live in
      XDG_DATA_HOME/slashem; configuration (.slashemrc) in
      XDG_CONFIG_HOME/slashem.
    '';
    homepage = "https://github.com/k21971/SlashEM";
    license = lib.licenses.ngpl;
    mainProgram = "slashem";
    platforms = [ "x86_64-linux" ];
  };
})
