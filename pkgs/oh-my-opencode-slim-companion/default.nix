{ lib
, rustPlatform
, fetchFromGitHub
, patchelf
, libGL
, libx11
, libxcb
, libxcursor
, libxi
, libxkbcommon
, libxrandr
, wayland
}:

let
  # winit and glutin load the display and GL libraries by soname at run time,
  # so they are absent from DT_NEEDED and have to be on the RUNPATH.
  runtimeLibraries = [
    libGL
    libx11
    libxcb
    libxcursor
    libxi
    libxkbcommon
    libxrandr
    wayland
  ];
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "oh-my-opencode-slim-companion";
  version = "0.1.3";

  # The commit the upstream release workflow built companion-v0.1.3 from.
  src = fetchFromGitHub {
    owner = "alvinunreal";
    repo = "oh-my-opencode-slim";
    rev = "5a4a81a647572141b1be20f72c0948c4601ac4ce";
    hash = "sha256-6oipgsVSoOxLD51MpwCzcjIQrVz30YsEUXE6EwedhS4=";
  };
  sourceRoot = "${finalAttrs.src.name}/companion";

  # Upstream's Cargo.lock has only crates.io dependencies; build the locked graph.
  cargoHash = "sha256-M6Axt2QLnD5ci5uKugXiM144YfjpOMxyYvZlH4YHQPg=";
  cargoBuildFlags = [ "--locked" ];
  cargoTestFlags = [ "--locked" ];

  nativeBuildInputs = [ patchelf ];

  postInstall = ''
    doc=$out/share/doc/oh-my-opencode-slim-companion
    install -Dm644 ../LICENSE ../docs/companion.md -t $doc

    # Keep the notices of the statically linked Rust crates.
    for crate in ${finalAttrs.cargoDeps}/source-registry-0/*/; do
      name=$(basename "$crate")
      for file in "$crate"*; do
        [ -f "$file" ] || continue
        base=$(basename "$file")
        case "''${base,,}" in
          license|license[-.]*|licence|licence[-.]*|copying|copying[-.]*|copyright|copyright[-.]*|notice|notice[-.]*|unlicense|unlicense[-.]*)
            install -Dm644 "$file" -t "$doc/third-party-licenses/$name"
            ;;
        esac
      done
    done
  '';

  # Runs after the fixup phase has shrunk the RUNPATH to DT_NEEDED entries.
  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath runtimeLibraries} \
      $out/bin/oh-my-opencode-slim-companion
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    program=$out/bin/oh-my-opencode-slim-companion

    # Without a session id the companion logs the reason and exits before
    # opening a window.
    export HOME=$TMPDIR/home XDG_DATA_HOME=$TMPDIR/data
    mkdir -p $HOME
    env -u OH_MY_OPENCODE_SLIM_COMPANION_SESSION_ID \
      OH_MY_OPENCODE_SLIM_COMPANION_DEBUG=1 $program
    grep -q 'exit missing owner_session_id' \
      $XDG_DATA_HOME/opencode/log/oh-my-opencode-slim-companion.*.log

    IFS=: read -ra runpath <<< "$(patchelf --print-rpath $program)"
    for soname in libwayland-client.so.0 libxkbcommon.so.0 libxkbcommon-x11.so.0 \
                  libX11.so.6 libX11-xcb.so.1 libXcursor.so.1 libXi.so.6 \
                  libXrandr.so.2 libxcb.so.1 libEGL.so.1 libGL.so.1; do
      found=
      for dir in "''${runpath[@]}"; do
        if [ -e "$dir/$soname" ]; then found=$dir; fi
      done
      if [ -z "$found" ]; then
        echo "$soname is not on the RUNPATH of $program" >&2
        exit 1
      fi
    done

    test -f $out/share/doc/oh-my-opencode-slim-companion/LICENSE
    test -n "$(ls $out/share/doc/oh-my-opencode-slim-companion/third-party-licenses)"
    runHook postInstallCheck
  '';

  meta = {
    description = "Animated desktop companion for oh-my-opencode-slim OpenCode sessions";
    longDescription = ''
      The companion is a small always-on-top eframe/egui window that plays the
      embedded animation of the agent active in an OpenCode session.  The
      oh-my-opencode-slim plugin starts it with
      OH_MY_OPENCODE_SLIM_COMPANION_SESSION_ID set; point the plugin's
      companion.binaryPath setting at this package's executable.  It reads
      $XDG_DATA_HOME/opencode/storage/oh-my-opencode-slim/companion-state.json
      and needs a Wayland or X11 session.  Window placement under niri uses the
      niri command from PATH.
    '';
    homepage = "https://github.com/alvinunreal/oh-my-opencode-slim";
    license = lib.licenses.mit;
    mainProgram = "oh-my-opencode-slim-companion";
    platforms = [ "x86_64-linux" ];
  };
})
