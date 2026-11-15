{
  lib,
  stdenv,
  fetchFromGitHub,
  ocaml-ng,
  SDL_compat,
  libGL,
  mesa,
  coreutils,
  runtimeShell,
  xvfb,
  xdotool,
}:

let
  # The bundled SDL and OpenGL stubs use the C names OCaml 5 removed (alloc,
  # failwith, copy_string); 4.14 is the last series that provides them.
  inherit (ocaml-ng.ocamlPackages_4_14) ocaml;
in
stdenv.mkDerivation {
  pname = "wanderers";
  # Upstream has no releases or tags; this is the last master commit.
  version = "0-unstable-2019-01-05";

  src = fetchFromGitHub {
    owner = "a-nikolaev";
    repo = "wanderers";
    rev = "054c1cdc6dd833d8938357e6d898def510531d67";
    hash = "sha256-jmH9uAkRMJQluu2Yp0mbYOXVcvvkxXpZlcRhwy1IAK8=";
  };

  strictDeps = true;
  nativeBuildInputs = [ ocaml ];
  buildInputs = [ SDL_compat libGL ];

  # GLCaml opens the OpenGL library by soname at start.
  postPatch = ''
    substituteInPlace lib/glcaml_stub.c \
      --replace-fail 'dlopen("libGL.so.1"' 'dlopen("${libGL}/lib/libGL.so.1"'
  '';

  dontConfigure = true;

  # Upstream's native-code target.  Its LIBS also names graphics, which only
  # the unused non-SDL window backend needs.
  buildPhase = ''
    runHook preBuild
    make -f makefile.inc nc LIBS='unix str bigarray'
    runHook postBuild
  '';

  # The game reads data/ and reads and writes game.save in its working
  # directory, so the launcher runs it in a per-user directory that links to
  # the installed data.
  installPhase = ''
    runHook preInstall
    install -Dm755 wanderers $out/libexec/wanderers
    mkdir -p $out/share/wanderers $out/bin
    cp -r data $out/share/wanderers/data
    doc=$out/share/doc/wanderers
    install -Dm644 -t $doc COPYING README.markdown
    # The linked bindings carry their own licence notices.
    install -Dm644 -t $doc/lib lib/sdl.ml lib/sdl.mli lib/sdl_stub.c \
      lib/glcaml.ml lib/glcaml.mli lib/glcaml_stub.c
    cat > $out/bin/wanderers <<EOF
    #!${runtimeShell}
    set -eu
    state="\''${XDG_DATA_HOME:-\''${HOME:?}/.local/share}/wanderers"
    ${coreutils}/bin/mkdir -p "\$state"
    cd "\$state"
    # Follow the installed data across upgrades; keep a directory the user put there.
    if [ -L data ] || [ ! -e data ]; then
      ${coreutils}/bin/ln -sfn $out/share/wanderers/data data
    fi
    exec $out/libexec/wanderers "\$@"
    EOF
    chmod 755 $out/bin/wanderers
    runHook postInstall
  '';

  # Play headless: start a seeded game, save and quit with Ctrl+q, then load
  # that save and quit again.  Mesa supplies software GLX to Xvfb and the game.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ xvfb xdotool ];
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home XDG_DATA_HOME=$TMPDIR/data XDG_RUNTIME_DIR=$TMPDIR/run
    export SDL_AUDIODRIVER=dummy
    export LD_LIBRARY_PATH=${mesa}/lib LIBGL_DRIVERS_PATH=${mesa}/lib/dri
    mkdir -p "$HOME"
    mkdir -m 700 "$XDG_RUNTIME_DIR"
    Xvfb -displayfd 3 -nolisten tcp -screen 0 1280x1024x24 3> $TMPDIR/display &
    xvfb=$!
    for _ in $(seq 100); do [ -s $TMPDIR/display ] && break; sleep 0.1; done
    export DISPLAY=:$(cat $TMPDIR/display)
    save=$XDG_DATA_HOME/wanderers/game.save
    for seed in check-seed ""; do
      $out/bin/wanderers $seed &
      game=$!
      for _ in $(seq 300); do
        xdotool search --name '^Wanderers$' > /dev/null 2>&1 && break
        kill -0 $game
        sleep 0.2
      done
      sleep 3
      xdotool key ctrl+q
      timeout 60 tail --pid=$game -f /dev/null
      wait $game
      test -s $save
    done
    test "$(readlink $XDG_DATA_HOME/wanderers/data)" = $out/share/wanderers/data
    kill $xvfb
    runHook postInstallCheck
  '';

  meta = {
    description = "Open-world adventure and dungeon-crawling game";
    longDescription = ''
      Wanderers is a graphical roguelike with semi-continuous time: discrete
      actions are simulated in continuous space, so combat involves pushing
      and dodging.  The surroundings of the player are simulated in detail
      and the rest of the world at a coarser scale.

      Run wanderers to continue the saved game or start a new one, wanderers
      SEED to start a new game from a seed, and wanderers '?' for a random
      seed.  Ctrl+q saves and quits.  The saved game is
      $XDG_DATA_HOME/wanderers/game.save, falling back to
      ~/.local/share/wanderers.
    '';
    homepage = "https://github.com/a-nikolaev/wanderers";
    # The game and its data are GPL-3.0-or-later; the bundled GLCaml binding
    # is BSD-3-Clause and the bundled SDL binding LGPL-2.0-only.
    license = with lib.licenses; [ gpl3Plus bsd3 lgpl2Only ];
    mainProgram = "wanderers";
    platforms = [ "x86_64-linux" ];
  };
}
