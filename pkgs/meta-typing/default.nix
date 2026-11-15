{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchYarnDeps,
  yarnConfigHook,
  nodejs,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "meta-typing";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "ronami";
    repo = "meta-typing";
    rev = "03a4927933e3a6e6439d42f29d656353512fe308";
    hash = "sha256-tC0/i+MqCO6JxF/Ul0YgVnu0u9kTb7av13TDAWPk2zw=";
  };

  # Upstream's yarn.lock selects the compiler (TypeScript 3.7.4) and the tsd
  # 0.11.0 test runner.  They are build-time tools only.
  yarnOfflineCache = fetchYarnDeps {
    yarnLock = finalAttrs.src + "/yarn.lock";
    hash = "sha256-FSs5WKTEJjOR1tu/nVHv+EghSWz7+r+ioEHk2ewtC9k=";
  };

  nativeBuildInputs = [
    yarnConfigHook
    nodejs
  ];

  env.NO_UPDATE_NOTIFIER = "1";

  # The declarations are the artifact: type-check the whole tree with
  # upstream's strict, noEmit tsconfig.
  buildPhase = ''
    runHook preBuild
    node node_modules/typescript/bin/tsc -p tsconfig.json
    runHook postBuild
  '';

  doCheck = true;
  # package.json's `test` script is `tsd`, over the unmodified src tree.
  checkPhase = ''
    runHook preCheck
    node node_modules/tsd/dist/cli.js
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    module=$out/lib/node_modules/meta-typing
    mkdir -p "$module"
    # Public declarations only; the *.test-d.ts files need tsd.
    find src -name '*.d.ts' -exec cp --parents -t "$module" {} +
    cp -r package.json LICENSE README.md assets "$module"

    mkdir -p $out/share/doc/meta-typing
    ln -s "$module"/{README.md,LICENSE,assets} $out/share/doc/meta-typing

    runHook postInstall
  '';

  doInstallCheck = true;
  # A consumer outside the source tree resolves the installed package by name.
  installCheckPhase = ''
    runHook preInstallCheck

    tsc=$PWD/node_modules/typescript/bin/tsc
    consumer=$(mktemp -d)
    mkdir "$consumer/node_modules"
    ln -s $out/lib/node_modules/meta-typing "$consumer/node_modules/meta-typing"
    cat > "$consumer/accepted.ts" <<'EOF'
    import { Add, Reverse } from 'meta-typing';
    export const sum: Add<2, 3> = 5;
    export const reversed: Reverse<[1, 2, 3]> = [3, 2, 1];
    EOF
    cat > "$consumer/rejected.ts" <<'EOF'
    import { Add } from 'meta-typing';
    export const sum: Add<2, 3> = 6;
    EOF
    (
      cd "$consumer"
      node "$tsc" --noEmit --strict --moduleResolution node accepted.ts
      if node "$tsc" --noEmit --strict --moduleResolution node rejected.ts > rejected.log; then
        echo "a wrong sum type-checked" >&2
        exit 1
      fi
      grep -F "Type '6' is not assignable to type '5'" rejected.log
    )

    runHook postInstallCheck
  '';

  meta = {
    description = "Algorithms and data structures expressed as TypeScript types";
    longDescription = ''
      Meta-typing implements arithmetic, list operations, sorting, trees,
      matrices and puzzles entirely in TypeScript's type system.  This
      declaration-only package installs the public type tree under
      lib/node_modules/meta-typing; it has no JavaScript entry point.
    '';
    homepage = "https://github.com/ronami/meta-typing";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
