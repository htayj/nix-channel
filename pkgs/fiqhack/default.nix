{
  lib,
  stdenv,
  fetchFromGitHub,
  bison,
  flex,
  perl,
  util-linux,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "fiqhack";
  version = "4.3.0";

  # Tag 4.3.0 is commit 6292ea1d04b5cabac2865a93e3ac0d6fa6adcb84.
  src = fetchFromGitHub {
    owner = "FredrIQ";
    repo = "fiqhack";
    tag = finalAttrs.version;
    hash = "sha256-QlYpPm9W76H2Sys8AFpNDSZRB7ajm/dsX/v8W4NSA9E=";
  };

  nativeBuildInputs = [
    bison
    flex
  ];
  buildInputs = [ zlib ];
  nativeCheckInputs = [ perl ];
  nativeInstallCheckInputs = [ util-linux ];

  # NGPL section 2(a) asks for a dated notice in each changed file; every
  # edit below carries one.
  postPatch = ''
    # makedefs stamps date.h with the build clock; use the tag's commit time
    # (2017-12-07T16:12:32Z).
    substituteInPlace libnethack/util/makedefs.c \
      --replace-fail 'time(&clocktim);' \
        '/* Nix modification, 2026-11-07: reproducible build date. */ clocktim = 1512663152L;'

    # Keep options, saves, dumps and logs in the per-user data directory,
    # $XDG_DATA_HOME/FIQHack or ~/.local/share/FIQHack, creating missing
    # parents.  The -U override is unchanged.
    nestedMkdir=$(cat <<'EOF'
    /* Nix modification, 2026-11-07: create nested state parents. */
            for (char *p = basedir + 1; *p; ++p) {
                if (*p != '/') continue;
                *p = '\0';
                if (mkdir(basedir, 0755) == -1 && errno != EEXIST) {
                    umask(mask);
                    return FALSE;
                }
                *p = '/';
            }
            mkdir(basedir, 0755);
    EOF
    )
    substituteInPlace nethack/src/rungame.c \
      --replace-fail 'envval = getenv("XDG_CONFIG_HOME");' \
        'envval = getenv("XDG_DATA_HOME"); /* Nix modification, 2026-11-07: per-user XDG data state. */' \
      --replace-fail '%s/.config/FIQHack/%s' '%s/.local/share/FIQHack/%s' \
      --replace-fail 'mkdir(basedir, 0755);' "$nestedMkdir"

    # Bones, scores, locks and the panic log default to the read-only state
    # directory; point them at the per-user directory instead.
    userState=$(cat <<'EOF'
    /* Nix modification, 2026-11-07: per-user writable state, separate from
           the read-only data prefix in the store. */
    #ifdef UNIX
        char user_state[BUFSZ];
        if (!override_hackdir) {
            if (!get_gamedir(CONFIG_DIR, user_state)) {
                fputs("fiqhack: cannot create user state directory\n", stderr);
                exit(EXIT_FAILURE);
            }
            pathlist[BONESPREFIX] = user_state;
            pathlist[SCOREPREFIX] = user_state;
            pathlist[LOCKPREFIX] = user_state;
            pathlist[TROUBLEPREFIX] = user_state;
        }
    #endif
        /* Copy paths and append slashes as required. */
    EOF
    )
    substituteInPlace nethack/src/main.c \
      --replace-fail '/* alloc memory for the paths and append slashes as required */' \
        "$userState"

    # The anti-magic trap called rnd(0) for level-zero monsters, which the
    # test suite's random-number guard rejects; clamp the dice range to one.
    substituteInPlace libnethack/src/trap.c \
      --replace-fail 'mdrain_en(mtmp, rnd(m_mlev(mtmp)) + 1);' \
        '/* Nix modification, 2026-11-07: level-zero anti-magic drain. */ mdrain_en(mtmp, rnd(m_mlev(mtmp) > 0 ? m_mlev(mtmp) : 1) + 1);'

    # Upstream's TAP test suite is normally built by aimake; let it read game
    # data from the build tree and link it against the same game objects.
    substituteInPlace testbench/src/testgame.c \
      --replace-fail 'const char *gsd = aimake_get_option("gamesdatadir");' \
        '/* Nix modification, 2026-11-07: build-tree test data. */ const char *gsd = getenv("FIQHACK_TEST_DATADIR"); if (!gsd) gsd = aimake_get_option("gamesdatadir");'
    cat >> GNUmakefile <<'EOF'

    # Nix modification, 2026-11-07: upstream TAP test suite.
    TEST_O = testbench/src/testmain.o testbench/src/testgame.o testbench/src/tap.o
    $(TEST_O): CPPFLAGS += -Itestbench/include
    $(TEST_O): libnethack/include/onames.h libnethack/include/pm.h libnethack/include/verinfo.h
    testbench/testmain: $(TEST_O) $(filter-out nethack/src/% libuncursed/% tilesets/%,$(GAME_O))
    EOF
    printf '\t$(CC) $(LDFLAGS) $^ $(EXTRAS) -lz -o $@\n' >> GNUmakefile
  '';

  dontConfigure = true;

  env.TZ = "UTC0";

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "CXX=${stdenv.cc.targetPrefix}c++"
    "BINDIR=${placeholder "out"}/bin"
    "DATADIR=${placeholder "out"}/share/fiqhack"
    # Writable paths come from the per-user directory patched in above.
    "STATEDIR=${placeholder "out"}/share/fiqhack"
  ];

  # The round-robin test suite is a fuzz campaign over millions of games; a
  # fixed 1000-game sample keeps its crash and panic-log assertions.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    make $makeFlags testbench/testmain
    echo 'exec ./testbench/testmain --seed 1 --limit 1000' > upstream-tests
    FIQHACK_TEST_DATADIR=$PWD/libnethack/dat prove --exec sh upstream-tests
    rm upstream-tests
    runHook postCheck
  '';

  postInstall = ''
    doc=$out/share/doc/fiqhack
    install -Dm644 -t $doc COPYING copyright binary-copyright.pod README.md \
      libnethack/dat/license libnethack/dat/gpl \
      doc/guidebook.asc doc/changelog-fiqhack.txt
    install -Dm644 -t $doc/text-tileset-sources tilesets/dat/text/*.txt
    for f in GNUmakefile libnethack/util/makedefs.c nethack/src/main.c \
             nethack/src/rungame.c libnethack/src/trap.c testbench/src/testgame.c; do
      install -Dm644 $f $doc/nix-modified-source/$f
    done
  '';

  # Start the game on a pseudo-terminal with an empty home directory and
  # check that its state directory appears under ~/.local/share.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    mkdir -p $TMPDIR/home
    HOME=$TMPDIR/home TERM=xterm LINES=24 COLUMNS=80 \
      timeout 10 script -q -c $out/bin/fiqhack typescript < /dev/null || true
    test -d $TMPDIR/home/.local/share/FIQHack
    test ! -e $TMPDIR/home/.config/FIQHack
    runHook postInstallCheck
  '';

  meta = {
    description = "NetHack 4 variant with a native terminal interface";
    longDescription = ''
      FIQHack is a NetHack 4 variant with revised monsters, items, spells and
      dungeon mechanics.  This package builds the local terminal client with
      its ASCII and Unicode text tilesets; the network server and graphical
      assets are not built.  Options, saves, bones, scores, locks and logs go
      in $XDG_DATA_HOME/FIQHack, or ~/.local/share/FIQHack.
    '';
    homepage = "https://github.com/FredrIQ/fiqhack";
    changelog = "https://github.com/FredrIQ/fiqhack/blob/${finalAttrs.version}/doc/changelog-fiqhack.txt";
    # Game and text assets are NGPL; libuncursed is also offered under GPL-2+.
    license = [
      lib.licenses.ngpl
      lib.licenses.gpl2Plus
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "fiqhack";
  };
})
