{
  lib,
  stdenv,
  fetchurl,
  coreutils,
  ncurses,
  runtimeShell,
  util-linux,
}:

stdenv.mkDerivation {
  # LICENSE.TXT reserves the original program's names for the unmodified work,
  # so this patched build is named after the vers.c banner "7.7 (Bell Labs)".
  pname = "bell-labs-rogue7";
  version = "7.7.1";

  # The Roguelike Gallery collection release; the game is its arogue7/ tree.
  src = fetchurl {
    url = "https://rlgallery.org/files/early-roguelike-rel2021.03-src.tgz";
    hash = "sha256-ViaqvTq9MoyaYBb93DWgISAgsC0hbuWbXmPoFGyGviY=";
  };

  # configure finds install-sh in the collection's top directory.
  sourceRoot = "early-roguelike-rel2021.03-src/arogue7";

  # Upstream reads ROGUEHOME for the score file only and takes the save
  # directory from the passwd database.  Let ROGUEHOME decide both.
  #
  # md_getroguedir copies ROGUEHOME into a 1024-byte buffer with a PATH_MAX
  # bound, which fortified glibc aborts on; bound the copy by the buffer.
  #
  # Nix hardening builds with -Werror=format-security; morestr, spacemsg and
  # retstr are plain strings, so print them through "%s".
  postPatch = ''
    substituteInPlace main.c --replace-fail \
      'strncpy(home, md_gethomedir(), LINELEN);' \
      'strncpy(home, (env = getenv("ROGUEHOME")) != NULL && *env ? env : md_gethomedir(), LINELEN);'
    substituteInPlace mdport.c --replace-fail \
      'strncpy(path, home, PATH_MAX - 20);' \
      'strncpy(path, home, sizeof(path) - 20);'
    substituteInPlace command.c \
      --replace-fail 'wprintw(hw, morestr);' 'wprintw(hw, "%s", morestr);' \
      --replace-fail 'wprintw(hw, spacemsg);' 'wprintw(hw, "%s", spacemsg);' \
      --replace-fail 'printf(retstr);' 'printf("%s", retstr);'
    substituteInPlace init.c \
      --replace-fail 'printf(retstr);' 'printf("%s", retstr);'
  '';

  buildInputs = [ ncurses ];
  nativeInstallCheckInputs = [ coreutils util-linux ];

  # Old-style declarations such as `extern char tolower();' conflict with
  # prototypes under C23.
  env.NIX_CFLAGS_COMPILE = "-std=gnu17";

  # Upstream defaults use a score file, log and save directory relative to
  # wherever the game is started; all state goes below the user's data
  # directory instead.
  configureFlags = [
    "--with-ncurses"
    "--with-program-name=bell-labs-rogue7"
    "--disable-setgid"
    "--disable-scorefile"
    "--disable-logfile"
    "--disable-savedir"
  ];

  # Upstream's install target creates the score file that configure was told
  # not to use.  The game keeps arogue77.sav and arogue77.scr in ROGUEHOME,
  # which the launcher points at the state directory.  The game builds both
  # file names in 256-byte buffers, so longer directories are rejected before
  # anything is created.
  installPhase = ''
    runHook preInstall
    install -Dm755 bell-labs-rogue7 $out/libexec/bell-labs-rogue7/bell-labs-rogue7
    install -Dm644 -t $out/share/doc/bell-labs-rogue7 LICENSE.TXT aguide.mm arogue77.html
    mkdir -p $out/bin
    cat > $out/bin/bell-labs-rogue7 <<'EOF'
    #!@runtimeShell@
    set -eu
    case "''${XDG_DATA_HOME:-}" in
      /*) state="$XDG_DATA_HOME/bell-labs-rogue7" ;;
      *) state="''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share/bell-labs-rogue7" ;;
    esac
    state_bytes=$(LC_ALL=C; printf %s "''${#state}")
    if [ "$state_bytes" -gt 242 ]; then
      echo 'bell-labs-rogue7: state directory is too long (at most 242 bytes)' >&2
      exit 1
    fi
    @mkdir@ -p -- "$state"
    export ROGUEHOME="$state/"
    export TERMINFO_DIRS="@terminfo@''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    exec @libexec@/bell-labs-rogue7 "$@"
    EOF
    substituteInPlace $out/bin/bell-labs-rogue7 \
      --subst-var-by runtimeShell ${runtimeShell} \
      --subst-var-by mkdir ${coreutils}/bin/mkdir \
      --subst-var-by terminfo ${ncurses}/share/terminfo \
      --subst-var-by libexec $out/libexec/bell-labs-rogue7
    chmod 555 $out/bin/bell-labs-rogue7
    runHook postInstall
  '';

  # Create a fighter on a pseudo-terminal and save the game, restore it in a
  # second process, then quit through the pack and score screens.  The save
  # and the score file must live in the state directory, and a state directory
  # over 242 bytes is refused.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home TERM=xterm LINES=24 COLUMNS=80 LC_ALL=C
    unset XDG_DATA_HOME ROGUEHOME ROGUEOPTS
    mkdir -p "$HOME" "$TMPDIR/play"
    cd "$TMPDIR/play"
    state=$HOME/.local/share/bell-labs-rogue7

    # The game exits before the slack input is used up, so that input may hit
    # a closed pipe; only the game's exit status matters.
    { { sleep 3; printf 1; sleep 2; printf '\033'; sleep 2; printf y; sleep 3
        printf S; sleep 2; printf y; sleep 3; } 2>/dev/null || true; } \
      | timeout 60 script -q -e -c "$out/bin/bell-labs-rogue7" saved
    tr -d '\000' < saved > screen
    grep -qF 'just a moment while I dig the dungeon' screen
    grep -qF 'What character class do you desire?' screen
    grep -qF 'Is this character okay?' screen
    grep -qF 'Save file (' screen
    test -s "$state/arogue77.sav"

    { { sleep 4; printf Q; sleep 2; printf 'yes\n'
        for _ in 1 2 3 4; do sleep 2; printf '\n'; done; sleep 2; } 2>/dev/null || true; } \
      | timeout 60 script -q -e -c "$out/bin/bell-labs-rogue7 -r" restored
    tr -d '\000' < restored > screen
    grep -qF 'Really quit? <yes or no>' screen
    grep -qF 'Contents of your pack when you quit:' screen
    grep -qF 'Top 10 Adventurers:' screen
    test ! -e "$state/arogue77.sav"
    test -s "$state/arogue77.scr"
    $out/bin/bell-labs-rogue7 -s | grep -qF 'Top 10 Adventurers:'

    # Nothing is written beside the state directory.
    test "$(ls -A "$TMPDIR/play")" = "$(printf 'restored\nsaved\nscreen')"
    test "$(ls -A "$state")" = arogue77.scr

    if XDG_DATA_HOME=/$(printf '%0240d' 0) $out/bin/bell-labs-rogue7 -s 2> err; then
      exit 1
    fi
    grep -qF 'state directory is too long' err
    runHook postInstallCheck
  '';

  meta = {
    description = "Historical Bell Labs terminal dungeon game, release 7.7.1";
    longDescription = ''
      The 1986 release 7.7 of a terminal dungeon game written at Bell Labs by
      Michael Morgan and Ken Dalka, as distributed in the Roguelike Gallery's
      collection of early roguelikes.  Characters choose a class, shop at an
      equipment post and descend through randomly generated levels in search
      of a quest item.  Saved games and the score list are kept in
      $XDG_DATA_HOME/bell-labs-rogue7, falling back to
      ~/.local/share/bell-labs-rogue7.  The upstream guide is installed as
      share/doc/bell-labs-rogue7/arogue77.html.
    '';
    homepage = "https://rlgallery.org/";
    # BSD-style terms plus endorsement and naming conditions; installed as
    # share/doc/bell-labs-rogue7/LICENSE.TXT.
    license = {
      fullName = "Advanced Rogue license (BSD-style with endorsement and naming conditions)";
      url = "https://icemonster.rlgallery.org/forge/warden/early-roguelike/raw/commit/35c5e434e658592a0139c7a110c4a323357e1019/arogue7/LICENSE.TXT";
      free = true;
      redistributable = true;
    };
    platforms = [ "x86_64-linux" ];
    mainProgram = "bell-labs-rogue7";
  };
}
