{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper, makeDesktopItem,
  copyDesktopItems, herdr-core, libglvnd, libxcb, libxkbcommon, vulkan-loader, wayland }:

stdenv.mkDerivation (finalAttrs: {
  pname = "herdr-app";
  version = "0.1.18";

  src = fetchurl {
    url = "https://releases.herdr.dev/app/${finalAttrs.version}/herdr-app-linux-x86_64.tar.gz";
    sha256 = "8a11edd79dd40b349f7286cf51910b62e21136daf8f03005a9fd2c4dc5830f83";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper copyDesktopItems ];
  buildInputs = [ libxcb libxkbcommon stdenv.cc.cc.lib ];
  # The graphical backend opens these libraries at runtime.
  runtimeDependencies = [ libglvnd vulkan-loader wayland ];
  dontStrip = true;

  desktopItems = [
    (makeDesktopItem {
      name = "herdr-app";
      desktopName = "Herdr";
      comment = "Terminals and coding agents that keep running";
      exec = "herdr-app";
      icon = "herdr-app";
      startupWMClass = "herdr-app";
      categories = [ "Development" ];
    })
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-app "$out/bin/herdr-app"
    install -Dm644 herdr-app.svg "$out/share/icons/hicolor/scalable/apps/herdr-app.svg"
    install -Dm644 -t "$out/share/doc/herdr-app" LICENSE THIRD-PARTY-NOTICES
    wrapProgram "$out/bin/herdr-app" --prefix PATH : ${lib.makeBinPath [ herdr-core ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/herdr-app" --version | grep -Fx 'herdr-app ${finalAttrs.version}'
    runHook postInstallCheck
  '';

  meta = {
    description = "Native desktop workspace for terminals and coding agents";
    homepage = "https://github.com/herdrdev/herdr-app";
    license = lib.licenses.asl20;
    mainProgram = "herdr-app";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
