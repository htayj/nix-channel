{ lib, stdenv, fetchurl, cmake, bison, flex, ncurses, zlib, coreutils
, runtimeShell, spdx-license-list-data }:

let
  rev = "25aaf2ab6a27a9104864d22337d7117c7d261571";
in
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

    # The complete source as built, installed beside the binary below.
    cp -r --preserve=mode . $NIX_BUILD_TOP/corresponding-source
  '';

  nativeBuildInputs = [ cmake bison flex ];
  buildInputs = [ ncurses zlib ];

  # The generated parsers, headers and nhdat form one serial build graph.
  enableParallelBuilding = false;

  # The launcher already has an absolute interpreter; patching would
  # rewrite scripts in the installed corresponding source.
  dontPatchShebangs = true;

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
      dist/debian/copyright doc/changelog.txt doc/save-recovery.md
    # mtrand.c (MT19937) is under the GNU Library GPL version 2 or later.
    install -Dm644 ${spdx-license-list-data.text}/text/LGPL-2.0-or-later.txt $doc/LGPL-2.0
    cd - >/dev/null

    # Complete corresponding source, as required by the NetHack General
    # Public License and the GNU Library GPL.
    cp -r --preserve=mode $NIX_BUILD_TOP/corresponding-source $doc/source
    install -Dm644 ${./default.nix} $doc/default.nix
    cat > $doc/SOURCE-NOTICE <<'EOF'
    DynaHack ${finalAttrs.version}: complete corresponding source

    The directory source/ holds the complete source code from which this
    package's programs and data were built, exactly as compiled.

    Upstream: https://github.com/tung/DynaHack, tag v${finalAttrs.version},
    commit ${rev}.
    Archive: ${finalAttrs.src.url}
    Archive hash: ${finalAttrs.src.outputHash}
      (nix-base32 sha256 ${builtins.convertHash { hash = finalAttrs.src.outputHash; toHashFormat = "nix32"; }})

    Changes from the upstream archive, made 2026-11-10 by the tay Nix
    channel. Each modified file carries a dated notice on its first line.
      libnitrohack/util/makedefs.c: fixed build date (2016-02-17) instead of
        the build clock, for reproducible output.
      nitrohack/include/nhcurses.h: wide curses header included as curses.h.
      nitrohack/src/dialog.c: dialog text printed with a %s format.
    Removed from the archive:
      doc/tmac.n: its terms forbid modified or sold redistribution; the
        build does not use it.
      nitrohack/rc: Windows resources whose icon has no separate grant;
        the build does not use them.
    No other file differs from the archive.

    The Nix build expression is default.nix in this directory. To rebuild
    without Nix, configure source/ with CMake 3.5 or later, a C compiler,
    bison, flex, ncurses (wide-character, header as curses.h) and zlib:

      cd source
      CFLAGS=-std=gnu99 cmake -B build \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DENABLE_NETCLIENT=OFF \
        -DENABLE_SERVER=OFF -DUSE_PDCURSES=OFF \
        -DBINDIR=PREFIX/libexec/dynahack -DLIBDIR=PREFIX/lib/dynahack \
        -DDATADIR=PREFIX/share/dynahack \
        -DSHELLDIR=PREFIX/share/dynahack/upstream-launcher
      make -C build -j1 install

    Replace PREFIX with the installation prefix. The build is serial
    because generated parsers, headers and nhdat depend on each other.
    The Nix package replaces upstream's launcher with bin/dynahack, which
    runs libexec/dynahack/dynahack with -H, -U and -V directories.
    EOF
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/dynahack/dynahack
    test -s $out/share/dynahack/nhdat
    doc=$out/share/doc/dynahack
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $doc/license
    grep -qF 'GNU LIBRARY GENERAL PUBLIC LICENSE' $doc/LGPL-2.0
    grep -qF '${rev}' $doc/SOURCE-NOTICE
    test -s $doc/default.nix

    # The installed source must equal the upstream archive apart from the
    # three modified files and two removals listed in SOURCE-NOTICE.
    pristine=$(mktemp -d)
    tar -xzf $src -C $pristine
    diff -rq $pristine/* $doc/source | sed "s|$pristine/[^/]*|A|; s|$doc/source|B|" > differences || true
    cat > expected <<'EOF'
    Files A/libnitrohack/util/makedefs.c and B/libnitrohack/util/makedefs.c differ
    Only in A/doc: tmac.n
    Only in A/nitrohack: rc
    Files A/nitrohack/include/nhcurses.h and B/nitrohack/include/nhcurses.h differ
    Files A/nitrohack/src/dialog.c and B/nitrohack/src/dialog.c differ
    EOF
    sort differences | diff -u <(sort expected) -
    for f in libnitrohack/util/makedefs.c nitrohack/include/nhcurses.h nitrohack/src/dialog.c; do
      head -n1 $doc/source/$f | grep -q '^/\* Modified 2026-11-10 by the tay Nix channel'
    done
    rm -r $pristine
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
