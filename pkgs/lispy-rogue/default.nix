{
  lib,
  stdenv,
  fetchFromGitHub,
  applyPatches,
  sbcl,
  runtimeShell,
}:

let
  version = "0.0.2";

  # Drop the installer artwork and the Quicklisp/download based packaging.
  # Patch the source itself; buildASDFSystem would otherwise run a top-level
  # postPatch on already patched source a second time.
  src = applyPatches {
    name = "lispy-rogue-src-${version}";
    src = fetchFromGitHub {
      owner = "lockie";
      repo = "lispy-rogue";
      rev = "b2249bf7fe05e4ae53468d0f8855fcf4f4057337";
      hash = "sha256-0GzYPPSQ/GI3ndWxGIr38WDFDWzMnD5iPCevEYfPmCU=";
    };
    postPatch = ''
      rm -r package .github package.sh
    '';
  };

  # Nixpkgs compiles only the base system.  The game also uses the
  # declarative interface from the same .asd, so compile both.  The Makefile
  # component would run make whenever the system is loaded; the library and
  # offsets are already built in old.src, so drop it.  Patch the source
  # itself, as below.
  nuklear = sbcl.pkgs.cl-liballegro-nuklear.overrideLispAttrs (old: {
    systems = [ "cl-liballegro-nuklear" "cl-liballegro-nuklear/declarative" ];
    lispLibs = old.lispLibs ++ [ sbcl.pkgs.alexandria ];
    src = applyPatches {
      name = "cl-liballegro-nuklear-src-${old.version}";
      inherit (old) src;
      postPatch = ''
        substituteInPlace cl-liballegro-nuklear.asd \
          --replace-fail '(:makefile "Makefile")' ""
      '';
    };
  });

  # Resources/ stays beside the compiled system: the game finds it with
  # ASDF:SYSTEM-RELATIVE-PATHNAME and reads everything from there.
  lispyRogueSystem = sbcl.buildASDFSystem {
    pname = "lispy-rogue";
    inherit version src;
    lispLibs = with sbcl.pkgs; [
      alexandria
      cl-astar
      cl-fast-ecs
      cl-liballegro
      nuklear
      cl-ppcre
      cl-tiled
      deploy
      float-features
      let-plus
      livesupport
    ];
  };

  # Every compiled Lisp system the game loads, and nothing from the user.
  lispClosure = map (entry: entry.drv) (builtins.genericClosure {
    startSet = [ { key = lispyRogueSystem.outPath; drv = lispyRogueSystem; } ];
    operator = entry:
      map (drv: { key = drv.outPath; inherit drv; }) (entry.drv.lispLibs or [ ]);
  });
  sourceRegistry = lib.concatMapStringsSep ":" (drv: "${drv}//") lispClosure;
  # Allegro and libffi, which the bindings open by soname.
  libraryPath = lib.makeLibraryPath
    (lib.unique (lib.concatMap (drv: drv.nativeLibs or [ ]) lispClosure));

  resources = "${lispyRogueSystem}/Resources";
in
stdenv.mkDerivation {
  pname = "lispy-rogue";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # Load the compiled ASDF systems at launch; no core is saved.  The game
  # keeps no saves or settings and writes nothing.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/doc/lispy-rogue ${src}/LICENSE ${src}/README.org
    # Explicit targets: a store path's basename carries its hash.
    install -Dm644 ${./notices.txt} $out/share/doc/lispy-rogue/ASSET-NOTICES
    install -Dm644 ${./Fantasque-OFL-1.1.txt} $out/share/doc/lispy-rogue/Fantasque-OFL-1.1.txt
    install -Dm644 ${./Inconsolata-OFL-1.1.txt} $out/share/doc/lispy-rogue/Inconsolata-OFL-1.1.txt
    mkdir -p $out/share/lispy-rogue $out/bin
    ln -s ${resources} $out/share/lispy-rogue/Resources
    cat > $out/bin/lispy-rogue <<'EOF'
    #!@runtimeShell@
    set -eu
    if [ "$#" -ne 0 ]; then
      echo 'Usage: lispy-rogue' >&2
      exit 2
    fi
    export CL_SOURCE_REGISTRY="@sourceRegistry@"
    export ASDF_OUTPUT_TRANSLATIONS="@storeDir@:@storeDir@"
    export LD_LIBRARY_PATH="@libraryPath@''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec @sbcl@ --noinform --no-userinit --no-sysinit --non-interactive \
      --eval '(require :asdf)' \
      --eval '(asdf:load-system :lispy-rogue)' \
      --eval '(lispy-rogue:main)'
    EOF
    substituteInPlace $out/bin/lispy-rogue \
      --subst-var-by runtimeShell ${runtimeShell} \
      --subst-var-by sourceRegistry ${lib.escapeShellArg sourceRegistry} \
      --subst-var-by storeDir ${builtins.storeDir} \
      --subst-var-by libraryPath ${libraryPath} \
      --subst-var-by sbcl ${sbcl}/bin/sbcl
    chmod 555 $out/bin/lispy-rogue
    runHook postInstall
  '';

  # Never opens a display or an audio device and never starts the game.
  # Checks the launcher's usage, that the assets match their notices, and
  # that the compiled systems load with the launcher's isolated settings and
  # an empty PATH, with both native libraries resolved and the tileset
  # parsed.  Rendering, input, audio and gameplay are not exercised.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export LC_ALL=C
    unset CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS XDG_CONFIG_DIRS XDG_DATA_DIRS \
      DISPLAY WAYLAND_DISPLAY

    base=$TMPDIR/lispy-rogue-check
    export HOME=$base/home XDG_CONFIG_HOME=$base/config XDG_CACHE_HOME=$base/cache \
      XDG_DATA_HOME=$base/data XDG_STATE_HOME=$base/state
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" \
      "$XDG_STATE_HOME" "$base/cwd"
    # An invalid user ASDF configuration: reading it would signal an error.
    mkdir -p "$XDG_CONFIG_HOME/common-lisp/source-registry.conf.d"
    echo '(:not-a-directive)' > "$XDG_CONFIG_HOME/common-lisp/source-registry.conf.d/decoy.conf"
    snapshot() { find "$base" | sort; }
    snapshot > "$TMPDIR/before"

    bash -n $out/bin/lispy-rogue
    for args in --help "x y"; do
      status=0
      $out/bin/lispy-rogue $args 2> "$TMPDIR/usage" || status=$?
      test "$status" = 2
      grep -qxF 'Usage: lispy-rogue' "$TMPDIR/usage"
    done

    for f in dungeon.ogg urizen-tileset.png fantasque-sans-mono.ttf inconsolata.ttf; do
      sum=$(sha256sum < $out/share/lispy-rogue/Resources/$f | cut -d' ' -f1)
      grep -qxF "  SHA-256: $sum" $out/share/doc/lispy-rogue/ASSET-NOTICES
    done
    test -s $out/share/lispy-rogue/Resources/urizen-tileset.tsx
    for f in LICENSE README.org ASSET-NOTICES Fantasque-OFL-1.1.txt Inconsolata-OFL-1.1.txt; do
      test -s $out/share/doc/lispy-rogue/$f
    done
    test ! -e ${lispyRogueSystem}/package
    test ! -e ${lispyRogueSystem}/package.sh
    test -s ${nuklear}/src/declarative.fasl
    test -s ${nuklear}/src/liballegro_nuklear.so
    ! grep -qF ':makefile "Makefile"' ${nuklear}/cl-liballegro-nuklear.asd

    cat > "$TMPDIR/check.lisp" <<'EOF'
    (require :asdf)
    (asdf:load-system :lispy-rogue)
    (defun expect (ok what)
      (unless ok
        (format *error-output* "lispy-rogue check failed: ~a~%" what)
        (uiop:quit 1)))
    (expect (fboundp 'lispy-rogue:main) "main is defined")
    (dolist (file '("dungeon.ogg" "inconsolata.ttf" "fantasque-sans-mono.ttf"
                    "urizen-tileset.png" "urizen-tileset.tsx"))
      (expect (probe-file (merge-pathnames file lispy-rogue::*resources-path*)) file))
    (expect (string= (namestring lispy-rogue::*resources-path*)
                     (uiop:getenv "EXPECT_RESOURCES"))
            "resources path")
    ;; dlopen only; Allegro is never initialised.
    (expect (cffi:foreign-symbol-pointer "al_install_system") "Allegro resolves")
    (expect (cffi:foreign-symbol-pointer "nk_allegro5_init") "Nuklear bridge resolves")
    (let ((tileset (cl-tiled:load-tileset
                    (merge-pathnames "urizen-tileset.tsx" lispy-rogue::*resources-path*))))
      (expect (plusp (length (cl-tiled:tileset-tiles tileset))) "tileset parses"))
    (format t "LISPY_ROGUE_CHECK_OK~%")
    EOF
    (cd "$base/cwd" && env PATH=/var/empty \
      CL_SOURCE_REGISTRY=${lib.escapeShellArg sourceRegistry} \
      ASDF_OUTPUT_TRANSLATIONS=${builtins.storeDir}:${builtins.storeDir} \
      LD_LIBRARY_PATH=${libraryPath} EXPECT_RESOURCES=${resources}/ \
      ${sbcl}/bin/sbcl --noinform --non-interactive --no-userinit --no-sysinit \
        --load "$TMPDIR/check.lisp" > "$TMPDIR/check.out")
    grep -qxF LISPY_ROGUE_CHECK_OK "$TMPDIR/check.out"
    snapshot > "$TMPDIR/after"
    cmp "$TMPDIR/before" "$TMPDIR/after"

    # The launcher with a stub SBCL: arguments and environment.
    cat > "$TMPDIR/fake-sbcl" <<EOF
    #!${runtimeShell}
    { printf '%s\n' "\$@"; echo "\$CL_SOURCE_REGISTRY"
      echo "\$ASDF_OUTPUT_TRANSLATIONS"; echo "\$LD_LIBRARY_PATH"; } > "\$PROBE_OUT"
    EOF
    chmod +x "$TMPDIR/fake-sbcl"
    sed "s|${sbcl}/bin/sbcl|$TMPDIR/fake-sbcl|" $out/bin/lispy-rogue > "$TMPDIR/probe"
    chmod +x "$TMPDIR/probe"
    grep -qF "$TMPDIR/fake-sbcl" "$TMPDIR/probe"
    (unset LD_LIBRARY_PATH; PROBE_OUT=$TMPDIR/p1 "$TMPDIR/probe")
    grep -qxF -- --no-userinit "$TMPDIR/p1"
    grep -qxF -- --no-sysinit "$TMPDIR/p1"
    grep -qxF '(lispy-rogue:main)' "$TMPDIR/p1"
    grep -qxF ${lib.escapeShellArg sourceRegistry} "$TMPDIR/p1"
    grep -qxF "${builtins.storeDir}:${builtins.storeDir}" "$TMPDIR/p1"
    grep -qxF ${libraryPath} "$TMPDIR/p1"
    runHook postInstallCheck
  '';

  passthru = { inherit lispyRogueSystem nuklear src; };

  meta = {
    description = "Graphical turn-based dungeon crawler written in Common Lisp";
    longDescription = ''
      Lispy Rogue is the Autumn Lisp Game Jam 2024 entry: explore randomly
      generated dungeon floors, fight monsters, collect equipment and descend
      to level eleven.  The game and its Allegro/Nuklear interface are built
      from source, with the bundled CC0 tiles and ambience and OFL fonts.  It
      needs a graphical display and an audio device, and keeps no saves.
    '';
    homepage = "https://github.com/lockie/lispy-rogue";
    # Game: MIT.  Tiles and ambience: CC0.  Fonts: OFL 1.1.
    license = with lib.licenses; [ mit cc0 ofl ];
    mainProgram = "lispy-rogue";
    platforms = [ "x86_64-linux" ];
  };
}
