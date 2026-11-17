{
  lib,
  stdenv,
  fetchurl,
  bison,
  coreutils,
  flex,
  gzip,
  m4,
  ncurses,
  runtimeShell,
  unzip,
  util-linux,
  which,
}:

let
  # mibic's banner grants the LGPL without naming a version, and the archive
  # ships only GPL text.  LGPL 2.1 is selected under its section 13; these are
  # the unmodified terms from an immutable GCC mirror revision.
  lgpl = fetchurl {
    name = "calcrogue-COPYING.LGPL-2.1";
    url = "https://raw.githubusercontent.com/gcc-mirror/gcc/d0ca130aa5d50cdaeea8e5c343d65250cdf51955/COPYING.LIB";
    hash = "sha256-qb3eVhbs3R6YC0TzYGAO6Hg7H5m4zIOivrFjoKOQ6GE=";
  };
in
stdenv.mkDerivation {
  pname = "calcrogue";
  # CHANGELOG identifies Beta 6a SP1; the title screen still says Beta 6a.
  version = "6a-sp1";

  src = fetchurl {
    name = "calcrogue-6a-sp1.zip";
    url = "https://www.ticalc.org/pub/89/asm/games/rpg/crogue.zip";
    hash = "sha256-YzjY1UYNe30nBgGu2fdiiadZtthgLl9IvW4TP6OWLJA=";
  };

  sourceRoot = "calcrogue";

  # native-state.patch: the constant data file is read from the store, saves
  # and scores stay in the launcher's working directory, and gzip runs without
  # a shell.  modern-c.patch: replaces a cast-lvalue increment that current
  # GCC rejects.  Same patches as the Guix channel.
  patches = [
    ./native-state.patch
    ./modern-c.patch
  ];

  # The distribution directories hold executables, prebuilt game data and the
  # nonfree HW3Patch archive; the Palm port carries font sources.  The parser,
  # scanner and macro data outputs are regenerated from their sources.
  postPatch = ''
    rm -r binLinux binWin binPalm binTI89 binTI92p binV200 src/sys/palm
    rm src/tools/mibic/lex.yy.c src/tools/mibic/y.tab.c src/tools/mibic/y.tab.h
    rm src/auto/automatic.h src/auto/tiles.dat
    substituteInPlace src/include/machdep.h \
      --replace-fail /usr/bin/gzip ${gzip}/bin/gzip \
      --replace-fail '#	define SHARED_SCORES' \
        '/* Scores and saves are private to the launcher cwd. */'
    substituteInPlace src/sys/curses/main.c \
      --replace-fail @CALCROGUE_DATA_FILE@ $out/share/calcrogue/crogdat.dat
  '';

  nativeBuildInputs = [
    bison
    flex
    m4
    unzip
    which
  ];
  buildInputs = [ ncurses ];

  # Data generation writes automatic.h and tiles.dat, which the game objects
  # then include.
  enableParallelBuilding = false;

  # Upstream's configure is a hand-written script that selects the
  # Windows-named computer target; the three settings are replaced with the
  # Unix curses ones.
  configurePhase = ''
    runHook preConfigure
    cd src
    make -C tools/sgt CXX=$CXX
    sh configure
    sed -i \
      -e 's|^PC_CC_OPTS[ \t]*:=.*|PC_CC_OPTS := -DTARGET=T_UNIX -Wall -std=gnu89|' \
      -e 's|^PC_CC_OPTS_TOOL[ \t]*:=.*|PC_CC_OPTS_TOOL := -Wall -std=gnu89|' \
      -e 's|^PC_CC_LIBS[ \t]*:=.*|PC_CC_LIBS := -lncurses|' \
      auto/configure.mk
    mkdir -p ../binLinux
    runHook postConfigure
  '';

  # The data compiler is built first, then the game data, then the game.
  buildPhase = ''
    runHook preBuild
    make -C tools/mibic CC=$CC LEX=flex 'YACC=bison -y' 'CCOPTS=-Wall -O2 -std=gnu89'
    make ../binLinux/crogdat.dat BUILD_VERBOSE=1
    make linux BUILD_VERBOSE=1
    runHook postBuild
  '';

  # The game keeps its save, saved levels, options and scores in the working
  # directory, so the launcher enters a private state directory first.
  installPhase = ''
    runHook preInstall
    install -Dm555 ../binLinux/crogue $out/libexec/calcrogue/calcrogue
    install -Dm444 -t $out/share/calcrogue ../binLinux/crogdat.dat

    doc=$out/share/doc/calcrogue
    install -Dm444 -t $doc COPYING README CHANGELOG ../readme.txt
    install -Dm444 ${lgpl} $doc/COPYING.LGPL-2.1
    install -Dm444 -t $doc/sgt tools/sgt/COPYING
    # The files that state the grants themselves.
    install -Dm444 -t $doc/mibic tools/mibic/src/main.c
    install -Dm444 -t $doc src/crogue.c
    cat > $doc/SOURCE <<'EOF'
    CalcRogue Beta 6a SP1, recovered ticalc.org archive.
    Archive SHA256: 6338d8d5460d7b7d270601aed9f76289a759b6d8602e5f48bd6e133fa3962c90
    Game and data: GPL 2 or later (see crogue.c).
    mibic: unversioned LGPL banner in mibic/main.c.
    LGPL 2.1 selected under section 13, not author-stated.
    GNU LGPL terms from GCC mirror revision:
    d0ca130aa5d50cdaeea8e5c343d65250cdf51955.
    Native i686 preserves the upstream 32-bit VM/C ABI.
    Modifications, 2026-10-09: immutable data separated
    from private cwd saves/scores; compressed cleanup,
    absent-save detection; shell-free store gzip;
    replace obsolete cast-lvalue pointer increment.
    Flex/Bison outputs and game data rebuilt from source.
    All bin* and Palm font sources excluded.
    Historical latest-release status is not established.
    EOF

    mkdir -p $out/bin
    cat > $out/bin/calcrogue <<'EOF'
    #!@shell@
    set -eu
    umask 077
    # Relative XDG_STATE_HOME values are ignored, as the XDG specification requires.
    case "''${XDG_STATE_HOME:-}" in
      /*) state_home=$XDG_STATE_HOME ;;
      *) state_home="''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state" ;;
    esac
    case "$state_home" in
      /*) ;;
      *) echo "calcrogue: state directory must be absolute: $state_home" >&2; exit 1 ;;
    esac
    state=$(@coreutils@/bin/realpath -m -- "$state_home/calcrogue")
    case "$state" in
      @storeDir@|@storeDir@/*)
        echo "calcrogue: refusing state in the immutable store: $state" >&2; exit 1 ;;
    esac
    @coreutils@/bin/mkdir -p -- "$state"
    cd -- "$state"
    export TERMINFO_DIRS="@terminfo@''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec @out@/libexec/calcrogue/calcrogue "$@"
    EOF
    substituteInPlace $out/bin/calcrogue \
      --subst-var-by shell ${runtimeShell} \
      --subst-var-by coreutils ${coreutils} \
      --subst-var-by storeDir ${builtins.storeDir} \
      --subst-var-by terminfo ${ncurses}/share/terminfo \
      --subst-var-by out $out
    chmod 555 $out/bin/calcrogue
    runHook postInstall
  '';

  # Upstream has no automated tests.  The smoke script plays, saves, restores
  # and saves again on an 80x25 pseudo-terminal and checks the launcher.
  doInstallCheck = true;
  nativeInstallCheckInputs = [
    gzip
    util-linux
  ];
  installCheckPhase = ''
    runHook preInstallCheck
    sh ${./smoke.sh} $out
    runHook postInstallCheck
  '';

  meta = {
    description = "Native terminal port of a calculator roguelike";
    longDescription = ''
      CalcRogue is a turn-based dungeon exploration game originally written
      for calculators, PDAs and computers.  This package builds the recovered
      Beta 6a SP1 source and its generated game data for the Linux curses
      frontend.  The game's bytecode compiler and C structures assume the
      32-bit x86 ABI, so it is built as an i686 program and runs on x86_64
      hosts.  Saves, saved levels, options and high scores are kept in
      $XDG_STATE_HOME/calcrogue, falling back to ~/.local/state/calcrogue.
      The calculator binaries, HW3Patch and the Palm font sources are not
      included.
    '';
    homepage = "https://www.ticalc.org/archives/files/fileinfo/260/26014.html";
    # mibic states the LGPL without a version; see share/doc/calcrogue/SOURCE.
    license = with lib.licenses; [
      gpl2Plus
      lgpl21Only
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    mainProgram = "calcrogue";
    platforms = [ "i686-linux" ];
  };
}
