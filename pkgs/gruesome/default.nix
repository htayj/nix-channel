{
  lib,
  stdenv,
  fetchurl,
  fpc,
  unzip,
  runtimeShell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gruesome";
  version = "0.0.3";

  src = fetchurl {
    url = "http://www.gamesofgrey.com/games/gruesome/gruesome${finalAttrs.version}.zip";
    hash = "sha256-L9Tu1FlUpqOJOqOZWIce+cOp0jrYe5jasBTBPfsTiPA=";
  };

  sourceRoot = "Gruesome";

  nativeBuildInputs = [
    fpc
    unzip
  ];

  dontConfigure = true;

  # The archive holds a single Free Pascal program and no build system.
  buildPhase = ''
    runHook preBuild
    mkdir -p build/units
    fpc -O2 -g- -FUbuild/units -FEbuild -obuild/gruesome-real source.pas
    runHook postBuild
  '';

  # The bundled Windows executable is not installed.
  installPhase = ''
    runHook preInstall
    install -Dm755 build/gruesome-real $out/libexec/gruesome/gruesome-real
    for f in license.txt readme.txt history.txt source.pas; do
      install -Dm644 "$f" "$out/share/doc/gruesome/$f"
    done
    mkdir -p $out/bin
    cat > $out/bin/gruesome <<EOF
    #!${runtimeShell}
    set -eu
    exec $out/libexec/gruesome/gruesome-real "\$@"
    EOF
    chmod 555 $out/bin/gruesome
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/gruesome/gruesome-real
    grep -q 'GNU GENERAL PUBLIC LICENSE' $out/share/doc/gruesome/license.txt
    runHook postInstallCheck
  '';

  meta = {
    description = "Console roguelike about a grue in procedurally generated caves";
    longDescription = ''
      Gruesome is a console roguelike in which the player controls a grue that
      explores randomly generated caverns, avoids torchlight, and hunts
      adventurers.  This package builds the upstream Pascal source with Free
      Pascal and installs the upstream documentation and GPL notice.
    '';
    homepage = "http://www.gamesofgrey.com/games/gruesome/";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "gruesome";
  };
})
