{ lib
, rustPlatform
, fetchFromGitHub
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rust-computus";
  version = "0.1.0-unstable-2026-07-26";

  src = fetchFromGitHub {
    owner = "htayj";
    repo = "computus";
    rev = "edd0c377b02bbfb3d4726d7df668761cb35accb9";
    hash = "sha256-11gF3CVwxjkJGPl70V8Gj5ZnuxCFvNK19HOp24BUAkg=";
    # The generated art is explicitly outside the GPL.  The simulation core
    # does not use it, so it is dropped from the fetched source.
    postFetch = ''
      rm -r $out/assets
    '';
  };

  # Upstream's Cargo.lock has only crates.io dependencies; build the locked graph.
  cargoHash = "sha256-hiPK/T+1gmPCkeigThdS7+8T55KOCpLw4lmf0gD9Dsc=";
  cargoBuildFlags = [ "--locked" ];
  cargoTestFlags = [ "--locked" ];

  # The workspace's only member is the simulation crate, named "core".  It is
  # a library for the WebAssembly front end and for other Rust crates, without
  # a compiler-independent binary form.  Install its source and archive, plus
  # a Cargo configuration selecting the vendored dependency closure, so
  # consumers build it offline.
  installPhase = ''
    runHook preInstall

    crate=core-0.1.0
    cargo package --package core --offline --locked --no-verify --no-metadata
    install -Dm644 target/package/$crate.crate -t $out/share/cargo/registry
    mkdir -p $out/share/cargo/src
    tar -xzf target/package/$crate.crate -C $out/share/cargo/src

    share=$out/share/rust-computus
    mkdir -p $share
    ln -s ${finalAttrs.cargoDeps}/source-registry-0 $share/vendor
    cat > $share/cargo-config.toml <<EOF
    [net]
    offline = true

    [source.crates-io]
    replace-with = "nix-vendor"

    [source.nix-vendor]
    directory = "$share/vendor"
    EOF

    install -Dm644 LICENSE -t $out/share/doc/rust-computus

    runHook postInstall
  '';

  # Build and run an external crate against the installed source, using only
  # the installed Cargo configuration.  The dependency is renamed because a
  # crate cannot refer to a dependency called "core" next to Rust's own.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    if [ -d "$NIX_BUILD_TOP/.cargo" ]; then
      mv "$NIX_BUILD_TOP/.cargo" "$NIX_BUILD_TOP/.cargo.build"
    fi
    consumer=$(mktemp -d)
    mkdir $consumer/src
    cat > $consumer/Cargo.toml <<EOF
    [package]
    name = "computus-consumer"
    version = "0.1.0"
    edition = "2021"

    [dependencies]
    computus-core = { package = "core", path = "$out/share/cargo/src/core-0.1.0" }
    EOF
    cat > $consumer/src/main.rs <<'EOF'
    use computus_core::{
        Candle, CandleKind, CandleState, Core, DayClock, Ledger, LedgerCategory, LedgerEntry,
        Phase, DAY_LENGTH_SECONDS, TALLOW_TOTAL,
    };

    fn main() {
        let mut clock = DayClock::new();
        assert_eq!(clock.phase(), Phase::Aurora);
        assert_eq!(clock.tick(DAY_LENGTH_SECONDS * 0.5), None);
        assert_eq!(clock.phase(), Phase::Meridies);
        assert_eq!(clock.tick(DAY_LENGTH_SECONDS), Some(2));

        let mut candle = Candle::new_lit(CandleKind::Tallow);
        candle.tick(TALLOW_TOTAL + 1.0);
        assert_eq!(candle.state, CandleState::Extinct);

        let mut ledger = Ledger::new();
        for (category, item, quantity, amount) in [
            (LedgerCategory::Income, "Cena", 2, 12),
            (LedgerCategory::Supplies, "Panis", 3, -9),
        ] {
            ledger.push(LedgerEntry { day: 1, category, item: item.to_string(), quantity, amount });
        }
        assert_eq!(ledger.balance(), 3);

        let saved = Core::new(7).save().expect("save");
        let reloaded = Core::load(&saved).expect("load").save().expect("save again");
        assert_eq!(saved.len(), reloaded.len());

        println!("computus consumer ok: day {} balance {}", clock.day, ledger.balance());
    }
    EOF
    install -Dm644 $out/share/rust-computus/cargo-config.toml $consumer/.cargo/config.toml
    (cd $consumer && cargo run) | grep -Fx 'computus consumer ok: day 2 balance 3'

    runHook postInstallCheck
  '';

  meta = {
    description = "Deterministic inn-management simulation core";
    longDescription = ''
      Computus is the deterministic Rust simulation core of a medieval inn
      management game.  It provides the day clock, candle, inventory, ledger,
      staff, guild, economy, save state, and seeded random-number simulation
      that the browser front end uses through WebAssembly bindings.

      The package installs the crate source under share/cargo/src/core-0.1.0.
      Copy share/rust-computus/cargo-config.toml to .cargo/config.toml of a
      dependent crate to build it offline from the vendored dependency
      closure, and rename the dependency, for example
      computus-core = { package = "core", path = "..." }.
    '';
    homepage = "https://github.com/htayj/computus";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
})
