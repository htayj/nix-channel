{ lib
, stdenvNoCC
, buildGoModule
, fetchFromGitHub
, fetchurl
, nodejs
, runtimeShell
, curl
}:

let
  version = "0-unstable-2026-07-13";

  src = fetchFromGitHub {
    owner = "htayj";
    repo = "flaghack";
    rev = "772c47e77c952eaa96c627079683768533c0ce93";
    hash = "sha256-uWK3XKFPnX8kZ9z6RKM3xue6EHQ09eDVTmt02TqST4s=";
  };

  # The terminal client is a Go module inside the same repository.
  client = buildGoModule {
    pname = "flaghack-charm";
    inherit version src;
    modRoot = "packages/cli/charm";
    vendorHash = "sha256-uwBJAqN4sIepiiJf9lCDumLqfKJEowQO2tOiSWD3Fig=";
    subPackages = [ "." ];
    postInstall = ''
      mv $out/bin/charm $out/bin/flaghack
    '';
  };

  # The server's production npm closure as resolved by upstream's pnpm lock:
  # registry tarballs unpacked at `path` below node_modules.  pnpm itself is
  # not run; pinned nixpkgs has no pnpm that accepts the lock unchanged.
  npmSources = lib.importJSON ./npm-sources.json;
  unpackNpmSource = entry: ''
    mkdir -p "$site/node_modules/${entry.path}"
    tar -xzf ${fetchurl { inherit (entry) url sha256; }} \
      -C "$site/node_modules/${entry.path}" --strip-components=1
  '';
in
stdenvNoCC.mkDerivation {
  pname = "flaghack";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  # node_modules carries prebuilt optional addons and the esbuild binary.
  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = true;

  installPhase = ''
    runHook preInstall

    site=$out/share/flaghack
    mkdir -p "$site/packages" "$out/bin" "$out/share/doc/flaghack"

    # tsx resolves @flaghack/domain through the paths of the root tsconfig.
    cp package.json tsconfig.json tsconfig.base.json "$site/"
    cp -r packages/domain packages/server "$site/packages/"

    ${lib.concatMapStrings unpackNpmSource npmSources}
    chmod -R u+w "$site/node_modules"

    cp ${client}/bin/flaghack "$out/bin/flaghack"

    cat > "$out/bin/flaghack-server" <<EOF
    #!${runtimeShell}
    cd $site
    exec ${nodejs}/bin/node --import $site/node_modules/tsx/dist/loader.mjs packages/server/src/server.ts "\$@"
    EOF
    chmod +x "$out/bin/flaghack-server"

    cp LICENSE "$out/share/doc/flaghack/LICENSE"
    cp packages/domain/LICENSE "$out/share/doc/flaghack/domain-LICENSE"
    cp packages/server/LICENSE "$out/share/doc/flaghack/server-LICENSE"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ curl ];
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    export FLAGHACK_PORT=38817
    export FLAGHACK_SAVE_PATH=$TMPDIR/state/save.json

    "$out/bin/flaghack-server" > server.log 2>&1 &
    server=$!

    ready=
    for attempt in $(seq 1 60); do
      if ! kill -0 "$server" 2>/dev/null; then
        cat server.log
        echo "flaghack-server exited before answering"
        exit 1
      fi
      if curl -fsS --max-time 2 -o client-state.json http://127.0.0.1:38817/client-state 2>/dev/null; then
        ready=1
        break
      fi
      sleep 0.5
    done
    if [ -z "$ready" ]; then
      cat server.log
      echo "flaghack-server did not answer within 30 seconds"
      exit 1
    fi

    # A fresh game starts at role selection.
    if ! grep -q selectRole client-state.json; then
      cat client-state.json server.log
      exit 1
    fi
    curl -fsS --max-time 5 -o world.json http://127.0.0.1:38817/world

    kill -TERM "$server"
    if ! wait "$server"; then
      cat server.log
      echo "flaghack-server did not shut down cleanly"
      exit 1
    fi
    echo "flaghack server smoke ok: $(head -c 120 client-state.json)"

    runHook postInstallCheck
  '';

  meta = {
    description = "Flag Hack roguelike: terminal client and local HTTP game server";
    longDescription = ''
      `flaghack` is the terminal client; it talks to a running
      `flaghack-server` at FLAGHACK_API_URL (default http://127.0.0.1:3000).
      The server listens on FLAGHACK_PORT or PORT (default 3000) and keeps
      its save file at FLAGHACK_SAVE_PATH, else
      $XDG_STATE_HOME/flag-hack/save.json, else
      ~/.local/state/flag-hack/save.json.
    '';
    homepage = "https://github.com/htayj/flaghack";
    # Flag Hack is AGPL; the bundled npm closure is MIT and Apache-2.0.
    license = with lib.licenses; [ agpl3Plus mit asl20 ];
    sourceProvenance = with lib.sourceTypes; [ fromSource binaryNativeCode ];
    mainProgram = "flaghack";
    platforms = [ "x86_64-linux" ];
  };
}
