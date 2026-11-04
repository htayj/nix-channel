{ lib, stdenv, fetchFromGitHub, runtimeShell, coreutils, bison, flex, groff, util-linux, ncurses }:

stdenv.mkDerivation {
  pname = "grunthack";
  version = "0.2.4-unstable-2018-09-17";

  src = fetchFromGitHub {
    owner = "NHTangles";
    repo = "GruntHack";
    rev = "51d75eebbcf8ab0ce31ddab9581d266db0a691c5";
    hash = "sha256-tbw5ZIC4QcSiH8e+U69HwbawN0hyk6N9bZOmq0SgUSg=";
  };

  nativeBuildInputs = [ bison flex groff util-linux ];
  buildInputs = [ ncurses ];

  postPatch = ''
    # The Macintosh instrument samples carry no redistribution grant and are
    # unused by the tty port; keep only their README notice.
    rm sys/share/sounds/*.uu

    # NGPL 2(a): identify every file changed by this build.
    for f in include/unixconf.h include/extern.h include/config.h \
             sys/unix/unixmain.c util/makedefs.c; do
      { printf '/* Modified by the tay Nix channel: native tty build, XDG paths,\n'
        printf ' * reproducible data generation.  See pkgs/grunthack/default.nix. */\n'
        cat "$f"; } > "$f.new"
      mv "$f.new" "$f"
    done

    sh sys/unix/setup.sh

    # Take the writable playground from the launcher instead of a system path.
    sed -i -E \
      -e 's|^#define VAR_PLAYGROUND[ \t]+.*$|#define VAR_PLAYGROUND nh_getenv("GRUNTHACK_VAR_PLAYGROUND")|' \
      -e 's|^#define MAIL[ \t]+.*$|/* #define MAIL */|' \
      include/unixconf.h
    grep -q 'nh_getenv("GRUNTHACK_VAR_PLAYGROUND")' include/unixconf.h
    ! grep -qE '^#define MAIL\b' include/unixconf.h

    substituteInPlace include/extern.h \
      --replace-fail 'E void NDECL(server_admin_msg);' 'E void NDECL(server_admin_msg);
    E void NDECL(ck_server_admin_msg);'

    substituteInPlace include/config.h \
      --replace-fail '#define COMPRESS "/bin/gzip"' '/* #define COMPRESS */' \
      --replace-fail '#define COMPRESS_EXTENSION ".gz"' '/* #define COMPRESS_EXTENSION */'
    sed -i -E \
      -e 's|^#define DUMP_FN[ \t]+.*$|#define DUMP_FN ""|' \
      -e 's|^#define SERVER_ADMIN_MSG[ \t]+.*$|/* #define SERVER_ADMIN_MSG */|' \
      include/config.h
    grep -q '^#define DUMP_FN ""$' include/config.h
    ! grep -qE '^#define SERVER_ADMIN_MSG\b' include/config.h

    # An explicit HACKDIR would otherwise keep scores and saves in the store.
    sed -i -E 's|if \(dir[[:space:]]*/\* User specified directory|if (dir \&\& !VAR_PLAYGROUND /* User specified directory|' \
      sys/unix/unixmain.c
    grep -q 'dir && !VAR_PLAYGROUND' sys/unix/unixmain.c

    # makedefs embeds the build clock; use the pinned commit date.
    substituteInPlace util/makedefs.c \
      --replace-fail '(void) time(&clocktim);' 'clocktim = 1537142400L;'
  '';

  dontConfigure = true;
  enableParallelBuilding = false;
  # Upstream makedefs passes its constant banner strings as printf formats.
  hardeningDisable = [ "format" ];

  preBuild = ''
    makeFlagsArray+=(
      "CC=$CC"
      "CFLAGS=-O2 -std=gnu89 -fcommon -I../include -D_DEFAULT_SOURCE -DTEXTCOLOR"
      "LEX=flex"
      "YACC=bison -y"
      "WINTTYLIB=-lncurses"
      "WINCURSESLIB=-lncurses"
      "VCS_DESCRIPTION=git 51d75ee"
    )
  '';
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall
    data=$out/share/grunthack
    doc=$out/share/doc/grunthack
    install -Dm755 src/grunthack $out/libexec/grunthack/grunthack
    install -Dm644 -t $data dat/ghdat dat/license
    install -Dm644 -t $doc README README-curses.txt doc/Guidebook.txt \
      doc/changes01.0 doc/changes01.1 doc/changes02.0 doc/changes02.1 \
      sys/unix/README.linux dat/license
    install -Dm644 sys/share/sounds/README $doc/sounds-README

    mkdir -p $out/bin
    cat > $out/bin/grunthack <<EOF
    #!${runtimeShell}
    set -eu
    state="\''${XDG_DATA_HOME:-\''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/grunthack"
    ${coreutils}/bin/mkdir -p -- "\$state/save" "\$state/whereis"
    for file in perm record logfile xlogfile livelog; do
      test -e "\$state/\$file" || : > "\$state/\$file"
    done
    export HACKDIR=$data NETHACKDIR=$data
    export GRUNTHACK_VAR_PLAYGROUND="\$state/"
    export TERM="\''${TERM:-xterm-256color}"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/grunthack/grunthack "\$@"
    EOF
    chmod 555 $out/bin/grunthack
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s $out/share/grunthack/ghdat
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/grunthack/license
    grep -qF 'GruntHack is a derivative of NetHack' $out/share/doc/grunthack/README
    test -s $out/share/doc/grunthack/Guidebook.txt
    ! ls $out/share/grunthack | grep -q '\.uu$'
    ${runtimeShell} -n $out/bin/grunthack
    runHook postInstallCheck
  '';

  meta = {
    description = "Historical NetHack derivative with expanded monsters, items and levels";
    longDescription = ''
      GruntHack is a NetHack derivative. This package builds the tty port
      from a fixed upstream revision with offline data generation. Game data
      stays in the store; saves, scores and locks live in the user's XDG data
      directory.
    '';
    homepage = "https://github.com/NHTangles/GruntHack";
    license = lib.licenses.ngpl;
    mainProgram = "grunthack";
    platforms = [ "x86_64-linux" ];
  };
}
