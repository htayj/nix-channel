{ lib, stdenv, fetchFromGitHub, pkg-config, SDL2, SDL2_image, bash, coreutils }:

stdenv.mkDerivation {
  pname = "blincolnlights";
  # Upstream has no release tags.
  version = "0-unstable-932d2ce";

  # The Lua gitlink is not fetched: none of the selected programs needs it.
  src = fetchFromGitHub {
    owner = "aap";
    repo = "blincolnlights";
    rev = "932d2cedfaec3368d6e1890b15645decc4815429";
    hash = "sha256-SRsizOrQBXe6C3+86H2cUDGUFS/LjKW/3uowiLyACLc=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ SDL2 SDL2_image ];
  # pdp5.h and friends declare `typedef u8 bool`, which C23 rejects.
  env.NIX_CFLAGS_COMPILE = "-std=gnu17";

  postPatch = ''
    for makefile in vpanel_b18/Makefile vpanel_pdp1/Makefile vpanel_whirlwind/Makefile; do
      substituteInPlace $makefile \
        --replace-fail '$(CC) -g -I.. -o $@ $^ -lSDL2 -lSDL2_image' \
          '$(CC) $(shell pkg-config --cflags sdl2 SDL2_image) -g -I.. -o $@ $^ $(shell pkg-config --libs sdl2 SDL2_image)'
    done
    # These Makefiles spell the compiler literally as `cc`.
    for makefile in pdp1/Makefile pdp5/Makefile tx0/Makefile whirlwind/Makefile; do
      substituteInPlace $makefile --replace-fail 'cc -' '$(CC) -'
    done
  '';

  # The root Makefile also builds GPIO, Raspberry Pi, peripheral and
  # Lua-dependent targets; build only the host emulators, panels and tools.
  buildPhase = ''
    runHook preBuild
    for directory in vpanel_b18 vpanel_pdp1 vpanel_whirlwind pdp1 pdp5 tx0 whirlwind tools; do
      make -C $directory CC=${stdenv.cc.targetPrefix}cc
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    bin=$out/bin
    libexec=$out/libexec/blincolnlights
    data=$out/share/blincolnlights/pdp1
    doc=$out/share/doc/blincolnlights
    mkdir -p $bin $libexec $data $doc

    # PNG artwork is compiled into the panel binaries.
    install -m755 vpanel_b18/panel_b18 $bin/blincolnlights-panel-b18
    install -m755 vpanel_pdp1/panel_pdp1 $bin/blincolnlights-panel-pdp1
    install -m755 vpanel_whirlwind/panel_whirlwind $bin/blincolnlights-panel-whirlwind
    install -m755 tools/mkptyfl tools/mkptyfio $bin

    install -m755 pdp1/pdp1 $libexec/pdp1
    install -m755 pdp1/pdp1_b18 $libexec/pdp1-b18
    install -m755 pdp5/pdp5 $libexec/pdp5
    install -m755 tx0/tx0_pdp1 $libexec/tx0-pdp1
    install -m755 tx0/tx0_b18 $libexec/tx0-b18
    install -m755 whirlwind/whirlwind $libexec/whirlwind
    install -m755 whirlwind/whirlwind_b18 $libexec/whirlwind-b18

    cp -r pdp1/maindec $data/maindec
    cp -r pdp1/tapes $data/tapes
    # pdp1/main.c names dpys5.rim; the source ships its compatible image as ddt.rim.
    ln -s ddt.rim $data/tapes/dpys5.rim

    install -m644 LICENSE README.md $doc

    # The emulators write coremem and punch.out relative to their working
    # directory.  Run each in its own XDG state directory, with the packaged
    # PDP-1 data visible at its expected relative paths.
    for program in pdp1 pdp1-b18 pdp5 tx0-pdp1 tx0-b18 whirlwind whirlwind-b18; do
      cat > $bin/blincolnlights-$program <<EOF
    #!${bash}/bin/sh
    state_root="\''${XDG_STATE_HOME:-\$HOME/.local/state}"
    state="\$state_root/blincolnlights/blincolnlights-$program"
    ${coreutils}/bin/mkdir -p "\$state"
    ${coreutils}/bin/ln -sfn $data/maindec "\$state/maindec"
    ${coreutils}/bin/ln -sfn $data/tapes "\$state/tapes"
    cd "\$state"
    exec $libexec/$program "\$@"
    EOF
      chmod 555 $bin/blincolnlights-$program
    done
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for program in panel-b18 panel-pdp1 panel-whirlwind pdp1 pdp1-b18 pdp5 tx0-pdp1 tx0-b18 whirlwind whirlwind-b18; do
      test -x $out/bin/blincolnlights-$program
    done
    test -x $out/bin/mkptyfl
    test -x $out/bin/mkptyfio
    test -e $out/share/blincolnlights/pdp1/tapes/dpys5.rim
    ! grep -q '\\' $out/bin/blincolnlights-pdp1
    runHook postInstallCheck
  '';

  meta = {
    description = "Virtual front panels and emulators for historic computers";
    longDescription = ''
      SDL virtual front panels for the Blincolnlights 18, PDP-1 and Whirlwind,
      with host emulators for the Whirlwind, TX-0, PDP-1 and PDP-5.  The
      emulator launchers keep core and punch state in
      $XDG_STATE_HOME/blincolnlights and expose the packaged PDP-1 tapes and
      diagnostics there.  Panels communicate through the fixed shared files
      /tmp/b18_panel, /tmp/pdp1_panel and /tmp/whirlwind_panel, and the
      emulators listen on fixed TCP ports, so run one user/session at a time.
    '';
    homepage = "https://github.com/aap/blincolnlights";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "blincolnlights-pdp1";
  };
}
