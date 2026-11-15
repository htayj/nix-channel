{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  makeWrapper,
  nodejs,
}:

let
  # Upstream loads the renderer from a CDN and the arcade face from Google
  # Fonts.  The package serves these fixed copies itself.
  pixi = fetchurl {
    url = "https://registry.npmjs.org/pixi.js/-/pixi.js-8.2.6.tgz";
    hash = "sha256-ErMjzitkPCkPPEswz95EMdDxvC/zaGkubpay9aCrvg0=";
  };
  pressStart2P = fetchurl {
    name = "PressStart2P-v16.ttf";
    url = "https://fonts.gstatic.com/s/pressstart2p/v16/e3t4euO8T-267oIAQAu6jDQyK0nS.ttf";
    hash = "sha256-e5ObgW+M4YXdjCxZ6F+wXT3NXN4MCw3koWUcta+cLCs=";
  };
  # The licence text Google Fonts ships beside that face.
  pressStart2PLicense = fetchurl {
    name = "PressStart2P-OFL.txt";
    url = "https://raw.githubusercontent.com/google/fonts/23e54b51ddffbc7713c583748e3bd86f62b1fa4a/ofl/pressstart2p/OFL.txt";
    hash = "sha256-cFlgwygaV2XswLWb1O18pZ7tFldIB2vC/D6P2/65RLA=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "trial-by-combat";
  version = "0.1.0-unstable-2026-08-12";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "trial-by-combat";
    rev = "4263df6da017acfe3240288266de4a9400d904a4";
    hash = "sha256-5sr+Kwwn6nxrif0cZR3cU+8pJkkQM8zNcDykbCyNQMg=";
  };

  # Upstream's complete package-lock.json: 79 registry entries.  Nine are the
  # development-only Biome linter and its prebuilt platform binaries, which
  # are fetched with the rest but never installed.
  npmDepsHash = "sha256-KqGyMaXtkdrW6sNhihs2Srgx0At5RkzvsHcIOxJKggo=";
  npmInstallFlags = [ "--omit=dev" ];

  nativeBuildInputs = [ makeWrapper ];

  # Plain JavaScript with no build script: the build only places the renderer
  # and the face beside the other client assets and points the page at them.
  buildPhase = ''
    runHook preBuild

    mkdir pixi
    tar -xzf ${pixi} -C pixi --strip-components=1 package/dist/pixi.min.js package/LICENSE
    install -Dm444 pixi/dist/pixi.min.js public/vendor/pixi.min.js
    install -Dm444 pixi/LICENSE public/vendor/pixi.js-LICENSE
    install -Dm444 ${pressStart2P} public/vendor/PressStart2P-v16.ttf
    install -Dm444 ${pressStart2PLicense} public/vendor/PressStart2P-OFL.txt
    rm -r pixi

    substituteInPlace public/index.html --replace-fail \
      'https://cdn.jsdelivr.net/npm/pixi.js@8.2.6/dist/pixi.min.js' \
      '/client/vendor/pixi.min.js'
    substituteInPlace public/styles.css --replace-fail \
      '@import url("https://fonts.googleapis.com/css2?family=Press+Start+2P&display=swap");' \
      '@font-face { font-family: "Press Start 2P"; font-style: normal; font-weight: 400; font-display: swap; src: url("/client/vendor/PressStart2P-v16.ttf") format("truetype"); }'

    runHook postBuild
  '';

  doCheck = true;
  # The suite must not append a match log to the tree that is installed.
  checkPhase = ''
    runHook preCheck
    TBC_MATCH_LOG=0 npm test
    runHook postCheck
  '';

  # An application, not an npm module: install the server, its client assets
  # and the locked runtime modules, and a launcher for the server.
  installPhase = ''
    runHook preInstall

    module=$out/lib/node_modules/trial-by-combat
    mkdir -p "$module"
    cp -r node_modules public src package.json package-lock.json LICENSE "$module"

    install -Dm444 -t $out/share/doc/trial-by-combat README.md LICENSE \
      public/vendor/pixi.js-LICENSE public/vendor/PressStart2P-OFL.txt

    # The default match log sits beside the server, in the read-only store.
    makeWrapper ${lib.getExe nodejs} $out/bin/trial-by-combat \
      --add-flags "$module/src/server.js" \
      --set-default TBC_MATCH_LOG 0

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node ${./check-host.mjs} $out/bin/trial-by-combat
    runHook postInstallCheck
  '';

  meta = {
    description = "Tactical browser arena served over HTTP and WebSocket";
    longDescription = ''
      Trial by Combat is a turn-based tactical arena.  A Node server hosts the
      match engine, an HTTP player API, and a WebSocket feed for the spectator
      and admin consoles; browsers render the board with Pixi.js.  The server
      listens on port 4178 unless PORT is set.  The renderer and the arcade
      typeface are served from the package, not from a CDN.  Match logging is
      off by default; set TBC_MATCH_LOG=1 and TBC_MATCH_LOG_FILE to a writable
      file to enable it.
    '';
    homepage = "https://github.com/kunchenguid/trial-by-combat";
    # The program and Pixi.js are MIT; the installed modules add ISC and
    # BSD-3-Clause, and the typeface is OFL-1.1.
    license = with lib.licenses; [
      mit
      isc
      bsd3
      ofl
    ];
    mainProgram = "trial-by-combat";
    platforms = [ "x86_64-linux" ];
  };
})
