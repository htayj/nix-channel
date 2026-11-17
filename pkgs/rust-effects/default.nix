{ lib
, rustPlatform
, fetchFromGitHub
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rust-effects";
  version = "0.1.0-unstable-2026-07-13";

  src = fetchFromGitHub {
    owner = "kitsuneninetails";
    repo = "rust-effects";
    rev = "d7fe96deb196fed0a222d0d3b796145f78420f39";
    hash = "sha256-izIaXN+jF3C8x9kkq6yVqTOEvpkFRv3KSkrizccLavw=";
  };

  # Upstream ships no lockfile and depends on futures, futures-util and tokio
  # with wildcard versions.  Cargo.lock is the Guix channel's reviewed graph;
  # the manifest is pinned to the same versions so that the installed source
  # resolves identically when an external crate uses it as a path dependency.
  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'edition = "2024"' \
                     $'edition = "2024"\nrust-version = "1.86"\nlicense = "MIT"' \
      --replace-fail 'futures-util = "*"' 'futures-util = "=0.3.32"' \
      --replace-fail 'futures = {version = "*"' 'futures = {version = "=0.3.32"' \
      --replace-fail 'tokio = { version = "*"' 'tokio = { version = "=1.52.3"'
    cp ${./Cargo.lock} Cargo.lock
  '';

  cargoBuildFlags = [ "--locked" ];
  cargoTestFlags = [ "--locked" ];

  # cargo test also builds upstream's example; run it as well.  Its output
  # stays out of the source tree, which cargo package archives below.
  postCheck = ''
    example=$(echo target/*/release/examples/hkt-like)
    "$example" | tee "$NIX_BUILD_TOP/example.log"
    grep -Fx 'FREE output: ["3", "1", "3", "0", "3", "1", "4", "1", "0", "1", "1"]' \
      "$NIX_BUILD_TOP/example.log"
  '';

  # A Rust library has no compiler-independent binary form.  Install the crate
  # source and archive with the lockfile, plus a Cargo configuration selecting
  # the vendored dependency closure, so consumers build it offline.
  installPhase = ''
    runHook preInstall

    crate=rust-effects-0.1.0
    cargo package --offline --locked --no-verify --no-metadata
    install -Dm644 target/package/$crate.crate -t $out/share/cargo/registry
    mkdir -p $out/share/cargo/src
    tar -xzf target/package/$crate.crate -C $out/share/cargo/src
    install -m644 Cargo.lock $out/share/cargo/src/$crate/Cargo.lock

    share=$out/share/rust-effects
    mkdir -p $share
    ln -s ${finalAttrs.cargoDeps} $share/vendor
    cat > $share/cargo-config.toml <<EOF
    [net]
    offline = true

    [source.crates-io]
    replace-with = "nix-vendor"

    [source.nix-vendor]
    directory = "$share/vendor"
    EOF
    install -Dm644 $share/cargo-config.toml $out/share/cargo/src/$crate/.cargo/config.toml

    install -Dm644 LICENSE README.md -t $out/share/doc/rust-effects

    runHook postInstall
  '';

  # Build and run an external crate against the installed source, using only
  # the installed Cargo configuration.  It is installed as the consumer's
  # .cargo/config.toml so that cargo-auditable's own cargo metadata call
  # reads it too; a --config argument does not reach that call.
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
    name = "rust-effects-consumer"
    version = "0.1.0"
    edition = "2024"

    [dependencies]
    rust-effects = { path = "$out/share/cargo/src/rust-effects-0.1.0" }
    EOF
    cat > $consumer/src/main.rs <<'EOF'
    use rust_effects::typeclasses::free_effect::free::new_free;

    fn main() {
        let program = new_free::<Vec<i32>>()
            .free_bind(|value: i32| if value % 2 == 0 { vec![value] } else { vec![] })
            .free_map(|value: i32| value * 10);
        let result: Vec<i32> = program.fold_map(vec![1, 2, 3, 4]);
        assert_eq!(result, vec![20, 40]);
        println!("rust-effects consumer ok: {result:?}");
    }
    EOF
    install -Dm644 $out/share/rust-effects/cargo-config.toml $consumer/.cargo/config.toml
    (cd $consumer && cargo run) | grep -Fx 'rust-effects consumer ok: [20, 40]'

    runHook postInstallCheck
  '';

  meta = {
    description = "Functional programming typeclasses and free effects for Rust";
    longDescription = ''
      This library provides higher-kinded-type-style functional programming
      abstractions for Rust, including functors, applicatives, monads, monoids
      and semigroups.  Its free-effect programs separate composition from
      interpretation, and its shared futures support asynchronous computations.

      The package installs the crate source under
      share/cargo/src/rust-effects-0.1.0 with a pinned lockfile.  Copy
      share/rust-effects/cargo-config.toml to .cargo/config.toml of a dependent
      crate to build it offline from the vendored dependency closure.
    '';
    homepage = "https://github.com/kitsuneninetails/rust-effects";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
