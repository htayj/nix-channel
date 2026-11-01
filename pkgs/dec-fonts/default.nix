# DEC VT220 bitmap fonts generated from a ROM recreation.
{ lib, stdenvNoCC, fetchurl }:

let
  version = "0.1.0-alpha.2";
  tag = "v${version}";
in
stdenvNoCC.mkDerivation {
  pname = "dec-fonts";
  inherit version;

  src = fetchurl {
    url = "https://github.com/htayj/DEC-Fonts/releases/download/${tag}/DEC-Fonts-${tag}.tar.gz";
    hash = "sha256-ZGvWXkrQphPCye4N696fLsKrQnyyd6qlepJPKg/MfoU=";
  };

  dontConfigure = true;
  dontBuild = true;

  # Guard against silent changes to the release profile.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    count() { find "$1" -name "*.$2" | wc -l; }
    test "$(count dist/fonts/bdf bdf)" -eq 12
    test "$(count dist/fonts/otb otb)" -eq 3
    test "$(count dist/fonts/psf psf)" -eq 3
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    fontRoot=$out/share/fonts/dec-fonts
    mkdir -p $fontRoot $out/share/consolefonts
    cp -r dist/fonts/bdf $fontRoot/bdf
    cp -r dist/fonts/otb $fontRoot/otb
    cp -r dist/fonts/psf $out/share/consolefonts/dec-fonts
    install -Dm644 -t $out/share/dec-fonts dist/dec.set
    install -Dm644 -t $out/share/doc/dec-fonts LICENSE README.org THIRD_PARTY_NOTICES.md
    runHook postInstall
  '';

  meta = {
    description = "DEC VT220 bitmap fonts";
    longDescription = ''
      DEC Fonts provides bitmap fonts generated from a DEC VT220 ROM
      recreation.  The package includes BDF and OTB fonts for Fontconfig and
      X core font users, plus PSF fonts for the Linux console.
    '';
    homepage = "https://github.com/htayj/DEC-Fonts";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
