{
  lib,
  stdenv,
  fetchurl,
  bison,
  flex,
  groff,
  util-linux,
  coreutils,
  gzip,
  mailutils,
  ncurses,
  runtimeShell,
  runtimeShellPackage,
}:

let
  commit = "10c2529b38ee457e8d015f8e1561039ab4d4bf2e";
  # The native Unix port reads environment values only up to BUFSZ / 2
  # bytes (nh_getenv in src/options.c), so a longer playground is ignored.
  playgroundLimit = 128;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "gnollhack";
  version = "4.3.0-27";

  src = fetchurl {
    name = "gnollhack-${finalAttrs.version}.tar.gz";
    url = "https://codeload.github.com/hyvanmielenpelit/GnollHack/tar.gz/${commit}";
    hash = "sha256-GAxWVyDOMzcCCSNQ9xYdXZkaZdeujSR/4YujTj+P8xo=";
  };

  # The Windows, Android and prebuilt trees carry the proprietary FMOD SDK,
  # prebuilt files and CC BY-NC artwork.  The Unix tty/curses port uses none
  # of them.
  prePatch = ''
    rm -r win/win32 sys/android binary
    rm sys/wince/gnollhack64x96.bmp
  '';

  patches = [ ./immutable-data.patch ];

  postPatch = ''
    # NGPL 2(a): every modified file carries a dated notice.
    notice() {
      { printf '%s Modified by tay Nix channel, 2026-11-11: %s%s\n' "$3" "$2" "$4"
        cat "$1"; } > "$1.new"
      mv "$1.new" "$1"
    }

    notice include/config.h "enable upstream reproducible builds and file prefixes." '/*' ' */'
    substituteInPlace include/config.h --replace-fail '/* #define REPRODUCIBLE_BUILD */' \
      '#define REPRODUCIBLE_BUILD
    #define NOCWD_ASSUMPTIONS'

    notice include/unixconf.h "qualify the default mail reader in the Nix closure." '/*' ' */'
    substituteInPlace include/unixconf.h \
      --replace-fail '"/bin/mail"' '"${mailutils}/bin/mail"'

    notice sys/unix/unixunix.c "qualify the fallback shell in the Nix closure." '/*' ' */'
    substituteInPlace sys/unix/unixunix.c \
      --replace-fail '"/bin/sh"' '"${runtimeShellPackage}/bin/sh"'

    notice sys/unix/hints/linux "use GNU C11 with optimisation, PIE, immutable data, unprivileged execution and store gzip." '#' ""
    substituteInPlace sys/unix/hints/linux \
      --replace-fail 'CFLAGS=-g -O ' 'CFLAGS=-g -O2 -std=gnu11 ' \
      --replace-fail '/bin/gzip' '${gzip}/bin/gzip' \
      --replace-fail ' -DSECURE' "" \
      --replace-fail 'LFLAGS=-rdynamic -no-pie' 'LFLAGS=-rdynamic'

    notice sys/unix/setup.sh "use the build shell." '#' ""
    substituteInPlace sys/unix/setup.sh --replace-fail '/bin/sh ' '${runtimeShell} '

    notice sys/unix/sysconf "keep native dumps private and avoid host diagnostic tools." '#' ""
    substituteInPlace sys/unix/sysconf \
      --replace-fail '=/tmp/gnollhack.' '=dumps/gnollhack.' \
      --replace-fail 'GDBPATH=' '#GDBPATH=' \
      --replace-fail 'GREPPATH=' '#GREPPATH=' \
      --replace-fail 'PANICTRACE_GDB=1' 'PANICTRACE_GDB=0'

    # No repository probe: version metadata identifies this archive.
    printf 'githash=%s\ngitbranch=%s\n' ${commit} ${finalAttrs.version} > dat/gitinfo.txt
  '';

  configurePhase = ''
    runHook preConfigure
    sh sys/unix/setup.sh sys/unix/hints/linux
    # NGPL 3(a): ship the complete corresponding native source, including the
    # dated changes above, with the binaries.
    mkdir native-source
    for d in src include util dat doc sys/unix sys/share win/tty win/curses win/share; do
      mkdir -p "native-source/$(dirname $d)"
      cp -r $d "native-source/$d"
    done
    cp LICENSE.md README.md Makefile native-source/
    runHook postConfigure
  '';

  nativeBuildInputs = [ bison flex groff util-linux ];
  buildInputs = [ ncurses ];

  # Generated headers, utilities and levels share undeclared dependencies.
  enableParallelBuilding = false;

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "SHELL=${runtimeShell}"
    "PREFIX=$(out)"
    "HACKDIR=$(out)/share/gnollhack"
    "WINTTYLIB=-lncursesw"
    "WINCURSESLIB=-lncursesw"
    "LEX=flex"
    "GITINFO=0"
  ];
  preBuild = ''
    makeFlagsArray+=("YACC=bison -y")
  '';
  # all builds the engine, recover, Guidebook, levels, text data and nhdat.
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall
    data=$out/share/gnollhack doc=$out/share/doc/gnollhack
    install -Dm555 src/gnollhack $out/libexec/gnollhack
    install -Dm555 util/recover $out/libexec/gnollhack-recover
    install -Dm444 dat/nhdat dat/license dat/symbols sys/unix/sysconf -t $data
    install -Dm444 LICENSE.md README.md dat/license dat/credits doc/Guidebook -t $doc
    cp -r native-source $doc/native-source
    install -Dm444 doc/nethack.6 $out/share/man/man6/gnollhack.6
    install -Dm444 doc/recover.6 $out/share/man/man6/gnollhack-recover.6

    mkdir -p $out/bin
    for program in gnollhack gnollhack-recover; do
      cat > $out/bin/$program <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    case \''${XDG_DATA_HOME-} in
      /*) base=\$XDG_DATA_HOME ;;
      *) case \''${HOME-} in
           /*) base=\$HOME/.local/share ;;
           *) echo 'gnollhack: an absolute HOME or XDG_DATA_HOME is required' >&2; exit 1 ;;
         esac ;;
    esac
    state=\$(${coreutils}/bin/realpath -m -- "\$base/gnollhack")
    case \$state in
      ${builtins.storeDir}|${builtins.storeDir}/*)
        echo 'gnollhack: state must be outside the store' >&2; exit 1 ;;
    esac
    if [ "\$(LC_ALL=C ${coreutils}/bin/printf '%s' "\$state" | ${coreutils}/bin/wc -c)" -gt ${toString playgroundLimit} ]; then
      echo 'gnollhack: playground path exceeds the native ${toString playgroundLimit}-byte limit' >&2; exit 1
    fi
    ${coreutils}/bin/mkdir -p -- "\$state/save" "\$state/dumps"
    for file in perm record logfile livelog xlogfile wishtracker paniclog; do
      test -e "\$state/\$file" || : > "\$state/\$file"
    done
    export GNOLLHACKDIR="\$state" NetHackDIR="\$state"
    export TERMINFO_DIRS=${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}
    exec $out/libexec/$program "\$@"
    EOF
      chmod 555 $out/bin/$program
    done
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ util-linux ];
  installCheckPhase = ''
    runHook preInstallCheck
    bash ${./smoke.sh} $out
    runHook postInstallCheck
  '';

  meta = {
    description = "NetHack variant with expanded dungeons and character development (tty/curses)";
    longDescription = ''
      GnollHack extends NetHack with new classes, monsters, items, spells,
      levels and character development.  This package provides the upstream
      native Unix terminal port with tty and curses interfaces, generated text
      and maps, native saves and the recovery utility.  Immutable data stays
      in the store; saves, bones, scores, logs and dumps use
      $XDG_DATA_HOME/gnollhack.  The graphical and audio clients are not
      included.
    '';
    homepage = "https://github.com/hyvanmielenpelit/GnollHack";
    license = lib.licenses.ngpl;
    mainProgram = "gnollhack";
    platforms = [ "x86_64-linux" ];
  };
})
