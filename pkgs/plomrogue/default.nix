{ lib, stdenv, fetchFromGitHub, perl, python3, coreutils, bash, ncurses }:

stdenv.mkDerivation {
  pname = "plomrogue";
  # The PtIG release tag of the engine, dated 2017-08-21.
  version = "0-unstable-2017-08-21";

  src = fetchFromGitHub {
    owner = "plomlompom";
    repo = "plomrogue";
    # The PtIG tag, not the unrelated newer engine branches.
    rev = "32c8b0d55c091b10ba683621d7881ef57ce8a88a";
    hash = "sha256-hauTW4eGyn5KoiGJfaVcqwvRpLXPLyPqJeuNEVsr3EY=";
  };

  nativeBuildInputs = [ perl ];
  nativeCheckInputs = [ python3 ];

  # The native save format orders Things by ID.  Modern Python dicts keep
  # insertion order, so deletion and ID reuse change actor scheduling and
  # same-cell precedence after a save/reload.  Iterating in canonical ID
  # order makes a reloaded world continue its saved random stream, and
  # restores exact equality with upstream's server test reference.  The
  # turn-start snapshots stay intact so births wait until the next turn.
  postPatch = ''
    files=$(find server plugins/server -name '*.py')
    perl -pi -e '
      s/for ([a-zA-Z_]+) in world_db\["Things"\]([[:space:]]+if|[[:space:]]*$|\]|:)/for $1 in sorted(world_db["Things"])$2/g;
      s/for Thing in world_db\["Things"\]\.values\(\)/for Thing in (world_db["Things"][tid] for tid in sorted(world_db["Things"]))/g;
    ' $files
    test "$(grep -c 'sorted(world_db\["Things"\])' $files | awk -F: '{ n += $2 } END { print n }')" -ge 19
    substituteInPlace start_server_client_union.sh test_server.sh \
      --replace-fail python3 ${python3.interpreter}
  '';

  dontConfigure = true;

  env.PYTHONDONTWRITEBYTECODE = "1";

  buildPhase = ''
    runHook preBuild
    sh build.sh
    runHook postBuild
  '';

  # Upstream's diff|wc pipeline reports a mismatch without failing, so
  # require exact equality with its reference after the 90 scripted actions.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    sh test_server.sh
    cmp testing/last_end testing/ref_end
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/plomrogue
    mkdir -p $data/testing $out/bin
    # Complete engine sources and notices, without the check phase's
    # profiles, saves or copied modules.
    cp -r server client plugins confserver $data/
    install -m755 -t $data roguelike roguelike-server roguelike-client \
      start_server_client_union.sh build.sh test_server.sh
    install -m644 -t $data libplomrogue.c NOTICE GPLv3 README README_PtIG \
      SERVER_COMMANDS TODO
    install -m555 -t $data libplomrogue.so
    install -m644 -t $data/testing testing/start testing/run testing/ref_end
    install -Dm644 -t $out/share/doc/plomrogue NOTICE GPLv3 README \
      README_PtIG SERVER_COMMANDS

    # Only engine resources are linked into the writable state directory;
    # relative save, record, log and server_run paths stay local to it.
    cat > $out/bin/plomrogue <<EOF
    #!${bash}/bin/bash
    set -eu
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/plomrogue"
    ${coreutils}/bin/mkdir -p -m 700 "\$state"
    for name in server client plugins confserver roguelike roguelike-server \\
        roguelike-client start_server_client_union.sh libplomrogue.so; do
      target="\$state/\$name"
      if [ -L "\$target" ]; then
        [ "\$(${coreutils}/bin/readlink "\$target")" = "$data/\$name" ] && continue
        ${coreutils}/bin/rm "\$target"
      elif [ -e "\$target" ]; then
        echo "plomrogue: cannot replace user file: \$target" >&2
        exit 1
      fi
      ${coreutils}/bin/ln -s "$data/\$name" "\$target"
    done
    cd "\$state"
    export PATH="${lib.makeBinPath [ python3 coreutils bash ]}\''${PATH:+:\$PATH}"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    export PYTHONDONTWRITEBYTECODE=1
    exec ./roguelike "\$@"
    EOF
    chmod 555 $out/bin/plomrogue
    runHook postInstall
  '';

  meta = {
    description = "Ecological island roguelike with an ASCII terminal interface";
    longDescription = ''
      Please the Island God is the default game in this pinned PlomRogue
      release.  Stranded on a hexagonal island, the player must please its
      god by feeding wildlife, cultivating plants and completing missions
      while surviving.  The Python curses client and C-backed server
      communicate through local files.  Saves, recordings and logs are kept
      under $XDG_STATE_HOME/plomrogue, or ~/.local/state/plomrogue when
      XDG_STATE_HOME is unset.
    '';
    homepage = "https://github.com/plomlompom/plomrogue/releases/tag/PtIG";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "plomrogue";
  };
}
