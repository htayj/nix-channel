{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, cairo
, pango
, freetype
, libxkbcommon
, wayland
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "notion-river";
  # v0.6.0 is the nearest tag; the pinned commit is fourteen commits later.
  # Cargo.toml still reports the program version 0.5.3.
  version = "0.6.0-14.ge79dea3";

  # The vendor/river submodule is not fetched: River is a separate runtime
  # compositor that the user supplies on PATH.
  src = fetchFromGitHub {
    owner = "Marenz";
    repo = "notion-river";
    rev = "e79dea34c3f32987c42e338db6a5c341bce0af23";
    hash = "sha256-nJTxbUbzuQn9+SukHYDtsOKWt98k5hDr+T/ZMgPgH+E=";
  };

  cargoHash = "sha256-DDZfkqfiiYYad2rB1wvcJdL1Pbvfe8fTJXpfv+lCGKw=";

  cargoBuildFlags = [ "--locked" ];
  cargoTestFlags = [ "--locked" ];

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ cairo pango freetype libxkbcommon wayland ];

  postPatch = ''
    substituteInPlace notion-river-session \
      --replace-fail '$HOME/.config/river/init' '${"$"}{XDG_CONFIG_HOME:-$HOME/.config}/river/init'
    substituteInPlace notion-river.desktop \
      --replace-fail /usr/bin/notion-river-session $out/bin/notion-river-session
    substituteInPlace config-examples/river-init \
      --replace-fail /usr/share/notion-river/examples $out/share/notion-river/examples
  '';

  # Upstream's tests create IPC fixtures; keep that state in the build tree.
  preCheck = ''
    export XDG_RUNTIME_DIR=$(mktemp -d)
    chmod 700 $XDG_RUNTIME_DIR
    export XDG_CONFIG_HOME=$(mktemp -d)
  '';

  postInstall = ''
    install -Dm755 notion-river-session -t $out/bin
    mkdir -p $out/share/notion-river
    cp -r config-examples $out/share/notion-river/examples
    cp config.example.toml $out/share/notion-river/examples/config.toml
    install -Dm644 notion-river.desktop -t $out/share/wayland-sessions
    install -Dm644 completions/notion-ctl.fish -t $out/share/fish/vendor_completions.d
    install -Dm644 LICENSE README.md -t $out/share/doc/notion-river
    install -Dm644 protocol/*.xml -t $out/share/doc/notion-river/protocol
  '';

  meta = {
    description = "Notion/Ion3-style static tiling window manager for the River compositor";
    homepage = "https://github.com/Marenz/notion-river";
    license = lib.licenses.mit;
    mainProgram = "notion-river";
    platforms = [ "x86_64-linux" ];
  };
})
