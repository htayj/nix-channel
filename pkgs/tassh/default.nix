{ lib
, rustPlatform
, fetchFromGitHub
, makeWrapper
, pkg-config
, wayland
, xvfb
, xclip
, wl-clipboard
, which
, procps
, inetutils
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tassh";
  version = "0.1.0-unstable-2026-02-28";

  src = fetchFromGitHub {
    owner = "drbeefsupreme";
    repo = "tassh";
    rev = "672569a55e6f2a0ae4274103a99b8b9abac87f4d";
    hash = "sha256-/nCIDXWq18mE1V3RSpHXIHg8DPAbMUnlZgR8eUaHJOQ=";
  };

  # Byte-identical copy of upstream's Cargo.lock at the pinned revision; build
  # and test the reviewed graph with --locked, as the Guix package does.
  cargoLock.lockFile = ./Cargo.lock;

  cargoBuildFlags = [ "--locked" ];
  cargoTestFlags = [ "--locked" ];

  # `tassh setup daemon` writes a systemd unit pointing at the binary.  Upstream
  # assumes ~/.cargo/bin/tassh; use the installed wrapper instead.
  postPatch = ''
    substituteInPlace src/setup.rs \
      --replace-fail 'home_dir().join(".cargo/bin/tassh")' \
                     'PathBuf::from(std::env::var("TASSH_BINARY").unwrap())'
  '';

  nativeBuildInputs = [ makeWrapper pkg-config ];
  buildInputs = [ wayland ];

  # The daemon runs Xvfb, xclip, wl-paste/wl-copy, which, pgrep and hostname.
  # The caller's PATH stays after these so host integration commands
  # (tailscale, ssh, systemctl, loginctl) remain discoverable.
  postInstall = ''
    wrapProgram $out/bin/tassh \
      --prefix PATH : ${lib.makeBinPath [ xvfb xclip wl-clipboard which procps inetutils ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ wayland ]} \
      --set TASSH_BINARY $out/bin/tassh

    doc=$out/share/doc/tassh
    install -Dm644 LICENSE README.md -t $doc

    # Keep the notices of the statically linked Rust crates.
    for crate in ${finalAttrs.cargoDeps}/*/; do
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

  meta = {
    description = "Tailscale and SSH PNG clipboard relay";
    homepage = "https://github.com/drbeefsupreme/tassh";
    license = lib.licenses.mit;
    mainProgram = "tassh";
    platforms = [ "x86_64-linux" ];
  };
})
