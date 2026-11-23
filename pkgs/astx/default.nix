{
  lib,
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  esbuild,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_22,
  makeWrapper,
}:

let
  # astx's lockfile (v6.0) and packageManager field pin pnpm 8.11.0, which
  # nixpkgs no longer ships.  Build that release with the nixpkgs pnpm recipe;
  # pnpm 8 emits no shell completion, so skip that step.
  pnpm = (pnpm_10.override {
    version = "8.11.0";
    hash = "sha256-WFiAbDspLL7Im1UzZiFoqVc1jiu9hkMVFtRB3Br6zok=";
  }).overrideAttrs { postInstall = ""; };

  # The lockfile pins esbuild 0.25.0, whose JavaScript API refuses any other
  # binary version, so build that release from source instead of using the
  # downloaded platform binary.
  esbuild' = esbuild.override {
    buildGoModule =
      args:
      buildGoModule (
        args
        // rec {
          version = "0.25.0";
          src = fetchFromGitHub {
            owner = "evanw";
            repo = "esbuild";
            rev = "v${version}";
            hash = "sha256-L9jm94Epb22hYsU3hoq1lZXb5aFVD4FC4x2qNt0DljA=";
          };
          vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
        }
      );
  };

  nodejs = nodejs_22;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "astx";
  version = "0.0.0-development-0.9f0ee21";

  src = fetchFromGitHub {
    owner = "codemodsquad";
    repo = "astx";
    rev = "9f0ee21ce3b1e34a0122a50a5e604a109fa9a09a";
    hash = "sha256-2gW2EYnuuBjL/wRHmHDC08BrX4ltu6qiQwkHTxv2+ms=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-z+MqSc9ipMM1lnjuPLcvd3BVQLVZygjdVGK4+/oE4kg=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm
    pnpmConfigHook
    makeWrapper
  ];

  env.ESBUILD_BINARY_PATH = lib.getExe esbuild';

  buildPhase = ''
    runHook preBuild
    patchShebangs node_modules/.bin node_modules/@jcoreio/toolchain
    node node_modules/@jcoreio/toolchain/scripts/toolchain.cjs build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    pnpm prune --prod
    # Drop the downloaded esbuild platform binaries; the wrapper points the
    # esbuild API at the source-built one.
    rm -rf node_modules/.pnpm/@esbuild+*
    find node_modules -xtype l -delete

    module=$out/lib/node_modules/astx
    mkdir -p $module $out/share/doc/astx
    cp -r dist node_modules package.json $module/
    cp LICENSE.md README.md $out/share/doc/astx/
    makeWrapper ${lib.getExe nodejs} $out/bin/astx \
      --add-flags $module/dist/cli/index.js \
      --set-default ESBUILD_BINARY_PATH ${lib.getExe esbuild'} \
      --set-default ASTX_WORKERS 1
    runHook postInstall
  '';

  passthru.esbuild = esbuild';

  meta = {
    description = "Structural search and replace for JavaScript and TypeScript";
    homepage = "https://github.com/codemodsquad/astx";
    license = lib.licenses.mit;
    mainProgram = "astx";
    platforms = [ "x86_64-linux" ];
  };
})
