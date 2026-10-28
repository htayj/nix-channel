{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, wrapGAppsHook3
, alsa-lib, gtk3, webkitgtk_4_1, libsoup_3, glib-networking, gst_all_1 }:

stdenv.mkDerivation rec {
  pname = "buzz-desktop";
  version = "0.5.28";

  src = fetchurl {
    url = "https://github.com/block/buzz/releases/download/desktop-v${version}/Buzz_${version}_amd64.deb";
    hash = "sha256-U2CfpYanh4cfCAsL/OZ5Yz5Ff2UJgkEcgboQRkjDiMs=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook wrapGAppsHook3 ];
  buildInputs = [
    alsa-lib gtk3 webkitgtk_4_1 libsoup_3 glib-networking stdenv.cc.cc.lib
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  # Keep upstream's sidecars next to the desktop executable without exposing
  # its bundled `buzz` CLI in the profile (Nixpkgs provides buzz-cli separately).
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/buzz-desktop $out/bin
    cp -r usr/bin/. $out/libexec/buzz-desktop/
    cp -r usr/share $out/
    ln -s $out/libexec/buzz-desktop/buzz-desktop $out/bin/buzz-desktop
    runHook postInstall
  '';

  meta = {
    description = "Buzz desktop workspace for humans and agents";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
