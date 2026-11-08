{
  lib,
  stdenv,
  fetchurl,
  applyPatches,
  unzip,
  sbcl,
  ncurses,
  coreutils,
  runtimeShell,
  util-linux,
}:

let
  version = "1.0";

  # Bind the commands documented by the game instead of shipping controls.cfg,
  # which has no explicit redistribution grant.  These are the Guix channel's
  # bindings.  The block closes INIT-CONTROLS like the :ERROR)) it replaces.
  defaultControls = lib.concatStringsSep "\r\n" [
    "    (progn"
    "      (control-bind (make-instance 'move-to :dx 1 :dy 0) 261 54)"
    "      (control-bind (make-instance 'move-to :dx -1 :dy 0) 260 52)"
    "      (control-bind (make-instance 'move-to :dx 0 :dy -1) 259 56)"
    "      (control-bind (make-instance 'move-to :dx 0 :dy 1) 258 50)"
    "      (control-bind (make-instance 'move-to :dx 1 :dy 1) 51)"
    "      (control-bind (make-instance 'move-to :dx -1 :dy 1) 49)"
    "      (control-bind (make-instance 'move-to :dx 1 :dy -1) 57)"
    "      (control-bind (make-instance 'move-to :dx -1 :dy -1) 55)"
    "      (control-bind (make-instance 'wait) 53 46)"
    "      (control-bind (make-instance 'quit-game) 81)"
    "      (control-bind (make-instance 'next-message) 32)"
    "      (control-bind (make-instance 'recap) 8 263)"
    "      (control-bind (make-instance 'look-around) 108 120)"
    "      (control-bind (make-instance 'open-door-smart) 111)"
    "      (control-bind (make-instance 'close-door-smart) 99)"
    "      (control-bind (make-instance 'save-game) 83)"
    "      (control-bind (make-instance 'descend) 62 43)"
    "      (control-bind (make-instance 'ascend) 60 45)"
    "      (control-bind (make-instance 'get-item-on-spot) 44 103)"
    "      (control-bind (make-instance 'drop-item-menu) 100)"
    "      (control-bind (make-instance 'show-inventory) 105)"
    "      (control-bind (make-instance 'show-equipment) 101)"
    "      (control-bind (make-instance 'use-item-menu) 117)"
    "      nil)))"
  ];

  # The end of INIT-CONTROLS: the controls.cfg branch, then the :ERROR
  # fallback.  Anchoring on both CRLF lines leaves LOAD-HISCORE's :ERROR alone.
  controlsFallback = "      nil)\r\n    :error))\r\n";

  # Patch the source itself; buildASDFSystem would otherwise run a top-level
  # postPatch on already patched source a second time.
  src = applyPatches {
    name = "sewers-src-${version}";
    src = fetchurl {
      url = "http://common-lisp.net/project/lifp/sewers-src.zip";
      hash = "sha256-gXvlce21YsCoCEVb4gGehbQEtoS0Hn63sOxuQeOYIGY=";
    };
    nativeBuildInputs = [ unzip ];
    postPatch = ''
      rm readme.txt controls.cfg
      substituteInPlace curses.lisp \
        --replace-fail '"libncurses.so.5"' '"${lib.getLib ncurses}/lib/libncurses.so.6"'
      substituteInPlace r2.lisp \
        --replace-fail ${lib.escapeShellArg controlsFallback} \
          ${lib.escapeShellArg "      nil)\r\n${defaultControls}\r\n"}
    '';
  };

  sewers = sbcl.buildASDFSystem {
    pname = "sewers";
    inherit version src;
    lispLibs = with sbcl.pkgs; [ cffi cl-store md5 trivial-gray-streams ];
  };

  # Every compiled Lisp system the game loads, and nothing from the user.
  lispClosure = map (entry: entry.drv) (builtins.genericClosure {
    startSet = [ { key = sewers.outPath; drv = sewers; } ];
    operator = entry:
      map (drv: { key = drv.outPath; inherit drv; }) (entry.drv.lispLibs or [ ]);
  });
  sourceRegistry = lib.concatMapStringsSep ":" (drv: "${drv}//") lispClosure;
in
stdenv.mkDerivation {
  pname = "sewer-massacre";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeInstallCheckInputs = [ coreutils util-linux ];

  # Load the compiled ASDF systems at launch; no core is saved.  The game reads
  # and writes current.sav, hiscore and morgue.txt in its working directory, so
  # the launcher enters the state directory first.
  installPhase = ''
    runHook preInstall
    install -Dm644 ${./sewer-massacre-entry.lisp} \
      $out/libexec/sewer-massacre/sewer-massacre.lisp
    install -Dm644 -t $out/share/doc/sewer-massacre \
      ${src}/license.txt ${src}/GNU-GPL
    mkdir -p $out/bin
    cat > $out/bin/sewer-massacre <<'EOF'
    #!@runtimeShell@
    set -eu
    umask 077
    export TERMINFO_DIRS="@terminfo@''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    export CL_SOURCE_REGISTRY="@sourceRegistry@"
    export ASDF_OUTPUT_TRANSLATIONS="@storeDir@:@storeDir@"
    state="''${XDG_STATE_HOME:-''${HOME:?HOME or XDG_STATE_HOME required}/.local/state}/sewer-massacre"
    @mkdir@ -p -- "$state"
    cd -- "$state"
    exec @sbcl@ --noinform --no-userinit --no-sysinit --script @entry@ "$@"
    EOF
    substituteInPlace $out/bin/sewer-massacre \
      --subst-var-by runtimeShell ${runtimeShell} \
      --subst-var-by terminfo ${ncurses}/share/terminfo \
      --subst-var-by sourceRegistry ${lib.escapeShellArg sourceRegistry} \
      --subst-var-by storeDir ${builtins.storeDir} \
      --subst-var-by mkdir ${coreutils}/bin/mkdir \
      --subst-var-by sbcl ${sbcl}/bin/sbcl \
      --subst-var-by entry $out/libexec/sewer-massacre/sewer-massacre.lisp
    chmod 555 $out/bin/sewer-massacre
    runHook postInstall
  '';

  # A: the --smoke command (map creation, a real move, inventory and a
  #    cl-store save/restore compared by content) under an 80x25
  #    pseudo-terminal, with a decoy user ASDF configuration that must be
  #    ignored.  Only the fallback state directory may appear in HOME.
  # B: the same with XDG_STATE_HOME and a read-only HOME.
  # C: a plain launch: splash screen, game screen, Q, y, a name for the high
  #    score table, which writes hiscore and morgue.txt and removes no save.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export TERM=xterm LC_ALL=C
    unset XDG_STATE_HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_CONFIG_DIRS \
      CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS TERMINFO_DIRS

    # wait_for FILE TEXT: wait up to 60 seconds for TEXT in FILE.
    wait_for() {
      tries=0
      until tr -d '\000' < "$1" | grep -qF -- "$2"; do
        tries=$((tries + 1))
        [ "$tries" -le 600 ] || return 1
        sleep 0.1
      done
    }

    feed_smoke() {
      wait_for "$1" SEWERS_SMOKE_OK
    }

    feed_play() {
      wait_for "$1" 'continue]' || return 1
      printf ' '
      wait_for "$1" 'Cash:' || return 1
      printf Q
      wait_for "$1" 'saving?' || return 1
      printf y
      wait_for "$1" 'Enter your name' || return 1
      printf 'nix\r'
      wait_for "$1" 'Adventurers:' || return 1
      sleep 0.5
      printf ' '
    }

    # run NAME FEEDER ARGS...: run the launcher on a pseudo-terminal.
    run() {
      name=$1 feeder=$2
      shift 2
      raw=$TMPDIR/$name.raw
      : > "$raw"
      { "$feeder" "$raw" || touch "$TMPDIR/$name.failed"; } \
        | timeout 300 script -qefc \
            "stty rows 25 cols 80; exec $out/bin/sewer-massacre $*" /dev/null \
            > "$raw" \
        || exit 1
      test ! -e "$TMPDIR/$name.failed" || exit 1
      tr -d '\000' < "$raw" > "$TMPDIR/$name.screen"
    }

    # A user ASDF configuration that must not be read.
    mkdir -p "$TMPDIR/decoy"
    echo '(error "user ASDF registry read")' > "$TMPDIR/decoy/sewers.asd"

    export HOME=$TMPDIR/home-a
    mkdir -p "$HOME/.config/common-lisp/source-registry.conf.d" \
      "$HOME/.config/common-lisp/asdf-output-translations.conf.d"
    echo "(:tree \"$TMPDIR/decoy/\")" \
      > "$HOME/.config/common-lisp/source-registry.conf.d/decoy.conf"
    echo "(\"${builtins.storeDir}/\" \"$TMPDIR/translated/\")" \
      > "$HOME/.config/common-lisp/asdf-output-translations.conf.d/decoy.conf"
    (cd "$HOME" && find . | sort) > "$TMPDIR/a.before"
    run a feed_smoke --smoke
    grep -qF SEWERS_SMOKE_OK "$TMPDIR/a.screen"
    state=$HOME/.local/state/sewer-massacre
    test "$(stat -c %a "$state")" = 700
    test "$(ls -A "$state")" = current.sav
    test "$(stat -c %a "$state/current.sav")" = 600
    (cd "$HOME" && find . | sort) > "$TMPDIR/a.after"
    test "$(comm -13 "$TMPDIR/a.before" "$TMPDIR/a.after" | tr '\n' ' ')" \
      = './.local ./.local/state ./.local/state/sewer-massacre ./.local/state/sewer-massacre/current.sav '
    test ! -e "$TMPDIR/translated"

    export HOME=$TMPDIR/home-b XDG_STATE_HOME=$TMPDIR/xdg
    mkdir -p "$HOME"
    chmod -R a-w "$HOME"
    run b feed_smoke --smoke
    grep -qF SEWERS_SMOKE_OK "$TMPDIR/b.screen"
    test -s "$XDG_STATE_HOME/sewer-massacre/current.sav"
    test -z "$(ls -A "$HOME")"
    chmod -R u+w "$HOME"
    unset XDG_STATE_HOME

    export HOME=$TMPDIR/home-c
    mkdir -p "$HOME"
    run c feed_play
    grep -qF nix "$TMPDIR/c.screen"
    state=$HOME/.local/state/sewer-massacre
    test -s "$state/hiscore"
    test -s "$state/morgue.txt"
    test ! -e "$state/current.sav"
    grep -qF 'Status: [missing]' "$state/morgue.txt"
    runHook postInstallCheck
  '';

  passthru = { inherit sewers; };

  meta = {
    description = "Terminal roguelike set in the sewers";
    longDescription = ''
      The Sewer Massacre is a Common Lisp roguelike in which a homeless person
      collects money in the sewers and tries to escape alive.  Saved games, the
      high score table and morgue.txt live in XDG_STATE_HOME/sewer-massacre,
      falling back to ~/.local/state/sewer-massacre.  `sewer-massacre --smoke`
      exercises map creation, movement and save and restore in a terminal.
    '';
    homepage = "http://common-lisp.net/project/lifp/sewers.htm";
    # r2.lisp: GNU GPL, version 2 text shipped; curses.lisp: "use it for any
    # purpose"; the channel's entry file: GPL-3.0-or-later.
    license = with lib.licenses; [ gpl2Only free gpl3Plus ];
    mainProgram = "sewer-massacre";
    platforms = [ "x86_64-linux" ];
  };
}
