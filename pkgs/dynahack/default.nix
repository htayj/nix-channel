{ lib, stdenv, fetchurl, cmake, bison, flex, ncurses, zlib, coreutils
, runtimeShell, spdx-license-list-data }:

stdenv.mkDerivation (finalAttrs: {
  pname = "dynahack";
  version = "0.6.0";

  # Tag v0.6.0, commit 25aaf2ab6a27a9104864d22337d7117c7d261571.
  src = fetchurl {
    url = "https://codeload.github.com/tung/DynaHack/tar.gz/refs/tags/v${finalAttrs.version}";
    name = "dynahack-${finalAttrs.version}.tar.gz";
    hash = "sha256-Ym3mi1OCZab9CjVgeWNfnE4aN7pa2h4RxoGUoVAOmIA=";
  };

  # The NetHack General Public License requires modified files to carry
  # prominent notices stating the change and its date.
  postPatch = ''
    notice() {
      sed -i "1i /* Modified 2026-11-10 by the tay Nix channel: $2. See pkgs/dynahack/default.nix. */" "$1"
    }

    # makedefs embeds the build clock in date.h; use a fixed date (2016-02-17).
    substituteInPlace libnitrohack/util/makedefs.c \
      --replace-fail 'time(&clocktim);' 'clocktim = 1455667200L;'
    notice libnitrohack/util/makedefs.c "fixed build date for reproducible output"

    # nixpkgs installs the wide ncurses headers as include/curses.h.
    substituteInPlace nitrohack/include/nhcurses.h \
      --replace-fail '<ncursesw/curses.h>' '<curses.h>'
    notice nitrohack/include/nhcurses.h "wide curses header included as curses.h"

    # Pass the dialog lines as data, not as printf formats.
    substituteInPlace nitrohack/src/dialog.c \
      --replace-fail 'mvwprintw(win, i + 1, 2, output[i]);' 'mvwprintw(win, i + 1, 2, "%s", output[i]);'
    notice nitrohack/src/dialog.c "dialog text printed with a %s format"

    # Neither file is used by this build: tmac.n forbids modified or sold
    # redistribution, and the Windows icon has no separate asset grant.
    rm doc/tmac.n
    rm -r nitrohack/rc
  '';

  nativeBuildInputs = [ cmake bison flex ];
  buildInputs = [ ncurses zlib ];

  # The generated parsers, headers and nhdat form one serial build graph.
  enableParallelBuilding = false;

  env.NIX_CFLAGS_COMPILE = "-std=gnu99";

  cmakeFlags = [
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    # Local curses client only; no network client or PostgreSQL server.
    "-DENABLE_NETCLIENT=OFF"
    "-DENABLE_SERVER=OFF"
    "-DUSE_PDCURSES=OFF"
    "-DBINDIR=${placeholder "out"}/libexec/dynahack"
    "-DLIBDIR=${placeholder "out"}/lib/dynahack"
    "-DDATADIR=${placeholder "out"}/share/dynahack"
    # Upstream's generated launcher is replaced by the one below.
    "-DSHELLDIR=${placeholder "out"}/share/dynahack/upstream-launcher"
  ];

  # Configuration, saves and dumps go to a private per-user XDG config
  # directory; bones, scores and locks to a private XDG state directory.
  postInstall = ''
    rm -r $out/share/dynahack/upstream-launcher

    mkdir -p $out/bin
    cat > $out/bin/dynahack <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    userdir="\''${XDG_CONFIG_HOME:-\$HOME/.config}/DynaHack"
    vardir="\''${XDG_STATE_HOME:-\$HOME/.local/state}/dynahack"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    ${coreutils}/bin/mkdir -p -- "\$userdir" "\$vardir"
    exec $out/libexec/dynahack/dynahack -H $out/share/dynahack -U "\$userdir" -V "\$vardir" "\$@"
    EOF
    chmod 555 $out/bin/dynahack

    doc=$out/share/doc/dynahack
    cd ..
    install -Dm644 -t $doc README.md libnitrohack/dat/license \
      dist/debian/copyright doc/changelog.txt doc/save-recovery.md \
      libnitrohack/src/mtrand.c
    # mtrand.c (MT19937) is under the GNU Library GPL version 2 or later.
    install -Dm644 ${spdx-license-list-data.text}/text/LGPL-2.0-or-later.txt $doc/LGPL-2.0
    # Modified sources, as required by the NetHack General Public License.
    install -Dm644 -t $doc/modified-source/libnitrohack/util libnitrohack/util/makedefs.c
    install -Dm644 -t $doc/modified-source/nitrohack/include nitrohack/include/nhcurses.h
    install -Dm644 -t $doc/modified-source/nitrohack/src nitrohack/src/dialog.c
    cd - >/dev/null
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/dynahack/dynahack
    test -s $out/share/dynahack/nhdat
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/doc/dynahack/license
    grep -qF 'GNU LIBRARY GENERAL PUBLIC LICENSE' $out/share/doc/dynahack/LGPL-2.0
    runHook postInstallCheck
  '';

  meta = {
    description = "NetHack variant derived from NitroHack and UnNetHack";
    longDescription = ''
      DynaHack is a NetHack variant derived from NitroHack and UnNetHack. This
      package builds the final maintainer release's local curses client and
      dungeon data, without the optional network client or server.
      Configuration, saves, logs and dumps live in XDG_CONFIG_HOME/DynaHack;
      bones, scores and locks live in XDG_STATE_HOME/dynahack.
    '';
    homepage = "https://github.com/tung/DynaHack";
    license = with lib.licenses; [ ngpl lgpl2Plus ];
    mainProgram = "dynahack";
    platforms = [ "x86_64-linux" ];
  };
})
