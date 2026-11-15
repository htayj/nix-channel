{ lib, stdenvNoCC, fetchurl, appimageTools, asar }:

let
  pname = "curseforge";
  version = "1.325.0-41594";
  contents = stdenvNoCC.mkDerivation {
    inherit pname version;
    src = fetchurl {
      url = "https://curseforge.overwolf.com/electron/linux/versions/1.325.0.41594/CurseForge-${version}.tar.gz";
      hash = "sha256-TYfrmUTvi4EhjUCzHqRiQRdU6U9RIHatWLaGzVN/KPQ=";
    };
    nativeBuildInputs = [ asar ];
    # Keep the local layout override in the package so rebuilding retains it.
    postPatch = ''
      asar extract resources/app.asar app-unpacked
      cat ${./hide-ads.css} >> app-unpacked/dist/desktop/desktop.css
      cat ${./hide-ads.css} >> app-unpacked/dist/game-dashboard/game-dashboard.css
      asar pack app-unpacked resources/app.asar --unpack-dir plugins
      rm -r app-unpacked
    '';
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -a . $out/
      cat > $out/AppRun <<'EOF'
      #!/bin/sh
      exec "$APPDIR/curseforge" "$@"
      EOF
      chmod +x $out/AppRun
      runHook postInstall
    '';
    dontFixup = true;
  };
in
appimageTools.wrapAppImage {
  inherit pname version contents;
  extraPkgs = pkgs: [ pkgs.icu pkgs.openssl pkgs.libxkbcommon ];
  extraInstallCommands = ''
    cp -r ${contents}/share $out/
    substituteInPlace $out/share/applications/com.overwolf.curseforge.desktop \
      --replace-fail 'Exec=curseforge' "Exec=$out/bin/curseforge"
  '';
  meta = {
    description = "CurseForge standalone game mod and World of Warcraft addon manager";
    homepage = "https://www.curseforge.com/download/app";
    license = lib.licenses.unfree;
    mainProgram = "curseforge";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
