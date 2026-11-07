{ lib
, rustPlatform
, fetchFromGitHub
, fetchurl
, cmake
, jq
, nodejs
}:

let
  # Four linked crates are published without their license text; each file is
  # taken from the upstream commit recorded in the crate's .cargo_vcs_info.json.
  crateLicense = repository: rev: hash: fetchurl {
    name = "${baseNameOf repository}-${builtins.substring 0 12 rev}-LICENSE";
    url = "https://raw.githubusercontent.com/${repository}/${rev}/LICENSE";
    inherit hash;
  };
  suppliedLicenses = {
    "fast-glob-1.0.1" = crateLicense "oxc-project/fast-glob"
      "96fc2766c419687ae5b29a34c304538251535595"
      "sha256-aCC1w2n6TAzaCIYw0XpjXx3NtLVQH2B3mWk0+rFpDis=";
    "napi-3.9.0" = crateLicense "napi-rs/napi-rs"
      "e9c50bb430b7d34659c0541f600e1e323d37432a"
      "sha256-PxzmZTMwLfOjLtv9/At48N00ZZ5MH1gXFi5eo8IpchU=";
    "napi-sys-3.2.1" = crateLicense "napi-rs/napi-rs"
      "be4b16ca00aa2cecd19be6ffe6de59495b471b14"
      "sha256-PxzmZTMwLfOjLtv9/At48N00ZZ5MH1gXFi5eo8IpchU=";
    "nodejs-built-in-modules-1.0.0" = crateLicense "oxc-project/nodejs-built-in-modules"
      "9117efa38fe088325e8a1036a8ddea7f3546c1ac"
      "sha256-IFOCV8+xgS1IFkp9EcAAimazPAG03r36DsKhBP4A8Cg=";
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "node-unrs-resolver";
  version = "1.12.2";

  src = fetchFromGitHub {
    owner = "unrs";
    repo = "unrs-resolver";
    # Tag v1.12.2.
    rev = "ccb26d205e2938b16069c64a28996b48ee97ff94";
    hash = "sha256-iEd6VfuQpCWOo7DHzjKdjhPQZr3n/vgoUPBrRo5O4wk=";
  };

  # Upstream's Cargo.lock has only crates.io dependencies; build the locked graph.
  cargoHash = "sha256-rQwSfZfR0DIa4Yp91OKyT01e125r3Ox0N9BMFWWWvcY=";
  # Upstream's release build: `napi build --platform --release
  # --features allocator` on the napi workspace member.
  cargoBuildFlags = [ "--locked" "--package" "unrs_resolver_napi" ];
  buildFeatures = [ "allocator" ];

  # libmimalloc-sys2 builds mimalloc through the cmake crate.
  nativeBuildInputs = [ cmake jq ];
  dontUseCmakeConfigure = true;

  # Upstream's Rust and Vitest suites need pnpm- and Yarn-installed fixture
  # node_modules trees; the install check exercises the delivered package
  # through its own JavaScript loader.
  doCheck = false;

  postInstall = ''
    module=$out/lib/node_modules/unrs-resolver
    mkdir -p $module
    mv $out/lib/libunrs_resolver_napi.so $module/resolver.linux-x64-gnu.node
    install -Dm644 napi/index.js napi/index.d.ts napi/browser.js -t $module
    install -Dm644 LICENSE README.md -t $module
    # The published manifest, without its development fields, postinstall
    # hook and prebuilt binding dependency.
    jq 'del(.scripts, .dependencies, .devDependencies, .packageManager)' \
      package.json > $module/package.json

    licenses=$out/share/doc/node-unrs-resolver/licenses
    for crate in ${finalAttrs.cargoDeps}/source-registry-0/*/; do
      name=$(basename "$crate")
      for file in "$crate"*; do
        [ -f "$file" ] || continue
        base=$(basename "$file")
        case "''${base,,}" in
          license|license[-.]*|licence|licence[-.]*|copying|copying[-.]*|copyright|copyright[-.]*|notice|notice[-.]*|unlicense|unlicense[-.]*)
            install -Dm644 "$file" -t "$licenses/$name"
            ;;
        esac
      done
    done
    ${lib.concatStrings (lib.mapAttrsToList (id: file: ''
      install -Dm644 ${file} $licenses/${id}/LICENSE
    '') suppliedLicenses)}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ nodejs ];
  installCheckPhase = ''
    runHook preInstallCheck
    unset NAPI_RS_NATIVE_LIBRARY_PATH
    node -e "
      const assert = require('node:assert');
      const path = require('node:path');
      const [module, fixtures] = process.argv.slice(1);
      const resolver = require(module);
      const addon = path.join(module, 'resolver.linux-x64-gnu.node');
      assert.ok(require.cache[addon], 'loader did not load ' + addon);
      assert.strictEqual(resolver.sync(fixtures, './a').path,
                         path.join(fixtures, 'a.js'));
      const factory = new resolver.ResolverFactory({ builtinModules: true });
      assert.deepStrictEqual(factory.sync(fixtures, 'node:fs').builtin,
                             { resolved: 'node:fs', isRuntimeModule: true });
    " $out/lib/node_modules/unrs-resolver \
      "$PWD/fixtures/enhanced-resolve/test/fixtures"
    test -f $out/share/doc/node-unrs-resolver/licenses/napi-3.9.0/LICENSE
    test -z "$(jq '.scripts, .dependencies' $out/lib/node_modules/unrs-resolver/package.json | grep -v null)"
    runHook postInstallCheck
  '';

  meta = {
    description = "Node.js ESM and CommonJS module resolver (Node-API addon)";
    longDescription = ''
      unrs-resolver implements Node.js ESM and CommonJS module resolution,
      with TypeScript tsconfig.json paths and Yarn Plug'n'Play support, in
      Rust.  This package builds its Node-API addon from source with the
      mimalloc allocator and installs the npm package as
      lib/node_modules/unrs-resolver with resolver.linux-x64-gnu.node.  The
      browser entry point re-exports the WebAssembly binding package, which
      is not provided.
    '';
    homepage = "https://github.com/unrs/unrs-resolver";
    # unrs-resolver, napi-rs and mimalloc are MIT; linked crates add
    # Apache-2.0, zlib (zlib-rs, libz-rs-sys, foldhash), ISC (libloading) and
    # BSD-2-Clause (pnp).  Their texts are installed under share/doc.
    license = with lib.licenses; [ mit asl20 zlib isc bsd2 ];
    # The installed file name encodes the linux-x64-gnu triple the loader requests.
    platforms = [ "x86_64-linux" ];
  };
})
