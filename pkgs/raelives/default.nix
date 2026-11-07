{
  lib,
  stdenv,
  fetchFromGitHub,
  coreutils,
  ncurses,
  runtimeShell,
  util-linux,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "raelives";
  version = "0.0.1-unstable-2014-03-05";

  src = fetchFromGitHub {
    owner = "littleglassdiode";
    repo = "irl";
    rev = "2085fa6f55abf53ea1a07bb348f99a720763bbbd";
    hash = "sha256-83IWI3uEkRE2u9brkvPqhcM7qafAcJBLpa6Z//R8Eow=";
  };

  buildInputs = [ ncurses ];
  nativeInstallCheckInputs = [ coreutils util-linux ];

  # alloc_level allocated sizeof (level), the size of a pointer, instead of the
  # structure; the first level->map write overflowed the 8-byte block.  The
  # map rows are passed to mvwprintw as the format string; they contain no
  # '%', so printing them through "%s" draws the same screen and satisfies
  # -Werror=format-security.
  postPatch = ''
    substituteInPlace src/level.c \
      --replace-fail 'calloc(1, sizeof (level));' 'calloc(1, sizeof (*level));'
    substituteInPlace src/main.c \
      --replace-fail 'mvwprintw(field, i-starty, 0, lvl->map[i]+startx);' \
        'mvwprintw(field, i-starty, 0, "%s", lvl->map[i]+startx);'
  '';

  dontConfigure = true;

  # Upstream's ldt.sh stamps the tree and builds unquoted commands; compile the
  # seven modules directly with its flags.
  buildPhase = ''
    runHook preBuild
    $CC -Wall -std=c99 -O2 -o raelives \
      src/actor.c src/ai.c src/input.c src/level.c src/load.c src/main.c src/vector.c \
      -lm -lncurses
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 raelives $out/libexec/raelives/raelives
    for f in COPYING AUTHORS README TODO; do
      install -Dm644 "$f" "$out/share/doc/raelives/$f"
    done
    mkdir -p $out/bin
    cat > $out/bin/raelives <<EOF
    #!${runtimeShell}
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/raelives/raelives "\$@"
    EOF
    chmod 555 $out/bin/raelives
    runHook postInstall
  '';

  # Start the game on a pseudo-terminal, move once, and quit with Q.  A clean
  # exit shows that the level allocation, curses setup and quit key work.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    printf 'lQ' > keys
    HOME=$TMPDIR TERM=xterm LINES=24 COLUMNS=80 TERMINFO_DIRS= \
      timeout 20 script -q -e -c "$out/bin/raelives" typescript < keys
    grep -q 'Mental.En' typescript
    runHook postInstallCheck
  '';

  meta = {
    description = "Small ncurses ASCII roguelike";
    longDescription = ''
      Intelligence: Rae Lives is an early C99 ncurses roguelike by Clayton G.
      Hobbs.  This revision has one static map, movement with vi keys, the
      numeric keypad or arrows, and Q to quit; saving, enemies and items were
      never implemented.
    '';
    homepage = "https://github.com/littleglassdiode/irl";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "raelives";
  };
})
