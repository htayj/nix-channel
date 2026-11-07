{ lib
, rustPlatform
, fetchurl
, makeWrapper
, pkg-config
, dbus
, openssl
, cacert
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "durthang";
  version = "0.2.0";

  src = fetchurl {
    url = "https://crates.io/api/v1/crates/durthang/${finalAttrs.version}/download";
    name = "durthang-${finalAttrs.version}.tar.gz";
    hash = "sha256-Ttef9729hyW1DYhcW5hoDkm5Gxh4tuLRFRtPl/f/5iY=";
  };

  # keyring's Secret Service transport is unencrypted unless a crypto feature
  # is selected; enable crypto-openssl as the Guix package does.  Cargo.lock is
  # the published lockfile with only the crates that feature adds, resolved
  # by cargo 1.99; every existing locked version is unchanged.
  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    substituteInPlace Cargo.toml \
      --replace-fail '    "linux-native",' '    "crypto-openssl",
        "linux-native",'
    cp ${./Cargo.lock} Cargo.lock
  '';

  cargoBuildFlags = [ "--locked" ];
  cargoTestFlags = [ "--locked" ];

  nativeBuildInputs = [ makeWrapper pkg-config ];
  buildInputs = [ dbus openssl ];

  postInstall = ''
    # rustls loads the native trust store; default it to the Nix CA bundle.
    wrapProgram $out/bin/durthang \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt

    doc=$out/share/doc/durthang
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
    description = "Terminal MUD client with TLS, GMCP, automap, aliases and triggers";
    longDescription = ''
      Durthang is a terminal MUD client.  It supports plain TCP and TLS
      connections, Telnet negotiation, GMCP, ANSI rendering, scrollback,
      aliases, triggers, automapping, notes and configurable sidebar panels.
      Passwords are stored through the encrypted Secret Service API, so a
      Secret Service daemon such as GNOME Keyring or KWallet must be running
      to save them.
    '';
    homepage = "https://github.com/Pommersche92/durthang";
    license = lib.licenses.gpl3Only;
    mainProgram = "durthang";
    platforms = [ "x86_64-linux" ];
  };
})
