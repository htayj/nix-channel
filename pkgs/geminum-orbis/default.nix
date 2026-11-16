{
  lib,
  stdenv,
  fetchsvn,
  coreutils,
  ncurses,
  runtimeShell,
  util-linux,
}:

stdenv.mkDerivation {
  pname = "geminum-orbis";
  # The unreleased trunk has no version file; this is Subversion revision 59.
  version = "0-r59";

  src = fetchsvn {
    url = "https://svn.code.sf.net/p/adventurerpg/code/trunk/";
    rev = "59";
    hash = "sha256-wJ08tx8pg3v0J+1j4TrvkeqhqVgHot+hlyloe/tIaTA=";
  };

  # The checkout has CRLF line endings and the patch is written against LF.
  # Only the C++ sources are converted; the maps and documents stay as they
  # are.
  prePatch = ''
    sed -i 's/\r$//' *.h *.cpp
  '';

  # Native ncurses port of the Windows console program: no conio or Win32
  # calls, standard curses colours and line-drawing characters, checked
  # terminal size and colour support, and the two maps read from
  # GEMINUM_DATA_DIR.  Same patch as the Guix channel.
  patches = [ ./platform.patch ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];

  buildInputs = [ ncurses ];

  dontConfigure = true;

  # The game headers and geminumorbis.cpp form one translation unit.
  buildPhase = ''
    runHook preBuild
    $CXX -std=gnu++11 -O2 \
      -DGEMINUM_DATA_DIR="\"$out/share/geminum-orbis/levels\"" \
      geminumorbis.cpp -o geminum-orbis -lncursesw
    runHook postBuild
  '';

  # The game creates its highscores file in the working directory, so the
  # launcher enters a private state directory first.
  installPhase = ''
    runHook preInstall
    install -Dm755 geminum-orbis $out/libexec/geminum-orbis/geminum-orbis
    install -Dm644 -t $out/share/geminum-orbis/levels levels/*.txt
    mkdir -p $out/share/doc/geminum-orbis
    cp -r docs $out/share/doc/geminum-orbis/upstream
    # Revision 59 has no licence file.
    install -Dm644 ${./LICENSE-PROVENANCE.txt} \
      $out/share/doc/geminum-orbis/LICENSE-PROVENANCE.txt

    mkdir -p $out/bin
    cat > $out/bin/geminum-orbis <<'EOF'
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
      *) echo "geminum-orbis: state directory must be absolute: $state_home" >&2; exit 1 ;;
    esac
    state=$(@coreutils@/bin/realpath -m -- "$state_home/geminum-orbis")
    case "$state" in
      @storeDir@|@storeDir@/*)
        echo "geminum-orbis: refusing state in the immutable store: $state" >&2; exit 1 ;;
    esac
    @coreutils@/bin/mkdir -p -- "$state"
    cd -- "$state"
    export TERMINFO_DIRS="@terminfo@''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec @out@/libexec/geminum-orbis/geminum-orbis "$@"
    EOF
    substituteInPlace $out/bin/geminum-orbis \
      --subst-var-by shell ${runtimeShell} \
      --subst-var-by coreutils ${coreutils} \
      --subst-var-by storeDir ${builtins.storeDir} \
      --subst-var-by terminfo ${ncurses}/share/terminfo \
      --subst-var-by out $out
    chmod 555 $out/bin/geminum-orbis
    runHook postInstall
  '';

  # Upstream has no automated tests.  The smoke script plays a short game on
  # an 80x25 pseudo-terminal and checks the launcher's refusals.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ util-linux ];
  installCheckPhase = ''
    runHook preInstallCheck
    sh ${./smoke.sh} $out
    runHook postInstallCheck
  '';

  meta = {
    description = "Unfinished terminal dungeon roguelike, formerly Adventure RPG";
    longDescription = ''
      Geminum Orbis is Kevin Wells's unfinished terminal dungeon roguelike,
      previously known as Adventure RPG.  This package builds the original
      C++ Subversion revision 59 with a native ncurses interface and both
      original static maps.  It has character generation, dungeon
      exploration, doors and stairs; upstream never implemented saving and
      loading.  The terminal must have at least 80 columns and 25 rows and
      support colours.  The highscores file is kept in
      $XDG_STATE_HOME/geminum-orbis, falling back to
      ~/.local/state/geminum-orbis.
    '';
    homepage = "https://sourceforge.net/projects/adventurerpg/";
    # The author set the RogueBasin licensing field to public domain;
    # SourceForge lists the project as GPLv2.  See
    # share/doc/geminum-orbis/LICENSE-PROVENANCE.txt.
    license = lib.licenses.publicDomain;
    mainProgram = "geminum-orbis";
    platforms = [ "x86_64-linux" ];
  };
}
