{ lib, stdenv, fetchurl, runtimeShell, coreutils, ncurses }:

stdenv.mkDerivation (finalAttrs: {
  pname = "hack";
  version = "1.0.3";

  src = fetchurl {
    url = "https://homepages.cwi.nl/~aeb/games/hack/hack-${finalAttrs.version}.tar.gz";
    hash = "sha256-aIU053as/mIOqeJIIr6osLS76OwsLzx0yNuJtRx7zDA=";
  };

  buildInputs = [ ncurses ];

  postPatch = ''
    # Linux provides termio rather than the BSD sgtty interface.  Mail
    # checking and the shell escape are disabled, and the data directory is
    # supplied at run time with -d.
    sed -i \
      -e 's|^#define BSD.*$|/* #define BSD */|' \
      -e 's|^#define[[:space:]]*MAIL\b.*$|/* #define MAIL */|' \
      -e 's|^#define[[:space:]]*SHELL.*$|/* #define SHELL */|' \
      -e 's|^#define[[:space:]]*HACKDIR.*$|/* #define HACKDIR */|' \
      config.h
    ! grep -E '^#define[[:space:]]*(BSD|MAIL|SHELL|HACKDIR)\b' config.h

    # Current GCC rejects an implicit external declaration followed by a
    # file-local K&R definition; declare those helpers before their callers.
    substituteInPlace hack.apply.c \
      --replace-fail 'extern struct monst *bchit();' 'static struct monst *bchit();' \
      --replace-fail 'extern char pl_character[];' 'extern char pl_character[];

    static use_camera(), in_ice_box(), ck_ice_box(), out_ice_box(),
           use_ice_box(), use_whistle(), use_magic_whistle(), dig(),
           use_pick_axe();'
    substituteInPlace hack.do.c \
      --replace-fail 'extern char *nomovemsg;' 'extern char *nomovemsg;

    static drop();'
    substituteInPlace hack.invent.c \
      --replace-fail 'char *xprname();' 'static char *xprname();'
    substituteInPlace hack.read.c \
      --replace-fail '#include "hack.h"' '#include "hack.h"

    extern struct obj *some_armor();'
    # `inline' is a keyword in current C dialects.
    substituteInPlace hack.tty.c --replace-fail 'inline' 'input_line'
    substituteInPlace hack.shk.c \
      --replace-fail 'extern struct obj *o_on(), *bp_to_obj();' 'extern struct obj *o_on(), *bp_to_obj();

    static setpaid(), addupbill(), findshk(), pay(), dopayobj(), getprice(),
           realhunger();'
    sed -i 's|^#define[[:space:]]*EGD.*$|&\n\nstatic restfakecorr(), goldincorridor();|' hack.vault.c
    grep -q 'static restfakecorr' hack.vault.c
    # The historical sprintf declaration conflicts with stdio.h.
    substituteInPlace hack.h \
      --replace-fail 'extern char *sprintf();' 'extern int sprintf(char *, const char *, ...);'
    substituteInPlace hack.main.c \
      --replace-fail 'register char *sfoo;' 'register char *sfoo;
    		extern char genocided[], fut_geno[];' \
      --replace-fail 'int hangup();' 'int hangup();
    #ifdef CHDIR
    static chdirx();
    #endif'
    substituteInPlace hack.makemon.c \
      --replace-fail '{ extern boolean in_mklev;' 'extern boolean in_mklev;
    	{'
    sed -i '0,/^#ifndef QUEST/s//extern char *getenv();\n\n#ifndef QUEST/' hack.mkshop.c
    grep -q 'extern char \*getenv' hack.mkshop.c

    # glibc no longer provides <termio.h> or struct termio; use the POSIX
    # termios interface with the same System V flag layout.
    substituteInPlace hack.ioctl.c \
      --replace-fail '<termio.h>' '<termios.h>' \
      --replace-fail 'struct termio termio;' 'struct termios termio;' \
      --replace-fail 'ioctl(fileno(stdin), (int) TCGETA, &termio)' 'tcgetattr(fileno(stdin), &termio)' \
      --replace-fail 'ioctl(fileno(stdin), (int) TCSETA, &termio)' 'tcsetattr(fileno(stdin), TCSANOW, &termio)'
    substituteInPlace hack.tty.c \
      --replace-fail '<termio.h>' '<termios.h>' \
      --replace-fail '#define termstruct	termio' '#define termstruct	termios' \
      --replace-fail '(ioctl(0, TCGETA, x))' '(tcgetattr(0, x))' \
      --replace-fail '(ioctl(0, TCSETA, x))' '(tcsetattr(0, TCSANOW, x))'

    # Link through the compiler instead of ld with /lib/crt0.o, skip lint,
    # and regenerate hack.onames.h with the built makedefs.
    sed -i \
      -e 's|^\t@ld -X -o .*$|\t$(CC) $(LDFLAGS) -o $(GAME) $(HOBJ) $(TERMLIB)|' \
      -e 's|^all:.*$|all: $(GAME)|' \
      -e 's|cc -o makedefs makedefs\.c|$(CC) $(CFLAGS) -o makedefs makedefs.c|' \
      -e 's|^\tmakedefs > hack\.onames\.h|\t./makedefs > hack.onames.h|' \
      -e 's|^CFLAGS = .*$|CFLAGS = -O2 -std=gnu89 -fcommon -D_DEFAULT_SOURCE|' \
      -e 's|^TERMLIB = .*$|TERMLIB = -lncurses|' \
      Makefile
    grep -q '$(CC) $(LDFLAGS) -o $(GAME)' Makefile
    grep -q './makedefs > hack.onames.h' Makefile
    rm hack.onames.h
  '';

  dontConfigure = true;
  # The historical makefile has incomplete dependencies for parallel builds.
  enableParallelBuilding = false;
  buildFlags = [ "hack" ];
  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];
  # hack.end.c formats score lines through Sprintf with data-derived but
  # internally generated format strings; keep upstream's K&R code intact.
  hardeningDisable = [ "format" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 hack $out/libexec/hack/hack
    install -Dm644 -t $out/share/hack data help hh rumors
    install -Dm644 -t $out/share/doc/hack READ_ME COPYRIGHT COPYRIGHT-JF
    install -Dm644 hack.6 $out/share/man/man6/hack.6

    # Hack writes levels, saves, the record and lock files in its play
    # directory; keep that in user state with read-only data links.
    mkdir -p $out/bin
    cat > $out/bin/hack <<EOF
    #!${runtimeShell}
    set -eu
    data=$out/share/hack
    state="\''${XDG_DATA_HOME:-\''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/hack"
    test ! -L "\$state" || { echo "hack: state directory is a symlink" >&2; exit 1; }
    ${coreutils}/bin/mkdir -p -- "\$state/save"
    for file in data help hh rumors; do
      path="\$state/\$file"
      if test -e "\$path" || test -L "\$path"; then
        test "\$(${coreutils}/bin/readlink -- "\$path")" = "\$data/\$file" ||
          { echo "hack: unexpected file \$path" >&2; exit 1; }
      else
        ${coreutils}/bin/ln -s "\$data/\$file" "\$path"
      fi
    done
    for file in perm record; do
      test ! -L "\$state/\$file" || { echo "hack: \$file is a symlink" >&2; exit 1; }
      test -e "\$state/\$file" || : > "\$state/\$file"
    done
    export HACKDIR="\$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/hack/hack -d "\$state" "\$@"
    EOF
    chmod 555 $out/bin/hack
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/hack/hack
    for f in data help hh rumors; do test -s $out/share/hack/$f; done
    test -s $out/share/doc/hack/COPYRIGHT
    test -s $out/share/doc/hack/COPYRIGHT-JF
    runHook postInstallCheck
  '';

  meta = {
    description = "Original 1985 Hack dungeon game, ancestor of NetHack";
    longDescription = ''
      Hack 1.0.3 is the classic terminal roguelike by Jay Fenlason and Andries
      Brouwer.  The launcher keeps levels, saves, the score record and lock
      files in $XDG_DATA_HOME/hack, falling back to ~/.local/share/hack.
    '';
    homepage = "https://homepages.cwi.nl/~aeb/games/hack/";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hack";
  };
})
