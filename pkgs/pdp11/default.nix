{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation (finalAttrs: {
  pname = "pdp11";
  # Upstream has no release tags.
  version = "0-unstable-5b5b734";

  # The lodepng submodule is only needed by the excluded xgp11 target.
  src = fetchFromGitHub {
    owner = "aap";
    repo = "pdp11";
    rev = "5b5b734f9b574cc3257670595eee6be084f2c8aa";
    hash = "sha256-KxpdWbYhl1Ht+G6WJvhSARKXR4uMoQYV89ZTTfxp4u4=";
  };

  # Build only the CPU emulators; tv11 and xgp11 are display/network
  # console targets that need the unpopulated lodepng submodule.
  programs = [ "pdp1105" "pdp1120" "pdp1140" "pdp1145" ];

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];
  buildFlags = finalAttrs.programs;

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin $programs
    install -Dm644 -t $out/share/doc/pdp11 LICENSE README.md
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for program in $programs; do
      test -x $out/bin/$program
    done
    runHook postInstallCheck
  '';

  meta = {
    description = "Host emulators for selected PDP-11 CPU models";
    longDescription = ''
      Native host emulators for the PDP-11/05, PDP-11/20, PDP-11/40, and
      PDP-11/45.  The upstream network and graphical console targets, disk
      images, and runtime fixtures are not included.
    '';
    homepage = "https://github.com/aap/pdp11";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
