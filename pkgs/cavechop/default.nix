{
  lib,
  stdenv,
  coreutils,
  fetchurl,
  gzip,
  ncurses,
  runtimeShell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "cavechop";
  # The Makefile declares MAJVERS=1 and MINVERS=0.  The snapshot is commit
  # ecc8bcfd56b96b71a2521f9b2a005f9cc89f0692, the last master revision and
  # the bugfix-release-1 tag.
  version = "1.0";

  src = fetchurl {
    url = "http://git.blackswordsonics.com/?p=cavechop-7drl;a=snapshot;h=ecc8bcfd56b96b71a2521f9b2a005f9cc89f0692;sf=tgz";
    name = "cavechop-${finalAttrs.version}.tar.gz";
    hash = "sha256-bBbBgSXr1rP9VkAsDdIJSr/XFrdRVwDaIFC+SpCK75c=";
  };

  buildInputs = [ ncurses ];

  # Save and restore shell out to gzip; use the store path, and restore from
  # the compressed file the save step produced.  permobjs has
  # NUM_OF_PERMOBJS entries, not 100: write exactly that many records and
  # restore only their scalar fields, keeping the static names and
  # process-local description pointers.
  postPatch = ''
    substituteInPlace main.c \
      --replace-fail '"gzip cavechop.sav"' '"${gzip}/bin/gzip cavechop.sav"' \
      --replace-fail '"gunzip cavechop.sav"' '"${gzip}/bin/gunzip cavechop.sav.gz"' \
      --replace-fail 'fwrite(permobjs, 100, sizeof (struct permobj), fp);' \
        'fwrite(permobjs, NUM_OF_PERMOBJS, sizeof (struct permobj), fp);' \
      --replace-fail 'fread(permobjs, 100, sizeof (struct permobj), fp);' '{
        int i;
        struct permobj saved;
        for (i = 0; i < NUM_OF_PERMOBJS; ++i)
        {
            fread(&saved, sizeof saved, 1, fp);
            permobjs[i].poclass = saved.poclass;
            permobjs[i].rarity = saved.rarity;
            permobjs[i].sym = saved.sym;
            permobjs[i].power = saved.power;
            permobjs[i].used = saved.used;
            permobjs[i].depth = saved.depth;
        }
    }'
  '';

  dontConfigure = true;

  makeFlags = [ "all" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 cavechop $out/libexec/cavechop/cavechop
    install -Dm644 notes.txt $out/share/doc/cavechop/notes.txt
    install -Dm644 cavechop.h $out/share/doc/cavechop/cavechop.h
    mkdir -p $out/bin
    cat > $out/bin/cavechop <<EOF
    #!${runtimeShell}
    set -eu
    export TERM="\''${TERM:-xterm-256color}"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    case "\''${XDG_STATE_HOME:-}" in
      /*) state="\$XDG_STATE_HOME" ;;
      *) state="\''${HOME:?HOME must be set when XDG_STATE_HOME is not absolute}/.local/state" ;;
    esac
    state="\$state/cavechop"
    ${coreutils}/bin/mkdir -p "\$state"
    cd "\$state"
    exec $out/libexec/cavechop/cavechop "\$@"
    EOF
    chmod 555 $out/bin/cavechop
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/cavechop/cavechop
    grep -q '${gzip}/bin/gunzip cavechop.sav.gz' $out/libexec/cavechop/cavechop
    grep -q 'Martin Read' $out/share/doc/cavechop/notes.txt
    runHook postInstallCheck
  '';

  meta = {
    description = "Seven-day roguelike dungeon game";
    longDescription = ''
      Cave Chop is a terminal seven-day roguelike by Martin Read, built with
      ncurses and panel.  The launcher keeps saves, logs and character dumps
      in $XDG_STATE_HOME/cavechop, defaulting to ~/.local/state/cavechop.
    '';
    homepage = "http://git.blackswordsonics.com/?p=cavechop-7drl;a=summary";
    license = lib.licenses.bsd2;
    platforms = [ "x86_64-linux" ];
    mainProgram = "cavechop";
  };
})
