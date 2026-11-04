{ lib, stdenv, fetchFromGitHub, runtimeShell, coreutils, bison, flex, pkg-config, ncurses }:

stdenv.mkDerivation {
  pname = "dnethack";
  version = "3.26.0";

  src = fetchFromGitHub {
    owner = "Chris-plus-alphanumericgibberish";
    repo = "dNAO";
    rev = "a6f0a1c43e66f4fb1bcac34d7d9709706682ec19";
    hash = "sha256-cjPQD+hRsMuGgpn6hfuQzo886pb+YGKWtdVP9xn4U1E=";
  };

  nativeBuildInputs = [ bison flex pkg-config ];
  buildInputs = [ ncurses ];

  postPatch = ''
    # No .git in the source; pin the version metadata to the fixed revision.
    substituteInPlace GNUmakefile \
      --replace-fail 'export COMMIT_DESC := $(shell git describe --always)' \
                     'export COMMIT_DESC := a6f0a1c43e66f4fb1bcac34d7d9709706682ec19'

    # The server admin-message hook reads an ambient relative file; it is not
    # part of the standalone game.
    sed -i -E 's|^#define SERVER_ADMIN_MSG.*$|/* #define SERVER_ADMIN_MSG */|' include/config.h
    ! grep -qE '^#define SERVER_ADMIN_MSG' include/config.h

    # Upstream disables external COMPRESS (#if 0 in include/config.h), so no
    # compressor path needs patching.
    # makedefs embeds the build clock; use the pinned commit time.
    substituteInPlace util/makedefs.c \
      --replace-fail '(void) time((time_t *)&clocktim);' 'clocktim = 1779991412L;'
  '';

  dontConfigure = true;
  # Generated yacc/flex sources, maps and nhdat have ordering dependencies.
  enableParallelBuilding = false;
  # include/macromagic.h ships pregenerated; do not regenerate it.
  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" "PYTHON=false" ];
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall
    data=$out/share/dnethack
    doc=$out/share/doc/dnethack
    install -Dm755 src/dnethack $out/libexec/dnethack/dnethack
    install -Dm755 util/recover $out/libexec/dnethack/recover
    install -Dm644 -t $data dat/nhdat dat/license
    install -Dm644 -t $doc README README.gray README.menucolor doc/Guidebook.txt \
      sys/unix/README.linux dat/license doc/fixes*

    mkdir -p $out/bin
    cat > $out/bin/dnethack <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    state="\''${XDG_DATA_HOME:-\''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/dnethack"
    ${coreutils}/bin/mkdir -p -- "\$state/save" "\$state/dumplog" "\$state/whereis"
    cd "\$state"
    for file in perm record logfile xlogfile livelog paniclog mailbox; do
      test -e "\$file" || : > "\$file"
    done
    ${coreutils}/bin/ln -sfn $data/nhdat nhdat
    ${coreutils}/bin/ln -sfn $data/license license
    export MAIL="\$state/mailbox"
    export HACKDIR="\$state" NETHACKDIR="\$state"
    export TERM="\''${TERM:-xterm-256color}"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/dnethack/dnethack "\$@"
    EOF
    chmod 555 $out/bin/dnethack
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s $out/share/dnethack/nhdat
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/dnethack/license
    grep -qF 'dNetHack is free software' $out/share/doc/dnethack/README
    ${runtimeShell} -n $out/bin/dnethack
    runHook postInstallCheck
  '';

  meta = {
    description = "NetHack variant with many new roles, races, monsters and branches";
    longDescription = ''
      dNetHack is a NetHack variant with a terminal interface and extensive new
      roles, races, monsters, items and dungeon branches. This package builds
      the Unix tty/curses game from a fixed dNAO revision. Game data stays in
      the store; saves, scores, dumplogs and locks live in the user's XDG data
      directory.
    '';
    homepage = "https://github.com/Chris-plus-alphanumericgibberish/dNAO";
    license = lib.licenses.ngpl;
    mainProgram = "dnethack";
    platforms = [ "x86_64-linux" ];
  };
}
