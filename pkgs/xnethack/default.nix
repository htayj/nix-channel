{ lib, stdenv, fetchFromGitHub, runtimeShell, coreutils, gnugrep, gzip, groff, pkg-config, lua5_4, ncurses }:

stdenv.mkDerivation {
  pname = "xnethack";
  version = "10.0";

  # Tag xnh10.0. The Lua and PDCurses submodules are unused: Lua comes from
  # Nixpkgs and only the tty interface is built.
  src = fetchFromGitHub {
    owner = "copperwater";
    repo = "xNetHack";
    rev = "6eef39403f16f65e13f5d57242ee8d036307687a";
    hash = "sha256-Jvq8LE7PVq2jNvtbEaMFDO5GtB48/jNHlqsK24dVQSA=";
  };

  # The linux.500 hints probe nroff while parsing the makefiles.
  nativeBuildInputs = [ groff pkg-config ];
  buildInputs = [ lua5_4 ncurses ];

  postPatch = ''
    # NGPL 2(a): identify every source file changed by this build.
    for f in include/config.h include/unixconf.h src/windows.c; do
      { printf '/* Modified by the tay Nix channel: reproducible build, XDG state\n'
        printf ' * paths, optional dump logs.  See pkgs/xnethack/default.nix. */\n'
        cat "$f"; } > "$f.new"
      mv "$f.new" "$f"
    done

    substituteInPlace include/config.h \
      --replace-fail '/* #define REPRODUCIBLE_BUILD */' '#define REPRODUCIBLE_BUILD'

    # Static data stays in the store; the launcher supplies the writable
    # per-user playground at run time.
    sed -i -E \
      -e 's|^#define SERVER_ADMIN_MSG[[:space:]]+.*$|/* #define SERVER_ADMIN_MSG */|' \
      -e 's|^/[*/][[:space:]]+#define VAR_PLAYGROUND.*$|#define VAR_PLAYGROUND nh_getenv("XNETHACK_VAR_PLAYGROUND")|' \
      include/unixconf.h
    grep -q 'nh_getenv("XNETHACK_VAR_PLAYGROUND")' include/unixconf.h
    ! grep -qE '^#define SERVER_ADMIN_MSG[[:space:]]' include/unixconf.h

    substituteInPlace sys/unix/hints/linux.500 --replace-fail /bin/gzip ${gzip}/bin/gzip
    sed -i -E 's/^(GIT_HASH|GIT_BRANCH|GIT_PREFIX) := .*$/\1 :=/' sys/unix/hints/linux.500

    # The Guidebook is installed from the shipped plain-text copy.
    substituteInPlace sys/unix/Makefile.top --replace-fail 'recover Guidebook' 'recover'

    printf 'githash=%s\ngitbranch=xnh10.0\n' 6eef39403f16f65e13f5d57242ee8d036307687a > dat/gitinfo.txt

    # dump_fmtstr() is declared NONNULLPTRS, so its own NULL test is
    # optimized away; with DUMPLOGFILE unset in sysconf (below),
    # dump_open_log() would crash at every game end.
    sed -i -E 's|fname = dump_fmtstr\((DUMPLOG_FILE\|DUMPHTML_FILE), buf, TRUE\);|fname = \1 ? dump_fmtstr(\1, buf, TRUE) : (char *) 0;|' \
      src/windows.c
    test "$(grep -c 'FILE ? dump_fmtstr(' src/windows.c)" = 2

    # Keep game-end dumps out of the shared /tmp and host tool paths out of
    # the store-resident system configuration.
    sed -i -E \
      -e 's|^DUMPLOGFILE=|#DUMPLOGFILE=|' \
      -e 's|^DUMPHTMLFILE=|#DUMPHTMLFILE=|' \
      -e 's|^GDBPATH=|#GDBPATH=|' \
      -e 's|^GREPPATH=.*$|GREPPATH=${gnugrep}/bin/grep|' \
      -e 's|^PANICTRACE_GDB=1|PANICTRACE_GDB=0|' \
      sys/unix/sysconf

    substituteInPlace sys/unix/setup.sh --replace-fail /bin/sh ${runtimeShell}
    ${runtimeShell} sys/unix/setup.sh sys/unix/hints/linux.500
  '';

  dontConfigure = true;
  # makedefs, the Lua library copy and dlb have ordering dependencies which the
  # upstream makefiles do not express completely.
  enableParallelBuilding = false;

  preBuild = ''
    # makedefs uses this value when REPRODUCIBLE_BUILD is enabled.
    export SOURCE_DATE_EPOCH=1779840932 TZ=UTC0
    makeFlagsArray+=(
      "CC=$CC"
      "CCFLAGS=-O2 -g"
      "PREFIX=$out"
      "HACKDIR=$out/share/xnethack"
      "LUATOP=${lua5_4}/lib"
      "LUAHEADERS=${lua5_4}/include"
      "LUAHPREFIX="
      "NOCRASHREPORT=1"
      "NO_NHUUID=1"
      "GITINFO=0"
    )
  '';
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall
    data=$out/share/xnethack
    doc=$out/share/doc/xnethack
    install -Dm755 src/xnethack $out/libexec/xnethack/xnethack
    install -Dm755 util/recover $out/libexec/xnethack/xnethack-recover
    install -Dm644 -t $data dat/nhdat dat/license dat/symbols dat/NHdump.css sys/unix/sysconf
    install -Dm644 -t $doc LICENSE README README.md doc/Guidebook.txt doc/xnh-changelog-10.0.md
    # Lua is linked statically; ship its MIT notice.
    sed -n '/^\* Copyright (C) 1994-[0-9]* Lua\.org/,/^\*\*\*\*\*/p' \
      ${lua5_4}/include/lua.h > $doc/lua-COPYRIGHT
    grep -qF 'Permission is hereby granted' $doc/lua-COPYRIGHT
    install -Dm644 doc/xnethack.6 $out/share/man/man6/xnethack.6
    install -Dm644 doc/recover.6 $out/share/man/man6/xnethack-recover.6

    mkdir -p $out/bin
    cat > $out/bin/xnethack <<EOF
    #!${runtimeShell}
    set -eu
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME must be set}/.local/state}/xnethack"
    XNETHACK_VAR_PLAYGROUND="\$state/"
    # nh_getenv() rejects values over 128 bytes; count bytes, not characters.
    playground_bytes=\$(LC_ALL=C; echo "\''${#XNETHACK_VAR_PLAYGROUND}")
    if test "\$playground_bytes" -gt 128; then
      echo 'xnethack: state directory path exceeds 128 bytes' >&2
      exit 1
    fi
    ${coreutils}/bin/mkdir -p -- "\$state/save"
    for file in perm record logfile xlogfile livelog paniclog; do
      test -e "\$state/\$file" || : > "\$state/\$file"
    done
    unset HACKDIR NETHACKDIR
    export XNETHACK_VAR_PLAYGROUND
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/xnethack/xnethack "\$@"
    EOF
    chmod 555 $out/bin/xnethack
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for f in nhdat license symbols sysconf; do test -s $out/share/xnethack/$f; done
    test ! -e $out/share/xnethack/sounds
    grep -qF 'NETHACK GENERAL PUBLIC LICENSE' $out/share/xnethack/license
    grep -qF "$out/share/xnethack" $out/libexec/xnethack/xnethack
    ${runtimeShell} -n $out/bin/xnethack
    runHook postInstallCheck
  '';

  meta = {
    description = "Variant of NetHack with gameplay and interface changes";
    longDescription = ''
      xNetHack is a variant of NetHack that aims to make the game more
      challenging, varied, and interesting while keeping its classic feel.
      This package builds the terminal (tty) interface. Static game data stays
      in the store; saves, scores and logs live in the user's XDG state
      directory.
    '';
    homepage = "https://github.com/copperwater/xNetHack";
    license = [ lib.licenses.ngpl lib.licenses.mit ];
    mainProgram = "xnethack";
    platforms = [ "x86_64-linux" ];
  };
}
