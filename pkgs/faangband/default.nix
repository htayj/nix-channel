{ lib, stdenv, fetchFromGitHub, autoconf, automake, pkg-config, coreutils
, ncurses, libx11, SDL2, SDL2_image, SDL2_ttf, SDL2_mixer }:

stdenv.mkDerivation (finalAttrs: {
  pname = "faangband";
  version = "2.0.1";

  src = fetchFromGitHub {
    owner = "NickMcConnell";
    repo = "FAangband";
    rev = "7ad7178b5da5819fe1a2d13182001b5bf6e9eaac";
    hash = "sha256-MxU/VLbVhojRQyhmttA1xVgxshGsd/5aJL3uzZtXc1k=";
  };

  # Shockbolt's tiles may not be modified or used outside Angband, so drop the
  # directory and its two list.txt records (5 and 6).  Other tiles are free.
  postPatch = ''
    rm -r lib/tiles/shockbolt
    substituteInPlace lib/tiles/Makefile --replace-fail ' old shockbolt' ' old'
    awk 'BEGIN { keep = 1 } /^name:/ { keep = ($0 !~ /^name:[56]:/) } keep' \
      lib/tiles/list.txt > list.txt.new
    mv list.txt.new lib/tiles/list.txt
    if grep -q shockbolt lib/tiles/list.txt; then
      echo 'shockbolt records remain in list.txt' >&2; exit 1
    fi

    # scripts/version.sh reads this file instead of Git metadata.
    echo ${finalAttrs.version} > version

    substituteInPlace lib/icons/faangband-sdl.desktop \
      --replace-fail -msdl -msdl2 \
      --replace-fail 'Name=FAangband (SDL)' 'Name=FAangband (SDL2)'
    for f in lib/icons/faangband-sdl.desktop lib/icons/faangband-x11.desktop; do
      substituteInPlace $f \
        --replace-fail 'Exec=faangband ' "Exec=$out/bin/faangband " \
        --replace-fail 'TryExec=faangband' "TryExec=$out/bin/faangband" \
        --replace-fail /usr/share/faangband/xtra/icon/att-32.png \
                       $out/share/faangband/icons/att-32.png
    done
  '';

  # The GitHub tree has no generated configure script.
  preConfigure = "sh autogen.sh";

  nativeBuildInputs = [ autoconf automake pkg-config ];
  buildInputs = [ ncurses libx11 SDL2 SDL2_image SDL2_ttf SDL2_mixer ];

  # sdl2-config only describes SDL itself; the extensions live in other inputs.
  env.NIX_CFLAGS_COMPILE = toString (map (p: "-I${lib.getDev p}/include/SDL2")
    [ SDL2_image SDL2_ttf SDL2_mixer ]);

  configureFlags = [
    "--with-private-dirs"
    "--enable-curses"
    "--enable-x11"
    "--enable-sdl2"
    "--enable-sdl2-mixer"
    "--bindir=${placeholder "out"}/libexec"
    "--sysconfdir=${placeholder "out"}/share"
    "--localstatedir=${placeholder "out"}/var"
  ];

  # Immutable assets come from the store; saves, scores and user files go to
  # $XDG_DATA_HOME/faangband (default ~/.local/share/faangband).
  postInstall = ''
    data=$out/share/faangband
    mkdir -p $out/bin
    cat > $out/bin/faangband <<EOF
    #!${stdenv.shell}
    set -eu
    state=\''${XDG_DATA_HOME:-\''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/faangband
    (umask 077; ${coreutils}/bin/mkdir -p -- "\$state/user" "\$state/save" \\
      "\$state/scores" "\$state/archive" "\$state/info" "\$state/bone")
    state=\$(CDPATH= cd -- "\$state" && pwd -P)
    for file in user.hlp dummy.txt; do
      if test ! -e "\$state/info/\$file"; then
        (umask 077; ${coreutils}/bin/cp --no-clobber -- "$data/user/info/\$file" "\$state/info/\$file")
      fi
    done
    exec $out/libexec/faangband \\
      "-dgamedata=$data/gamedata" "-dpref=$data/customize" \\
      "-dhelp=$data/help" "-dscreens=$data/screens" \\
      "-dfonts=$data/fonts" "-dtiles=$data/tiles" \\
      "-dsounds=$data/sounds" "-dicons=$data/icons" \\
      "-dghost=$data/ghost" \\
      "-duser=\$state/user" "-dsave=\$state/save" "-dscores=\$state/scores" \\
      "-darchive=\$state/archive" "-dinfo=\$state/info" "-dbone=\$state/bone" \\
      "\$@"
    EOF
    chmod 555 $out/bin/faangband

    install -Dm644 -t $out/share/applications \
      $data/icons/faangband-x11.desktop $data/icons/faangband-sdl.desktop
    install -Dm644 -t $out/share/doc/faangband \
      README.md changes.txt docs/copying.rst docs/thanks.rst lib/readme.txt
    # Component copyright notices that must accompany binary releases.
    install -Dm644 -t $out/share/doc/faangband/component-notices \
      src/message.c src/message.h src/sound.h src/snd-sdl.h \
      src/z-textblock.c src/z-textblock.h src/z-rand.c src/z-util.c
  '';

  meta = {
    description = "First Age Angband roguelike with curses, X11 and SDL2 frontends";
    longDescription = ''
      FAangband is a roguelike set in Tolkien's First Age, with wilderness,
      multiple towns, races, classes and procedural dungeons.  This build
      provides the curses, X11 and SDL2 frontends with sound, fonts and the
      Original, Nomad, Adam Bolt and David Gervais tiles; the restricted
      Shockbolt tiles are omitted.  Player data is kept in
      $XDG_DATA_HOME/faangband (default ~/.local/share/faangband).
    '';
    homepage = "https://github.com/NickMcConnell/FAangband";
    # Code GPL-2.0-only (docs/copying.rst); Adam Bolt tiles any-purpose grant;
    # Gervais tiles CC BY 3.0; DASP sounds relicensed CC BY 4.0 by the rights
    # holder on 2023-12-23 (upstream commit fe28950e).
    license = with lib.licenses; [ gpl2Only cc-by-30 cc-by-40 free ];
    platforms = lib.platforms.linux;
    mainProgram = "faangband";
  };
})
