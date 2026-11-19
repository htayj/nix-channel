{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
}:

buildNpmPackage (finalAttrs: {
  pname = "scala-ts";
  version = "0.1.8";

  src = fetchFromGitHub {
    owner = "codingismy11to7";
    repo = "scala-ts";
    rev = "9342030a619f9d3f8463bd23becd9051231af21e";
    hash = "sha256-6kELb9q/TlJOvPhDFccBANsyI7C9BQav+Pnsn/uC6LU=";
  };

  nodejs = nodejs_22;

  # Upstream's package-lock.json is lockfileVersion 1.  npm completes such a
  # lockfile from registry metadata, which fetcher version 2 stores beside
  # the 698 locked archives.  All of them are build-time tools except
  # immutable.
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-bgjvRW+I+VcGDYWiQsSzPw9ihudBv9IKj+z6ewFpYzU=";
  # No dependency lifecycle scripts run (husky would install Git hooks).
  npmRebuildFlags = [ "--ignore-scripts" ];

  env.NO_UPDATE_NOTIFIER = "1";

  # The default build is upstream's `npm run build`: tsc to CommonJS modules
  # and declarations in dist, then the rollup bundle and the typedoc pages.

  doCheck = true;
  # tslint, then the jest suite.
  checkPhase = ''
    runHook preCheck
    npm run test:prod
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    module=$out/lib/node_modules/scala-ts
    mkdir -p "$module/node_modules"
    cp -r dist package.json LICENSE README.md "$module"

    # package.json names the rollup bundle, which is not installed.  Point
    # consumers at the compiled CommonJS entry and its declarations.
    substituteInPlace "$module/package.json" --replace-fail \
      '"main": "legacy/scala-ts.umd.js",' \
      '"main": "dist/scala-ts.js", "types": "dist/scala-ts.d.ts",'

    # ES5 class lowering copies TypeScript's __extends helper into
    # dist/Exceptions.js; its notice and licence go with that code.
    install -m444 node_modules/typescript/CopyrightNotice.txt \
      "$module/TypeScript-CopyrightNotice.txt"
    install -m444 node_modules/typescript/LICENSE.txt "$module/TypeScript-LICENSE.txt"

    # The modules and their declarations import immutable, a peer dependency:
    # install the lock-selected release beside them.
    cp -r node_modules/immutable "$module/node_modules/immutable"

    mkdir -p $out/share/doc/scala-ts
    ln -s "$module"/{README.md,LICENSE} $out/share/doc/scala-ts

    runHook postInstall
  '';

  doInstallCheck = true;
  # A consumer outside the source tree resolves the installed package by
  # name, type-checks against its declarations and runs.
  installCheckPhase = ''
    runHook preInstallCheck

    grep -F '"version": "4.0.0-rc.12"' \
      $out/lib/node_modules/scala-ts/node_modules/immutable/package.json

    tsc=$PWD/node_modules/typescript/bin/tsc
    consumer=$(mktemp -d)
    mkdir "$consumer/node_modules"
    ln -s $out/lib/node_modules/scala-ts "$consumer/node_modules/scala-ts"
    cp ${./check-consumer.ts} "$consumer/check-consumer.ts"
    (
      cd "$consumer"
      node "$tsc" --strict --target es2015 --module commonjs --moduleResolution node \
        check-consumer.ts
      node check-consumer.js
    )

    runHook postInstallCheck
  '';

  meta = {
    description = "Scala-inspired functional programming data types for TypeScript";
    longDescription = ''
      Scala-ts provides Option, Either, Try, Future, Lazy and Duration types
      modelled on Scala's standard library.  The CommonJS modules and their
      TypeScript declarations are installed under lib/node_modules/scala-ts,
      together with the immutable release they import.
    '';
    homepage = "https://github.com/codingismy11to7/scala-ts";
    # scala-ts is Apache-2.0; the installed immutable and the TypeScript
    # helper emitted into dist are MIT and Apache-2.0.
    license = with lib.licenses; [
      asl20
      mit
    ];
    platforms = [ "x86_64-linux" ];
  };
})
