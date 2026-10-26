{
  lib,
  buildGoModule,
  fetchzip,
}:

buildGoModule (finalAttrs: {
  pname = "shamogu";
  version = "1.5.0";

  # Codeberg archive of the commit Guix pins for the 1.5.0 release.
  src = fetchzip {
    url = "https://codeberg.org/anaseto/shamogu/archive/fcd439d4d7949dfa4b9d7e513caacc0a82360384.tar.gz";
    hash = "sha256-d4PtFOVr176JqybKrKXpqNs3j8cDY9ixTkmAh0UV/TQ=";
  };

  vendorHash = "sha256-wibNLDdykV2psOnJbMKu0EZSrrhKRxrN/OTWXmUz2FM=";

  # Native terminal (tcell) frontend only: default build tags exclude the
  # SDL and browser frontends, and nothing needs cgo.
  env.CGO_ENABLED = "0";
  ldflags = [ "-s" "-w" ];

  postInstall = ''
    install -Dm644 docs/shamogu.6 -t $out/share/man/man6
    install -Dm644 LICENSE README.md CHANGES.md -t $out/share/doc/shamogu
    install -Dm644 tiles/LICENSE tiles/README -t $out/share/doc/shamogu/tiles
    # Preserve the notices of every vendored module.
    (cd vendor && find . -type f \( -name 'LICENSE*' -o -name 'COPYING*' \
        -o -name 'NOTICE*' -o -name PATENTS \) \
      -exec install -Dm644 {} $out/share/doc/shamogu/modules/{} \;)
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/shamogu -version | grep -F v${finalAttrs.version}
    runHook postInstallCheck
  '';

  meta = {
    description = "Tactical terminal roguelike with totemic spirits";
    longDescription = ''
      Shamogu is a coffee-break roguelike with tactical movement, careful
      timing of totemic spirit invocation and comestible consumption, and
      visibility and noise stealth mechanics.  This package builds the native
      ASCII terminal game.  Saves, configuration and replays live in
      $XDG_DATA_HOME/shamogu.
    '';
    homepage = "https://anaseto.codeberg.page/games/shamogu/";
    license = with lib.licenses; [ isc asl20 mit bsd3 ];
    mainProgram = "shamogu";
    platforms = [ "x86_64-linux" ];
  };
})
