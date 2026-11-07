{
  lib,
  stdenv,
  fetchurl,
  coreutils,
  groff,
  ncurses,
  runtimeShell,
  util-linux,
}:

stdenv.mkDerivation {
  pname = "srogue";
  version = "9.0";

  # The Roguelike Gallery collection release; its srogue/ tree matches
  # upstream commit 6bb7e13c1fd1b674860c7a20809aa41657f94ea3 plus generated
  # Autoconf files.
  src = fetchurl {
    url = "https://rlgallery.org/files/early-roguelike-rel2021.03-src.tgz";
    hash = "sha256-ViaqvTq9MoyaYBb93DWgISAgsC0hbuWbXmPoFGyGviY=";
  };

  # configure finds install-sh in the collection's top directory.
  sourceRoot = "early-roguelike-rel2021.03-src/srogue";

  # Keep scores and saves in the player's ROGUEHOME or HOME, bound copies into
  # fixed buffers, and read 4-byte save fields correctly on LP64.  The patch is
  # rooted at the collection's top directory.
  patches = [ ./srogue-portable-state.patch ];
  patchFlags = [ "-p2" ];

  # Nix hardening builds with -Werror=format-security; spacemsg is a plain
  # string, so print it through "%s".
  postPatch = ''
    substituteInPlace command.c \
      --replace-fail 'wprintw(hw,spacemsg);' 'wprintw(hw, "%s", spacemsg);'
  '';

  nativeBuildInputs = [ groff ];
  buildInputs = [ ncurses ];
  nativeInstallCheckInputs = [ coreutils util-linux ];

  # Old-style declarations such as `char *xcrypt();' conflict with prototypes
  # under C23.
  env.NIX_CFLAGS_COMPILE = "-std=gnu17";

  # Upstream defaults install a setgid binary with host-wide score, log and
  # save locations; all state goes below the user's data directory instead.
  configureFlags = [
    "--with-ncurses"
    "--with-program-name=srogue"
    "--disable-setgid"
    "--disable-scorefile"
    "--disable-logfile"
    "--disable-savedir"
  ];

  # Upstream's install target creates the host-wide score file that configure
  # was told not to use.  The game keeps srogue.sav and srogue.scr in
  # ROGUEHOME, falling back to HOME; the launcher points both at the state
  # directory.  home[] is an 80-byte buffer that must also hold "/srogue.sav"
  # and a NUL, so longer directories are rejected before anything is created.
  installPhase = ''
    runHook preInstall
    install -Dm755 srogue $out/libexec/srogue/srogue
    install -Dm644 -t $out/share/doc/srogue LICENSE.TXT rogue.nr srogue.doc
    mkdir -p $out/bin
    cat > $out/bin/srogue <<'EOF'
    #!@runtimeShell@
    set -eu
    case "''${XDG_DATA_HOME:-}" in
      /*) state="$XDG_DATA_HOME/srogue" ;;
      *) state="''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share/srogue" ;;
    esac
    state_bytes=$(LC_ALL=C; printf %s "''${#state}")
    if [ "$state_bytes" -gt 68 ]; then
      echo 'srogue: state directory is too long (at most 68 bytes)' >&2
      exit 1
    fi
    @mkdir@ -p -- "$state"
    export HOME="$state" ROGUEHOME="$state"
    export TERMINFO_DIRS="@terminfo@''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    cd -- "$state"
    exec @libexec@/srogue "$@"
    EOF
    substituteInPlace $out/bin/srogue \
      --subst-var-by runtimeShell ${runtimeShell} \
      --subst-var-by mkdir ${coreutils}/bin/mkdir \
      --subst-var-by terminfo ${ncurses}/share/terminfo \
      --subst-var-by libexec $out/libexec/srogue
    chmod 555 $out/bin/srogue
    runHook postInstall
  '';

  # Listing scores before any game must not create a score file.  Then start a
  # game on a pseudo-terminal, quit with Q y, pass the pack and score prompts,
  # and check that the score list is printed and its file kept in the state
  # directory.  A state directory over 68 bytes is refused.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home TERM=xterm LINES=24 COLUMNS=80 LC_ALL=C
    export ROGUEOPTS='name=Smoke Tester'
    unset XDG_DATA_HOME ROGUEHOME
    mkdir -p "$HOME"
    state=$HOME/.local/share/srogue

    $out/bin/srogue -s
    test -d "$state"
    test ! -e "$state/srogue.scr"

    # The game exits after the third return, so the slack input may hit a
    # closed pipe; only the game's exit status matters.
    { { sleep 3; printf Q; sleep 1; printf y
        for _ in 1 2 3 4; do sleep 1; printf '\n'; done; sleep 2; } 2>/dev/null || true; } \
      | timeout 60 script -q -e -c "$out/bin/srogue" typescript
    tr -d '\000' < typescript > screen
    grep -qF 'Hello Smoke Tester, One moment' screen
    grep -qF 'Really quit? [y/n/s]' screen
    grep -qF 'Contents of your pack when you chickened out' screen
    grep -qF 'Top Ten Adventurers:' screen
    test -s "$state/srogue.scr"
    $out/bin/srogue -s | grep -qF 'Top Ten Adventurers:'

    if XDG_DATA_HOME=/$(printf '%070d' 0) $out/bin/srogue -s 2> err; then
      exit 1
    fi
    grep -qF 'state directory is too long' err
    runHook postInstallCheck
  '';

  meta = {
    description = "Robert Kindelberger's expanded version of the Rogue dungeon game";
    longDescription = ''
      Super-Rogue is Robert D. Kindelberger's 1984 extension of the classic
      terminal game Rogue.  It adds character attributes such as strength,
      dexterity, wisdom and constitution, limits on the weight and volume of
      the pack, and trading posts where treasure can be bought and sold.  This
      is version 9.0 from the Roguelike Gallery's collection of early
      roguelikes.  Saved games and the personal score list are kept in
      $XDG_DATA_HOME/srogue, falling back to ~/.local/share/srogue.
    '';
    homepage = "https://rlgallery.org/";
    # BSD-style terms plus Super-Rogue endorsement and naming conditions;
    # installed as share/doc/srogue/LICENSE.TXT.
    license = {
      fullName = "Super-Rogue license (BSD-style with endorsement and naming conditions)";
      url = "https://icemonster.rlgallery.org/forge/warden/early-roguelike/raw/commit/35c5e434e658592a0139c7a110c4a323357e1019/srogue/LICENSE.TXT";
      free = true;
      redistributable = true;
    };
    platforms = [ "x86_64-linux" ];
    mainProgram = "srogue";
  };
}
