{
  lib,
  stdenv,
  fetchFromGitHub,
  applyPatches,
  runCommand,
  sbcl,
  SDL,
  coreutils,
  runtimeShell,
}:

let
  rev = "b771e2e0bbf0bbe08d50cb32124dc3903dc74cd4";
  # README and CHANGELOG say 2.0.2 while cotd.asd still says 1.0.5; name the
  # tree the way the Guix channel's git-version does.
  version = "2.0.2-0.${builtins.substring 0 7 rev}";

  upstream = fetchFromGitHub {
    owner = "gwathlobal";
    repo = "CotD";
    inherit rev;
    hash = "sha256-f/4gaz1UQOXMhsJ1xLW4seARXbP96Pd3vqGyjHnZJ3M=";
  };

  sdlLibDir = "${lib.getLib SDL}/lib";
  sdlLib = "${sdlLibDir}/libSDL-1.2.so.0";

  # Read-only artwork, faction descriptions and help.  A separate output so
  # the compiled source can name it without depending on the final package.
  assets = runCommand "cotd-assets-${version}" { } ''
    mkdir -p $out/share/cotd
    cp -r ${upstream}/src/data ${upstream}/src/help $out/share/cotd/
  '';
  assetDir = "${assets}/share/cotd";

  # Assets come from the store; options.cfg, saves, highscores, log.txt and
  # morgue/ stay relative to *CURRENT-DIR*, the launcher's state directory.
  # Patch the source itself; buildASDFSystem would otherwise run a top-level
  # postPatch on already patched source a second time.
  src = applyPatches {
    name = "cotd-src-${version}";
    src = upstream;
    postPatch = ''
      substituteInPlace src/file-storage.lisp \
        --replace-fail 'filename *current-dir*' 'filename #P"${assetDir}/"'
      substituteInPlace src/cotd.lisp \
        --replace-fail 'tiles-path *current-dir*' 'tiles-path #P"${assetDir}/"' \
        --replace-fail '"libSDL-1.2.so.0.7.2"' '"${sdlLib}"'
      rm -r src/data src/help
      # 19 upstream uses minus the three asset reads: the rest are state.
      count=$(grep -rF '*current-dir*' src --include='*.lisp' | wc -l)
      if [ "$count" != 16 ]; then
        echo "unexpected *current-dir* uses: $count" >&2
        exit 1
      fi
    '';
  };

  cotdSystem = sbcl.buildASDFSystem {
    pname = "cotd";
    inherit version src;
    lispLibs = with sbcl.pkgs; [
      lispbuilder-sdl
      bordeaux-threads
      defenum
      cl-store
      log4cl
    ];
  };

  # Every compiled Lisp system the game loads, and nothing from the user.
  lispClosure = map (entry: entry.drv) (builtins.genericClosure {
    startSet = [ { key = cotdSystem.outPath; drv = cotdSystem; } ];
    operator = entry:
      map (drv: { key = drv.outPath; inherit drv; }) (entry.drv.lispLibs or [ ]);
  });
  sourceRegistry = lib.concatMapStringsSep ":" (drv: "${drv}//") lispClosure;
in
stdenv.mkDerivation {
  pname = "cotd";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # Load the compiled ASDF system at launch; no core is saved.  The game keeps
  # its mutable files in the working directory, so the launcher enters the
  # state directory first.  LD_LIBRARY_PATH lets lispbuilder-sdl-cffi find
  # libSDL by soname; cotd itself uses the absolute path.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/doc/cotd \
      ${upstream}/LICENSE ${upstream}/README.md ${upstream}/CHANGELOG.txt \
      ${upstream}/COMPILING.txt ${upstream}/COMPILE-DEPENDECIES.txt
    mkdir -p $out/share $out/bin
    ln -s ${assetDir} $out/share/cotd
    cat > $out/bin/cotd <<'EOF'
    #!@runtimeShell@
    set -eu
    umask 077
    if [ "$#" -ne 0 ]; then
      echo 'Usage: cotd' >&2
      exit 2
    fi
    state="''${XDG_STATE_HOME:-''${HOME:?HOME or XDG_STATE_HOME required}/.local/state}/cotd"
    @mkdir@ -p -- "$state"
    cd -- "$state"
    export CL_SOURCE_REGISTRY="@sourceRegistry@"
    export ASDF_OUTPUT_TRANSLATIONS="@storeDir@:@storeDir@"
    export LD_LIBRARY_PATH="@sdlLibDir@''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec @sbcl@ --noinform --no-userinit --no-sysinit --non-interactive \
      --eval '(require :asdf)' \
      --eval '(asdf:load-system :cotd)' \
      --eval '(cotd::cotd-exec)'
    EOF
    substituteInPlace $out/bin/cotd \
      --subst-var-by runtimeShell ${runtimeShell} \
      --subst-var-by mkdir ${coreutils}/bin/mkdir \
      --subst-var-by sourceRegistry ${lib.escapeShellArg sourceRegistry} \
      --subst-var-by storeDir ${builtins.storeDir} \
      --subst-var-by sdlLibDir ${sdlLibDir} \
      --subst-var-by sbcl ${sbcl}/bin/sbcl
    chmod 555 $out/bin/cotd
    runHook postInstall
  '';

  # Never initialises SDL, opens a window or starts the game.  Checks the
  # launcher's usage, state directory and environment with a stub SBCL, then
  # loads the compiled system with the launcher's isolated ASDF settings and
  # reads packaged text, with HOME and every XDG base directory under TMPDIR.
  # Gameplay, rendering and save/load are not exercised.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export LC_ALL=C SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
    unset CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS XDG_CONFIG_DIRS XDG_DATA_DIRS \
      DISPLAY WAYLAND_DISPLAY

    base=$TMPDIR/cotd-check
    export HOME=$base/home XDG_CONFIG_HOME=$base/config XDG_CACHE_HOME=$base/cache \
      XDG_DATA_HOME=$base/data XDG_STATE_HOME=$base/state XDG_RUNTIME_DIR=$base/runtime
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" \
      "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$base/cwd"
    chmod 700 "$XDG_RUNTIME_DIR"
    # An invalid user ASDF configuration: reading it would signal an error.
    mkdir -p "$XDG_CONFIG_HOME/common-lisp/source-registry.conf.d"
    echo '(:not-a-directive)' > "$XDG_CONFIG_HOME/common-lisp/source-registry.conf.d/decoy.conf"
    snapshot() { find "$base" | sort; }
    snapshot > "$TMPDIR/before"

    bash -n $out/bin/cotd
    for args in --help "x y"; do
      status=0
      $out/bin/cotd $args 2> "$TMPDIR/usage" || status=$?
      test "$status" = 2
      grep -qxF 'Usage: cotd' "$TMPDIR/usage"
    done
    test ! -e "$XDG_STATE_HOME/cotd"

    test -s $out/share/cotd/data/font_large.bmp
    test -s $out/share/cotd/data/descriptions/church.txt
    for f in overview keybindings campaign_keybindings concept_combat \
             concept_environment concept_gods credits; do
      test -s $out/share/cotd/help/$f.txt
    done
    for f in LICENSE README.md CHANGELOG.txt COMPILING.txt COMPILE-DEPENDECIES.txt; do
      test -s $out/share/doc/cotd/$f
    done
    test "$(grep -cF 'filename #P"${assetDir}/"' ${cotdSystem}/src/file-storage.lisp)" = 1
    test "$(grep -cF 'tiles-path #P"${assetDir}/"' ${cotdSystem}/src/cotd.lisp)" = 2
    test "$(grep -cF '"${sdlLib}"' ${cotdSystem}/src/cotd.lisp)" = 2
    test ! -e ${cotdSystem}/src/data
    test ! -e ${cotdSystem}/src/help

    cat > "$TMPDIR/check.lisp" <<'EOF'
    (require :asdf)
    (asdf:load-system :cotd)
    (defun expect (ok what)
      (unless ok
        (format *error-output* "cotd check failed: ~a~%" what)
        (uiop:quit 1)))
    (dolist (file '("help/overview.txt" "help/keybindings.txt"
                    "data/descriptions/church.txt"))
      (let ((text (cotd::get-txt-from-file file)))
        (expect (and text (plusp (length text))) file)))
    ;; dlopen only; SDL_Init is never called.
    (cffi:load-foreign-library (uiop:getenv "EXPECT_SDL"))
    (expect (cffi:foreign-symbol-pointer "SDL_Init") "SDL_Init resolves")
    (format t "COTD_CHECK_OK~%")
    EOF
    (cd "$base/cwd" && env CL_SOURCE_REGISTRY=${lib.escapeShellArg sourceRegistry} \
      ASDF_OUTPUT_TRANSLATIONS=${builtins.storeDir}:${builtins.storeDir} \
      LD_LIBRARY_PATH=${sdlLibDir} EXPECT_SDL=${sdlLib} \
      ${sbcl}/bin/sbcl --noinform --non-interactive --no-userinit --no-sysinit \
        --load "$TMPDIR/check.lisp" > "$TMPDIR/check.out")
    grep -qxF COTD_CHECK_OK "$TMPDIR/check.out"
    snapshot > "$TMPDIR/after"
    cmp "$TMPDIR/before" "$TMPDIR/after"

    # The launcher with a stub SBCL: state directory, umask and arguments.
    cat > "$TMPDIR/fake-sbcl" <<EOF
    #!${runtimeShell}
    { pwd -P; umask; printf '%s\n' "\$@"; echo "\$CL_SOURCE_REGISTRY"
      echo "\$ASDF_OUTPUT_TRANSLATIONS"; echo "\$LD_LIBRARY_PATH"; } > "\$PROBE_OUT"
    EOF
    chmod +x "$TMPDIR/fake-sbcl"
    sed "s|${sbcl}/bin/sbcl|$TMPDIR/fake-sbcl|" $out/bin/cotd > "$TMPDIR/cotd-probe"
    chmod +x "$TMPDIR/cotd-probe"
    grep -qF "$TMPDIR/fake-sbcl" "$TMPDIR/cotd-probe"

    PROBE_OUT=$TMPDIR/p1 "$TMPDIR/cotd-probe"
    test "$(sed -n 1p "$TMPDIR/p1")" = "$(cd "$XDG_STATE_HOME" && pwd -P)/cotd"
    test "$(sed -n 2p "$TMPDIR/p1")" = 0077
    test "$(stat -c %a "$XDG_STATE_HOME/cotd")" = 700
    grep -qxF -- --no-userinit "$TMPDIR/p1"
    grep -qxF -- --no-sysinit "$TMPDIR/p1"
    grep -qxF '(cotd::cotd-exec)' "$TMPDIR/p1"
    grep -qxF ${lib.escapeShellArg sourceRegistry} "$TMPDIR/p1"
    grep -qxF "${builtins.storeDir}:${builtins.storeDir}" "$TMPDIR/p1"
    grep -qxF ${sdlLibDir} "$TMPDIR/p1"

    (unset XDG_STATE_HOME; PROBE_OUT=$TMPDIR/p2 "$TMPDIR/cotd-probe")
    test "$(sed -n 1p "$TMPDIR/p2")" = "$(cd "$HOME" && pwd -P)/.local/state/cotd"

    status=0
    (unset XDG_STATE_HOME HOME; PROBE_OUT=$TMPDIR/p3 "$TMPDIR/cotd-probe") 2>/dev/null || status=$?
    test "$status" != 0
    test ! -e "$TMPDIR/p3"
    test -z "$(find "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR" "$base/cwd" -mindepth 1 -print -quit)"
    runHook postInstallCheck
  '';

  passthru = { inherit cotdSystem assets src; };

  meta = {
    description = "SDL roguelike battle of angels and demons in a human city";
    longDescription = ''
      City of the Damned is the original Common Lisp roguelike with an SDL
      interface: custom scenarios or a strategic campaign as an angel, demon,
      soldier or another faction.  Artwork and help are read from
      share/cotd.  Options, saved games, high scores, log.txt and morgue/ live
      in XDG_STATE_HOME/cotd, falling back to ~/.local/state/cotd.
    '';
    homepage = "https://github.com/gwathlobal/CotD";
    # LICENSE is the GPL v3 text; no source file grants "or later".
    license = lib.licenses.gpl3Only;
    mainProgram = "cotd";
    platforms = [ "x86_64-linux" ];
  };
}
