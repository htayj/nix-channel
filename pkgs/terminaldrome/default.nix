{ lib
, rustPlatform
, fetchFromGitHub
, makeWrapper
, mpv
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "terminaldrome";
  version = "0.7.4";

  src = fetchFromGitHub {
    owner = "thafaker";
    repo = "TerminalDrome";
    rev = "cad7698a22c4c6ed2d7efa6150ab4b4d8857fb47";
    hash = "sha256-AbiglQmbfwFg9WtXz6OB1sfcjEdQSj/y5d6CPgm8o2U=";
  };

  # Upstream's Cargo.lock has only crates.io dependencies; build the locked graph.
  cargoHash = "sha256-EUhzlqBnz2v9njwihLn2oG+pinVGlVtj0h8pXRMIUbk=";
  cargoBuildFlags = [ "--locked" ];
  cargoTestFlags = [ "--locked" ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    # Playback starts mpv by name.  The optional visualizer uses cava and
    # ffmpeg from the user's PATH and falls back to a demo animation.
    wrapProgram $out/bin/terminaldrome \
      --prefix PATH : ${lib.makeBinPath [ mpv ]}

    doc=$out/share/doc/terminaldrome
    install -Dm644 README.md config.toml.template -t $doc

    # Keep the notices of the statically linked Rust crates.
    for crate in ${finalAttrs.cargoDeps}/source-registry-0/*/; do
      name=$(basename "$crate")
      for file in "$crate"*; do
        [ -f "$file" ] || continue
        base=$(basename "$file")
        case "''${base,,}" in
          license|license[-.]*|licence|licence[-.]*|copying|copying[-.]*|copyright|copyright[-.]*|notice|notice[-.]*|unlicense|unlicense[-.]*)
            install -Dm644 "$file" -t "$doc/third-party-licenses/$name"
            ;;
        esac
      done
    done
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    grep -q '${mpv}/bin' $out/bin/terminaldrome
    grep -aq 'Config file not found' $out/bin/.terminaldrome-wrapped
    grep -aq 'version 0.7.4' $out/bin/.terminaldrome-wrapped
    test -f $out/share/doc/terminaldrome/config.toml.template
    test -n "$(ls $out/share/doc/terminaldrome/third-party-licenses)"
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal client for Navidrome and other Subsonic-compatible music servers";
    longDescription = ''
      TerminalDrome browses artists, albums, songs and playlists on a
      Navidrome server and streams tracks through mpv.  It reads
      ./config.toml or ~/.config/TerminalDrome/config.toml; a template is
      installed in share/doc/terminaldrome.
    '';
    homepage = "https://github.com/thafaker/TerminalDrome";
    license = lib.licenses.mit;
    mainProgram = "terminaldrome";
    platforms = [ "x86_64-linux" ];
  };
})
