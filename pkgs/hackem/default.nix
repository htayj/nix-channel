{ lib, stdenv, fetchFromGitHub, runtimeShell, coreutils, gzip, bison, flex, groff, util-linux, ncurses }:

stdenv.mkDerivation {
  pname = "hackem";
  version = "1.2.2";

  src = fetchFromGitHub {
    owner = "elunna";
    repo = "hackem";
    rev = "6e99cffbeecd2cbf71b3d27b9285be345aca298b";
    hash = "sha256-Th2L2ZCqQWBAsRFrMM7V2BIAs+jbLkxW31MXngv+oPQ=";
  };

  nativeBuildInputs = [ bison flex groff util-linux ];
  buildInputs = [ ncurses ];

  postPatch = ''
    # NGPL 2(a): identify every file changed by this build.
    for f in include/config.h include/unixconf.h include/extern.h; do
      { printf '/* Modified by the tay Nix channel: store data, XDG state paths,\n'
        printf ' * reproducible data generation.  See pkgs/hackem/default.nix. */\n'
        cat "$f"; } > "$f.new"
      mv "$f.new" "$f"
    done

    # Immutable data in the store; saves, scores and dumps in the launcher's
    # private state directory; no global sysconf file.
    substituteInPlace include/config.h \
      --replace-fail '#define SYSCF                /* use a global configuration */' '/* #define SYSCF */' \
      --replace-fail '#define SYSCF_FILE "sysconf" /* global configuration is in a file */' '/* #define SYSCF_FILE */' \
      --replace-fail '#define HACKDIR "/usr/games/lib/hackemdir"' "#define HACKDIR \"$out/share/hackem\"" \
      --replace-fail '#define COMPRESS "/usr/bin/compress" /* Lempel-Ziv compression */' '#define COMPRESS "${gzip}/bin/gzip"' \
      --replace-fail '#define COMPRESS_EXTENSION ".Z"      /* compress'"'"'s extension */' '#define COMPRESS_EXTENSION ".gz"' \
      --replace-fail '/* #define DUMPLOG */' '#define DUMPLOG' \
      --replace-fail '#define DUMPLOG_FILE        "/tmp/hackem.%n.%d.log"' '#define DUMPLOG_FILE nh_getenv("HACKEM_DUMPLOG_FILE")
    #define DUMPLOG_URL nh_getenv("HACKEM_DUMPLOG_URL")'

    substituteInPlace include/unixconf.h \
      --replace-fail '#define SERVER_ADMIN_MSG "adminmsg"' '/* #define SERVER_ADMIN_MSG */' \
      --replace-fail '/* #define VAR_PLAYGROUND "/var/lib/games/nethack" */' '#define VAR_PLAYGROUND nh_getenv("HACKEM_VAR_PLAYGROUND")'

    # The Unix append_slash is declared only for PC ports upstream.
    substituteInPlace include/extern.h \
      --replace-fail '/* ### files.c ### */' 'E void FDECL(append_slash, (char *));

    /* ### files.c ### */'

    # groff reads the tab and inline comment as part of the .so filename.
    sed -i -E 's|^\.so tmac\.nh[[:blank:]]+.*$|.so tmac.nh|' doc/Guidebook.mn
    grep -qx '.so tmac.nh' doc/Guidebook.mn

    substituteInPlace sys/unix/setup.sh --replace-fail /bin/sh ${runtimeShell}
    ${runtimeShell} sys/unix/setup.sh sys/unix/hints/linux
  '';

  dontConfigure = true;
  enableParallelBuilding = false;

  preBuild = ''
    # makedefs embeds this date when REPRODUCIBLE_BUILD is enabled.
    export SOURCE_DATE_EPOCH=1698401163 TZ=UTC0
    makeFlagsArray+=(
      "CC=$CC"
      "LINK=$CC"
      "CFLAGS=-O2 -std=gnu99 -fcommon -D_DEFAULT_SOURCE -I../include -DNOTPARMDECL -DCURSES_GRAPHICS -DDLB -DREPRODUCIBLE_BUILD -DNOMAIL -DNOSHELL -DNOUSER_SOUNDS -DFCMASK=0644"
      "WINLIB=-lncurses"
      "LEX=flex"
      "YACC=bison -y"
      "GITINFO=0"
    )
  '';
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall
    data=$out/share/hackem
    doc=$out/share/doc/hackem
    install -Dm755 src/hackem $out/libexec/hackem/hackem
    # symbols is read outside the dlb archive by the tty symset loader.
    install -Dm644 -t $data dat/nhdat dat/license dat/symbols
    install -Dm644 -t $doc LICENSE README.md doc/Guidebook.txt \
      doc/hackem_changelog.txt sys/unix/README.linux src/isaac64.c
    install -Dm644 doc/nethack.6 $out/share/man/man6/hackem.6

    mkdir -p $out/bin
    cat > $out/bin/hackem <<EOF
    #!${runtimeShell}
    set -eu
    home="\''${HOME:?HOME must be set}"
    state="\''${XDG_STATE_HOME:-\''${XDG_DATA_HOME:-\$home/.local/state}}/hackem"
    config="\''${XDG_CONFIG_HOME:-\$home/.config}/hackem"
    ${coreutils}/bin/mkdir -p -- "\$state/save" "\$state/whereis" "\$config"
    for file in perm record logfile xlogfile livelog paniclog hangup; do
      test -e "\$state/\$file" || : > "\$state/\$file"
    done
    export HOME="\$config"
    export HACKDIR=$data NETHACKDIR=$data
    export HACKEM_VAR_PLAYGROUND="\$state/"
    export HACKEM_DUMPLOG_FILE="\$state/hackem.%n.%d.log"
    export HACKEM_DUMPLOG_URL="file://\$HACKEM_DUMPLOG_FILE"
    export TERM="\''${TERM:-xterm-256color}"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/hackem/hackem "\$@"
    EOF
    chmod 555 $out/bin/hackem
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s $out/share/hackem/nhdat
    test -s $out/share/hackem/symbols
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/hackem/license
    grep -qF "Hack'EM" $out/share/doc/hackem/README.md
    test -s $out/share/doc/hackem/Guidebook.txt
    test ! -e $out/share/hackem/sounds
    grep -qF '${gzip}/bin/gzip' $out/libexec/hackem/hackem
    grep -qF "$out/share/hackem" $out/libexec/hackem/hackem
    ${runtimeShell} -n $out/bin/hackem
    runHook postInstallCheck
  '';

  meta = {
    description = "EvilHack-based NetHack variant with features from many other variants";
    longDescription = ''
      Hack'EM is a NetHack variant built on EvilHack. This package builds the
      tty and curses interfaces from a fixed upstream revision with offline
      data generation. Game data stays in the store; saves, scores, locks and
      dump logs live in the user's XDG state directory.
    '';
    homepage = "https://github.com/elunna/hackem";
    license = [ lib.licenses.ngpl lib.licenses.cc0 ];
    mainProgram = "hackem";
    platforms = [ "x86_64-linux" ];
  };
}
