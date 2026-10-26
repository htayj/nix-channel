{
  lib,
  stdenv,
  coreutils,
  fetchFromGitHub,
  runtimeShell,
}:

stdenv.mkDerivation {
  pname = "hunger-games";
  version = "3.5";

  # The Hunger Games simulation ships as a script for the Daedalus 3.5 engine.
  src = fetchFromGitHub {
    owner = "CruiserOne";
    repo = "Daedalus";
    rev = "32af46ddf22e53c9bfd7bd7eacca1e249c60a5e8";
    hash = "sha256-WXj5kp0ul++TEgQ3gev/qw4N4Kp6SupTuqMt/L/ovzk=";
  };

  # Select the documented Unix build by disabling the Windows and PC macros
  # (the sources use CRLF line endings).
  # Bitmap storage uses 32-bit words, so `unsigned long' overruns it on LP64.
  # GCC may select the sized-delete ABI, which upstream does not declare.
  # Current libstdc++ defines placement new and delete in <new>, so the
  # upstream redefinitions are compiled out.
  postPatch = ''
    sed -i -E 's@^#define (WIN|PC)(\r?)$@// #define \1\2@' util.h
    ! grep -Eq '^#define (WIN|PC)[[:space:]]*$' util.h
    substituteInPlace util.h \
      --replace-fail 'typedef unsigned long dword;' 'typedef unsigned int dword;'
    sed -i \
      -e 's@^void \*operator new(size_t cb, void \*pv)@void operator delete(void *pv, size_t cb) { DeallocateP(pv); }\n#if 0\n&@' \
      -e 's@^// Change the size of a memory allocation@#endif\n&@' \
      util.cpp
    test "$(grep -c '^#if 0$' util.cpp)" -eq 1
    test "$(grep -c '^#endif$' util.cpp)" -ge 1
    grep -q '^void operator delete(void \*pv, size_t cb)' util.cpp
  '';

  dontConfigure = true;
  buildFlags = [ "daedalus" ];
  # Upstream passes constant string tables directly as printf formats, and
  # the script engine stores FILE pointers in 32-bit integer variables, which
  # only round-trip with a low non-PIE heap.
  hardeningDisable = [ "format" ];
  env.NIX_CFLAGS_COMPILE = "-fno-pie";
  env.NIX_CFLAGS_LINK = "-no-pie";

  installPhase = ''
    runHook preInstall
    install -Dm755 daedalus $out/libexec/hunger-games/daedalus
    install -Dm644 -t $out/share/hunger-games hunger.ds hunger.bmp
    install -Dm644 -t $out/share/doc/hunger-games README.md license.htm \
      changes.htm changes.doc daedalus.htm daedalus.doc script.htm script.doc
    mkdir -p $out/bin
    cat > $out/bin/hunger-games <<EOF
    #!${runtimeShell}
    set -eu
    test "\$#" -eq 0 || { echo 'usage: hunger-games' >&2; exit 64; }
    case "\''${XDG_STATE_HOME:-}" in
      /*) state="\$XDG_STATE_HOME" ;;
      *) state="\''${HOME:?HOME must be set when XDG_STATE_HOME is not absolute}/.local/state" ;;
    esac
    state="\$state/hunger-games"
    ${coreutils}/bin/mkdir -p "\$state"
    cd "\$state"
    ${coreutils}/bin/ln -sfn $out/share/hunger-games/hunger.ds hunger.ds
    ${coreutils}/bin/ln -sfn $out/share/hunger-games/hunger.bmp hunger.bmp
    exec $out/libexec/hunger-games/daedalus "OpenScript 'hunger.ds' fNoExit 1 fSkipMessageDisplay 0"
    EOF
    chmod 555 $out/bin/hunger-games
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/hunger-games/daedalus
    test -s $out/share/hunger-games/hunger.ds
    status=0; $out/bin/hunger-games extra 2>/dev/null || status=$?
    test "$status" -eq 64
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal Hunger Games simulation for the Daedalus engine";
    longDescription = ''
      Hunger Games is a turn-based survival simulation implemented as a
      Daedalus 3.5 script.  The launcher keeps state in
      $XDG_STATE_HOME/hunger-games (default ~/.local/state/hunger-games) and
      enters the Daedalus command prompt with the script loaded.  Enter
      *FHelp for help, MoveForward to move, and fNoExit 0 Exit to leave.
    '';
    homepage = "https://github.com/CruiserOne/Daedalus";
    license = lib.licenses.gpl2Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hunger-games";
  };
}
