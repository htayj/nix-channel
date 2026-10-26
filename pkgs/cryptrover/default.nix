{ lib, stdenv, fetchzip, runtimeShell, coreutils, ncurses }:

stdenv.mkDerivation (finalAttrs: {
  pname = "cryptrover";
  version = "1.1";

  src = fetchzip {
    url = "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/cryptrover/cryptrover_${finalAttrs.version}_nosound.tar.gz";
    hash = "sha256-u37Iog2aotz+IWOLw7cMUXRif3LDLgojiMBVwIAzqLE=";
  };

  buildInputs = [ ncurses ];

  # The archive ships a prebuilt `cr' and a configure script that downloads
  # optional dependencies; the build uses neither.
  postPatch = ''
    rm cr
    # mdport.c uses toupper() without including ctype.h.
    sed -i '/#include "mdport.h"/a #include <ctype.h>' src/mdport.c
    # A panel retains its window; free the panel first, or closing the help
    # screen crashes with current ncurses.
    substituteInPlace src/io.c \
      --replace-fail 'delwin(help_win);' "" \
      --replace-fail 'del_panel(help_panel);' $'del_panel(help_panel);\n\tdelwin(help_win);' \
      --replace-fail 'delwin(highscore_win);' "" \
      --replace-fail 'del_panel(highscore_panel);' $'del_panel(highscore_panel);\n\tdelwin(highscore_win);'
  '';

  dontConfigure = true;
  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" "STRIP=true" "SDL=0" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 cr $out/libexec/cryptrover/cryptrover
    install -Dm644 -t $out/share/doc/cryptrover README COPYING
    # mdport.c is separately BSD-3-Clause licensed.
    sed -n '/Copyright (C) 2005/,/\*\//p' src/mdport.c \
      > $out/share/doc/cryptrover/BSD-3-Clause.txt

    # The game writes scores.dat to the working directory.
    mkdir -p $out/bin
    cat > $out/bin/cryptrover <<EOF
    #!${runtimeShell}
    set -eu
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/cryptrover"
    ${coreutils}/bin/mkdir -p "\$state"
    cd "\$state"
    exec $out/libexec/cryptrover/cryptrover "\$@"
    EOF
    chmod 555 $out/bin/cryptrover
    runHook postInstall
  '';

  meta = {
    description = "Terminal dungeon survival game with a limited air supply";
    longDescription = ''
      CryptRover is a terminal game in which an archaeologist must survive
      twelve crypt levels before the air runs out.  This package builds the
      no-sound ncurses version from source and keeps the score table under
      $XDG_STATE_HOME/cryptrover, falling back to ~/.local/state/cryptrover.
    '';
    homepage = "https://code.google.com/archive/p/cryptrover/";
    license = with lib.licenses; [ gpl3Plus bsd3 ];
    platforms = lib.platforms.linux;
    mainProgram = "cryptrover";
  };
})
