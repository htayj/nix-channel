{
  lib,
  stdenv,
  fetchurl,
  nodejs,
  cmake,
  ninja,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "koffi";
  version = "3.1.2";

  # The npm release ships the C++ sources, the vendored Node-API headers and
  # the cnoke CMake driver; the platform prebuilds live in separate packages.
  src = fetchurl {
    url = "https://registry.npmjs.org/koffi/-/koffi-${finalAttrs.version}.tgz";
    hash = "sha256-/XFMKNoX1EIA8FLArv8EByhbnPsQ/rYfQ6W9o8J5Zcg=";
  };

  sourceRoot = "package";

  nativeBuildInputs = [
    nodejs
    cmake
    ninja
  ];

  # cnoke drives CMake itself.
  dontUseCmakeConfigure = true;
  dontUseNinjaBuild = true;
  dontUseNinjaInstall = true;
  dontUseNinjaCheck = true;

  # Build the addon from source; --prebuild is omitted so nothing is fetched.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    node cnoke.cjs -P . -D src/koffi --release
    # The versioned CMake work tree is build-only.
    find build/koffi -mindepth 2 -maxdepth 2 -type d -name 'v*_native' -exec rm -rf {} +
    runHook postBuild
  '';

  # Ship the JavaScript loader and the compiled addon; the C++ sources and
  # vendored headers are build-only.
  installPhase = ''
    runHook preInstall
    dest=$out/lib/node_modules/koffi
    mkdir -p $dest/src/koffi/src
    cp -r build package.json index.cjs index.js index.d.ts indirect.cjs indirect.js \
      LICENSE.txt README.md $dest/
    cp src/koffi/*.cjs src/koffi/*.js $dest/src/koffi/
    cp src/koffi/src/*.cjs src/koffi/src/*.js $dest/src/koffi/src/
    runHook postInstall
  '';

  doInstallCheck = true;
  # Run outside the source tree so require() resolves the installed copy.
  installCheckPhase = ''
    runHook preInstallCheck
    mkdir -p $TMPDIR/check && cd $TMPDIR/check
    NODE_PATH=$out/lib/node_modules ${lib.getExe nodejs} -e '
      const koffi = require("koffi");
      const libc = koffi.load("libc.so.6");
      const strlen = libc.func("size_t strlen(const char *str)");
      const getpid = libc.func("int getpid()");
      if (strlen("koffi-check") !== 11 || getpid() !== process.pid) {
        console.error("unexpected FFI result");
        process.exit(1);
      }
      console.log("koffi check passed");
    '
    runHook postInstallCheck
  '';

  meta = {
    description = "Fast and easy-to-use C foreign function interface for Node.js";
    homepage = "https://koffi.dev/";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
