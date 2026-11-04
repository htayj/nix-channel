{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go,
}:

# Ludvig Lundgren's Go client, packaged under the Guix name because nixpkgs'
# qbittorrent-cli is the unrelated .NET client by fedarovich.  The Guix
# qbittorrent-cli alias symlink is omitted so both can share a profile.
buildGoModule (finalAttrs: {
  pname = "ludviglundgren-qbittorrent-cli";
  version = "2.3.0";

  src = fetchFromGitHub {
    owner = "ludviglundgren";
    repo = "qbittorrent-cli";
    # Commit of tag v2.3.0, as pinned by Guix.
    rev = "7b5f87de149d699c0bd955867fe5d57418b6ec68";
    hash = "sha256-T2U7DP1LsRv1PJwsA3tl2gkUONZ/g/l/eulhSMBp4OQ=";
  };

  vendorHash = "sha256-x9WarAz+EQ4PDn1+tRNzhMoNvmP6BuMf7fylLsR2JCQ=";

  # Build and test the whole module; only the documentation generator is
  # left out, so cmd/qbt is the sole installed program.
  excludedPackages = [ "tools/gen-docs" ];

  env.CGO_ENABLED = "0";
  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
    "-X main.commit=${finalAttrs.src.rev}"
    "-X main.date=1970-01-01T00:00:00Z"
  ];

  postInstall = ''
    doc=$out/share/doc/ludviglundgren-qbittorrent-cli
    install -Dm644 LICENSE README.md go.mod go.sum -t $doc
    cp -r docs/src/content/docs $doc/commands
    # Preserve the notices of every vendored module and of the linked Go
    # runtime, and keep complete sources of MPL-covered modules.
    (cd vendor && find . -type f \( -name 'LICENSE*' -o -name 'LICENCE*' \
        -o -name 'COPYING*' -o -name 'NOTICE*' -o -name PATENTS \) \
      -exec install -Dm644 {} $doc/modules/{} \;)
    # The Nixpkgs Go output omits its notices; take them from its source.
    mkdir -p $doc/go
    tar -xzf ${go.src} -C $doc/go --strip-components=1 go/LICENSE go/PATENTS
    (cd vendor && grep -rlZ --include='LICENSE*' 'Mozilla Public License' . \
      | xargs -0 -n1 dirname | sort -u | while read -r dir; do
          mkdir -p $doc/sources/$dir
          cp -r $dir/. $doc/sources/$dir/
        done)
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/qbt version | grep -F 'Version: ${finalAttrs.version}'
    $out/bin/qbt version | grep -F 'Commit: ${finalAttrs.src.rev}'
    $out/bin/qbt --help > /dev/null
    test -s $out/share/doc/ludviglundgren-qbittorrent-cli/LICENSE
    test -s $out/share/doc/ludviglundgren-qbittorrent-cli/go/LICENSE
    test -d $out/share/doc/ludviglundgren-qbittorrent-cli/modules
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line management of qBittorrent";
    longDescription = ''
      Ludvig Lundgren's Go client for the qBittorrent Web API: torrent,
      category, tag, transfer and application management, plus local
      bencode and torrent metadata tools.  The command is qbt.
    '';
    homepage = "https://github.com/ludviglundgren/qbittorrent-cli";
    # The client is MIT; the static binary also contains modules under
    # these free licenses, whose notices are installed with the package.
    license = with lib.licenses; [
      mit
      mpl20
      asl20
      bsd0
      bsd2
      bsd3
      isc
    ];
    mainProgram = "qbt";
    platforms = [ "x86_64-linux" ];
  };
})
