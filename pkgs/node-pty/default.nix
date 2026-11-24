{
  lib,
  stdenv,
  fetchurl,
  nodejs,
}:

let
  # Header-only C++ wrapper for N-API, needed only to compile the addon.
  nodeAddonApi = fetchurl {
    url = "https://registry.npmjs.org/node-addon-api/-/node-addon-api-7.1.1.tgz";
    hash = "sha256-sQRV0VqXfAzRehyw62eeA9k5+O+NQwLrM+H3jazHH4I=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "node-pty";
  version = "1.1.0";

  # The npm release ships compiled JavaScript in lib/ and the C++ sources.
  src = fetchurl {
    url = "https://registry.npmjs.org/node-pty/-/node-pty-${finalAttrs.version}.tgz";
    hash = "sha256-x1F/GQg93LBfJ2kEaA6ysRprXsq3eLjk5WhabWRbP2A=";
  };

  sourceRoot = "package";

  nativeBuildInputs = [ nodejs ];

  postUnpack = ''
    mkdir node-addon-api
    tar xzf ${nodeAddonApi} -C node-addon-api --strip-components=1
  '';

  # Build the Linux PTY addon from source as binding.gyp describes it, without
  # node-gyp, header downloads or the bundled macOS/Windows prebuilds.
  buildPhase = ''
    runHook preBuild
    mkdir -p build/Release
    $CXX -shared -fPIC -std=c++17 -O2 -pthread -Wall \
      -DNAPI_CPP_EXCEPTIONS -DNAPI_VERSION=8 \
      -I${nodejs}/include/node -I../node-addon-api \
      src/unix/pty.cc -lutil \
      -o build/Release/pty.node
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    dest=$out/lib/node_modules/node-pty
    mkdir -p $dest/build/Release
    cp -r lib typings package.json LICENSE README.md $dest/
    cp build/Release/pty.node $dest/build/Release/
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    NODE_PATH=$out/lib/node_modules ${lib.getExe nodejs} -e '
      const pty = require("node-pty");
      const term = pty.spawn("${stdenv.shell}", ["-c", "echo pty-ok $((6*7))"], { cols: 80, rows: 24 });
      let output = "";
      term.onData((data) => { output += data; });
      term.onExit(({ exitCode }) => {
        if (exitCode !== 0 || !output.includes("pty-ok 42")) {
          console.error("unexpected PTY result", exitCode, JSON.stringify(output));
          process.exit(1);
        }
        console.log("node-pty check passed");
      });
    '
    runHook postInstallCheck
  '';

  meta = {
    description = "Fork pseudoterminals in Node.js";
    homepage = "https://github.com/microsoft/node-pty";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
