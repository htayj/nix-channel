{ lib, stdenv, fetchFromGitHub, cmake, SDL2 }:

stdenv.mkDerivation {
  pname = "aiwnios";
  version = "0.9.0-unstable-2026-02-02";

  src = fetchFromGitHub {
    owner = "aiwnios";
    repo = "Aiwnios";
    rev = "e155e87a4a4ddae4cd7f25685d9db8869fd45a40";
    hash = "sha256-dTlveH+7tNv83p4zn1LLC0m8XDSDSt9elQOAguskqzs=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ SDL2 ];

  # The runtime is bootstrapped below in a private boot directory instead of
  # upstream's source-tree targets.
  cmakeFlags = [ "-DBUILD_HCRT=OFF" ];

  postPatch = ''
    # Keep the Nix prefix (it becomes the compiled-in template directory) and
    # write the executable into the build tree.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'set(CMAKE_INSTALL_PREFIX "/usr")' "" \
      --replace-fail 'RUNTIME_OUTPUT_DIRECTORY "''${CMAKE_CURRENT_SOURCE_DIR}"' \
                     'RUNTIME_OUTPUT_DIRECTORY "''${CMAKE_CURRENT_BINARY_DIR}"'

    # Reproducibility fixes carried by the Guix package: zero the whole AOT
    # tail, the debug line map, and the rounded bytecode extent instead of
    # copying uninitialized heap bytes into HCRT2.BIN and HCRT2.DBG.Z.
    substituteInPlace Src/CMain.HC \
      --replace-fail 'MemSet(ptr,0,16);' 'MemSet(ptr,0,31);'
    substituteInPlace Src/AIWNIOS_CodeGen.HC \
      --replace-fail '*info=MAlloc((idx+2)*8+sizeof(CDbgInfo))' \
                     '*info=CAlloc((idx+2)*8+sizeof(CDbgInfo))'
    substituteInPlace c/w_bytecode.c \
      --replace-fail 'bin = A_CALLOC(len, NULL);' 'bin = A_CALLOC((len + 7) & ~7LL, NULL);'

    # Respect an explicit HOME instead of always using the passwd entry.
    substituteInPlace c/main.c \
      --replace-fail 'if (pwd)' 'if (getenv("HOME")) home = getenv("HOME"); else if (pwd)'
  '';

  postBuild = ''
    export HOME=$PWD/home
    mkdir -p "$HOME" boot
    for f in ../*; do
      [ "$f" = ../build ] || cp -r "$f" boot/
    done
    rm -f boot/HCRT2.BIN boot/HCRT2.DBG.Z boot/Registry.HC.Z
    (cd boot
     ../aiwnios -d -F -t . -b
     test -f HCRT2.BIN
     ../aiwnios -d -F -t . -c FreshOnce.HC)
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cat > boot/build-check.HC <<'EOF'
    I64 Square(I64 n) {return n*n;}
    if (Square(7)!=49) ExitAiwnios(1);
    Print("AIWNIOS_BUILD_OK\n");
    ExitAiwnios(0);
    EOF
    ./aiwnios -d -F -t boot -c build-check.HC | tee check.out
    grep -q AIWNIOS_BUILD_OK check.out
    rm boot/build-check.HC
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/aiwnios
    doc=$out/share/doc/aiwnios
    install -Dm755 aiwnios $out/bin/aiwnios
    mkdir -p $data/God $data/misc $doc/licenses
    (cd boot
     cp -r AfterEgypt Doc Apps AiwniosHelp Src Demo $data/
     install -m644 HSNotes.DD PersonalMenu.DD HCRT2.BIN $data/
     for f in HCRT2.DBG.Z Registry.HC.Z; do
       if [ -e "$f" ]; then install -m644 "$f" $data/; fi
     done
     install -m644 God/Vocab.DD $data/God/
     install -m644 misc/Bible.TXT.Z $data/misc/
     install -m644 README.MD $doc/
     install -m644 LICENSE $doc/licenses/Aiwnios
     install -m644 vendor/isocline/LICENSE $doc/licenses/isocline
     install -m644 vendor/argtable3/LICENSE $doc/licenses/argtable3)
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s $out/share/aiwnios/HCRT2.BIN
    grep -q "$out/share/aiwnios" $out/bin/aiwnios
    runHook postInstallCheck
  '';

  meta = {
    description = "HolyC compiler and TempleOS-like host environment";
    longDescription = ''
      Aiwnios compiles and executes HolyC on a host operating system.  Its
      self-hosted runtime includes the TempleOS-style DolDoc desktop, editor,
      graphics, help and example applications, plus command-line and terminal
      modes.  The installed boot template is copied to a writable directory
      (~/.local/share/aiwnios/T) on first launch; -t selects another boot
      directory.  HolyC runs as native code with the user's authority and is
      not a sandbox.
    '';
    homepage = "https://github.com/aiwnios/Aiwnios";
    # Aiwnios BSD-3; isocline MIT; argtable3 BSD-3/BSD-2/Tcl notices.
    license = with lib.licenses; [ bsd3 mit bsd2 tcltk ];
    mainProgram = "aiwnios";
    platforms = [ "x86_64-linux" ];
  };
}
