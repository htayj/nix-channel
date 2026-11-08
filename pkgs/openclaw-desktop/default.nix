{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, wrapGAppsHook3
, gtk3, webkitgtk_4_1, libsoup_3, glib-networking, libayatana-appindicator
, gst_all_1 }:

stdenv.mkDerivation rec {
  pname = "openclaw-desktop";
  version = "2026.11.1";

  src = fetchurl {
    url = "https://github.com/openclaw/openclaw/releases/download/v${version}/OpenClaw-${version}-amd64.deb";
    hash = "sha256-7AajW1tRTjGbPHY9HmBZg171R0Cyk7/XOxmisfwvDBY=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook wrapGAppsHook3 ];
  buildInputs = [
    gtk3 webkitgtk_4_1 libsoup_3 glib-networking stdenv.cc.cc.lib
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
  ];
  # Tauri loads the tray indicator at runtime rather than linking to it.
  runtimeDependencies = [ libayatana-appindicator ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r usr/bin usr/lib usr/share $out/
    runHook postInstall
  '';

  meta = {
    description = "OpenClaw desktop companion for local and remote Gateways";
    homepage = "https://docs.openclaw.ai/platforms/linux";
    license = lib.licenses.mit;
    mainProgram = "openclaw-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
