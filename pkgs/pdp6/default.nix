{ lib, stdenv, fetchFromGitHub, makeWrapper, pkg-config, SDL2, SDL2_image }:

stdenv.mkDerivation {
  pname = "pdp6";
  # Upstream has no release tags.
  version = "0-unstable-2645ed9";

  src = fetchFromGitHub {
    owner = "aap";
    repo = "pdp6";
    rev = "2645ed907d0267710866fd8228863ce8867f4dc6";
    hash = "sha256-cPqfcKpA53lnkYwjAYSkjHkBPZVhVQUkXh4I6RICLwo=";
  };

  # sdl2-config supplies the SDL headers and libraries; the panel art is
  # compiled in from art/panelart.inc.
  nativeBuildInputs = [ makeWrapper pkg-config SDL2 ];
  buildInputs = [ SDL2 SDL2_image ];

  makeFlags = [ "-C" "emu" "CC=${stdenv.cc.targetPrefix}cc" ];
  buildFlags = [ "pdp6" ];
  # pdp6.h declares `typedef uchar bool`, which C23 rejects.
  env.NIX_CFLAGS_COMPILE = "-std=gnu17";

  # The emulator reads init.ini from its working directory.  This one
  # configures local devices only; upstream's sample also mounts paths
  # relative to the source tree and connects a network console.
  initIni = ''
    mkdev apr apr166
    mkdev tty tty626
    mkdev ptr ptr760
    mkdev ptp ptp761
    mkdev dc dc136
    mkdev dt0 dt551
    mkdev dx0 dx555
    mkdev fmem fmem162 0
    mkdev mem0 moby
    connectdev dc dt0
    connectdev dt0 dx0 1
    connectio tty apr
    connectio ptr apr
    connectio ptp apr
    connectio dc apr
    connectio dt0 apr
    connectmem fmem 0 apr -1
    connectmem mem0 0 apr 0
  '';
  passAsFile = [ "initIni" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 emu/pdp6 $out/libexec/pdp6/pdp6
    install -Dm644 $initIniPath $out/libexec/pdp6/init.ini
    makeWrapper $out/libexec/pdp6/pdp6 $out/bin/pdp6 \
      --chdir $out/libexec/pdp6
    install -Dm644 -t $out/share/doc/pdp6 LICENSE README.md
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/bin/pdp6
    # An unknown option prints usage and exits before SDL initialisation.
    if $out/bin/pdp6 -x 2> usage.txt; then exit 1; fi
    grep -q 'usage: ' usage.txt
    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical PDP-6 console emulator with a local device set";
    longDescription = ''
      The upstream SDL PDP-6 emulator with its operator panel, configured
      with local devices only.  Network, serial, FPGA, and hardware panel
      variants are not included.
    '';
    homepage = "https://github.com/aap/pdp6";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "pdp6";
  };
}
