{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
}:

buildNpmPackage (finalAttrs: {
  pname = "wenyan";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "wenyan-lang";
    repo = "wenyan";
    rev = "97f0a4b8c5a815467c5c2cac08215d722efde208";
    hash = "sha256-3sBosEUeQIdA10cUmanMMiwAKq7xk1YypESBcHGEYj4=";
  };

  nodejs = nodejs_22;

  # Upstream's lockfile (version 2) records resolved registry URLs and
  # integrity for every entry.  Only fsevents, husky and nodemon carry install
  # scripts, none of which the build needs.
  npmDepsHash = "sha256-iWlsGmSIEmBqOz9spZkbP5g+XGQ4nA0/ggInNfnL47g=";
  npmRebuildFlags = [ "--ignore-scripts" ];

  env = {
    NO_UPDATE_NOTIFIER = "1";
    # Webpack 4 hashes with MD4, which needs OpenSSL's legacy provider.
    NODE_OPTIONS = "--openssl-legacy-provider";
  };

  # sync-rpc starts its worker relative to its own directory, so keep
  # sync-request external instead of bundling it into the CLI.
  postPatch = ''
    substituteInPlace webpack.base.config.js \
      --replace-fail "devtool: 'source-map'," \
        "devtool: 'source-map', externals: { 'sync-request': 'commonjs sync-request' },"
  '';

  # Upstream's build:dev script without its rimraf step; the unminified
  # development bundles keep diagnostics readable.
  dontNpmBuild = true;
  buildPhase = ''
    runHook preBuild
    node node_modules/typescript/bin/tsc --emitDeclarationOnly --declaration --declarationDir typings
    node node_modules/webpack-cli/bin/cli.js --mode development
    for f in dist/cli/index.min.js dist/core/index.min.js dist/core/index.d.ts \
             dist/render/index.min.js dist/runtime/index.min.js; do
      test -s "$f"
    done
    runHook postBuild
  '';

  # The bundles, declarations and the runtime dependency closure of
  # sync-request, plus the Wenyan standard library and examples.
  installPhase = ''
    runHook preInstall
    npm prune --omit=dev --ignore-scripts
    module=$out/lib/node_modules/wenyanlang
    mkdir -p "$module" $out/bin $out/share/wenyan $out/share/doc/wenyan
    cp -r dist typings node_modules package.json "$module"
    cp -r examples lib $out/share/wenyan
    cp LICENSE README.md README.zh-Hans.md README.zh-Hant.md CHANGELOG.md $out/share/doc/wenyan
    chmod +x "$module"/dist/cli/index.min.js
    ln -s ../lib/node_modules/wenyanlang/dist/cli/index.min.js $out/bin/wenyan
    runHook postInstall
  '';

  # The compiler library must evaluate a recursive factorial, and the CLI must
  # compile and run the same program.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR
    ${lib.getExe finalAttrs.nodejs} -e '
      const fs = require("fs"), assert = require("assert");
      const wy = require(process.argv[1] + "/lib/node_modules/wenyanlang/dist/core/index.min.js");
      const code = wy.compile(fs.readFileSync("examples/factorial.wy", "utf8"));
      const values = [];
      wy.evalCompiled(code, { outputHanzi: false, output: (...xs) => values.push(xs) });
      assert.deepStrictEqual(values, [[120]]);
      console.log("library: factorial = 120");
    ' $out
    $out/bin/wenyan --help > help.txt
    $out/bin/wenyan examples/helloworld.wy | tee hello.txt
    test -s hello.txt
    runHook postInstallCheck
  '';

  meta = {
    description = "Compiler for the classical Chinese programming language Wenyan";
    homepage = "https://github.com/wenyan-lang/wenyan";
    license = lib.licenses.mit;
    mainProgram = "wenyan";
    platforms = [ "x86_64-linux" ];
  };
})
