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
  # the launcher enters the state directory first.  --smoke instead runs in a
  # private temporary directory, removed afterwards, and leaves saved games
  # untouched.
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
    if [ "$#" -eq 1 ] && [ "$1" = --smoke ]; then
      # The smoke saves and loads current.sav in its working directory, so it
      # runs in a private temporary directory and leaves saved games alone.
      # This shell outlives the game to remove that directory, on exit and
      # after stopping the game on HUP, INT or TERM.
      smoke= sbcl= signal= signals=0
      forward() {
        signal=$1 signals=$((signals + 1))
        [ -z "$sbcl" ] || kill -s TERM "$sbcl" 2>/dev/null || :
      }
      trap '[ -z "$smoke" ] || @rm@ -rf -- "$smoke"' EXIT
      trap 'forward HUP' HUP
      trap 'forward INT' INT
      trap 'forward TERM' TERM
      smoke=$(@mktemp@ -d -- "''${TMPDIR:-/tmp}/sewer-massacre-smoke.XXXXXXXXXX")
      cd -- "$smoke"
      smoke=$PWD
      # Without job control the game stays in the terminal's foreground
      # process group; only its standard input needs restoring.
      @sbcl@ --noinform --no-userinit --no-sysinit --script @entry@ --smoke <&0 &
      sbcl=$!
      [ -z "$signal" ] || kill -s TERM "$sbcl" 2>/dev/null || :
      # A trapped signal interrupts wait; wait again until the game exits.
      while :; do
        seen=$signals status=0
        wait "$sbcl" || status=$?
        [ "$signals" != "$seen" ] || break
      done
      if [ -n "$signal" ]; then
        @rm@ -rf -- "$smoke"
        smoke=
        trap - "$signal"
        kill -s "$signal" "$$"
      fi
      exit "$status"
    fi
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
      --subst-var-by mktemp ${coreutils}/bin/mktemp \
      --subst-var-by rm ${coreutils}/bin/rm \
      --subst-var-by sbcl ${sbcl}/bin/sbcl \
      --subst-var-by entry $out/libexec/sewer-massacre/sewer-massacre.lisp
    chmod 555 $out/bin/sewer-massacre
    runHook postInstall
  '';

  # A: the --smoke command (map creation, a real move, inventory and a
  #    cl-store save/restore compared by content) under an 80x25
  #    pseudo-terminal, with a decoy user ASDF configuration that must be
  #    ignored.  It runs in a private directory under TMPDIR that must be
  #    removed; sentinel saved games in the fallback state directory and the
  #    rest of HOME must not change.
  # B: the same with XDG_STATE_HOME and a read-only HOME, then with an absent
  #    state directory, which must not be created, and with neither variable.
  # F: a failing smoke exits 1; TERM, INT and HUP stop a smoke held at its
  #    capture rendezvous.  Each must remove its directory and keep saved games.
  # C: a plain launch: splash screen, game screen, Q, y, a name for the high
  #    score table, which writes hiscore and morgue.txt and removes no save.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export TERM=xterm LC_ALL=C
    unset XDG_STATE_HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_CONFIG_DIRS \
      CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS TERMINFO_DIRS

    # Every launch gets this TMPDIR; the space exercises quoting.  Each smoke
    # must leave it empty.
    smoketmp="$TMPDIR/smoke tmp"
    mkdir "$smoketmp"
    no_smoke_dirs() {
      test -z "$(ls -A "$smoketmp")"
    }

    # seed NAME DIR: put sentinel saved games in DIR and keep a copy.
    seed() {
      mkdir -p "$2"
      for file in current.sav hiscore morgue.txt; do
        echo "$1 $file sentinel" > "$2/$file"
      done
      cp -a "$2" "$TMPDIR/$1.sentinels"
    }

    # unchanged NAME DIR: DIR holds exactly the sentinels, byte for byte.
    unchanged() {
      diff -r "$TMPDIR/$1.sentinels" "$2"
    }

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
        | env TMPDIR="$smoketmp" timeout 300 script -qefc \
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
    seed a "$HOME/.local/state/sewer-massacre"
    (cd "$HOME" && find . | sort) > "$TMPDIR/a.before"
    run a feed_smoke --smoke
    grep -qF SEWERS_SMOKE_OK "$TMPDIR/a.screen"
    unchanged a "$HOME/.local/state/sewer-massacre"
    (cd "$HOME" && find . | sort) > "$TMPDIR/a.after"
    cmp "$TMPDIR/a.before" "$TMPDIR/a.after"
    test ! -e "$TMPDIR/translated"
    no_smoke_dirs

    export HOME=$TMPDIR/home-b XDG_STATE_HOME=$TMPDIR/xdg
    mkdir -p "$HOME"
    seed b "$XDG_STATE_HOME/sewer-massacre"
    chmod -R a-w "$HOME"
    run b feed_smoke --smoke
    grep -qF SEWERS_SMOKE_OK "$TMPDIR/b.screen"
    unchanged b "$XDG_STATE_HOME/sewer-massacre"
    test -z "$(ls -A "$HOME")"
    no_smoke_dirs
    export XDG_STATE_HOME=$TMPDIR/xdg-absent
    run b-absent feed_smoke --smoke
    grep -qF SEWERS_SMOKE_OK "$TMPDIR/b-absent.screen"
    test ! -e "$XDG_STATE_HOME"
    test -z "$(ls -A "$HOME")"
    no_smoke_dirs
    chmod -R u+w "$HOME"
    (unset HOME XDG_STATE_HOME; run b-unset feed_smoke --smoke)
    grep -qF SEWERS_SMOKE_OK "$TMPDIR/b-unset.screen"
    no_smoke_dirs
    unset XDG_STATE_HOME

    export HOME=$TMPDIR/home-f
    state=$HOME/.local/state/sewer-massacre
    seed f "$state"

    # SEWERS_CAPTURE_READY without SEWERS_CAPTURE_DONE fails an assertion after
    # the save and before the rendezvous file is written.
    status=0
    env TMPDIR="$smoketmp" SEWERS_CAPTURE_READY="$TMPDIR/f.ready" \
      timeout 300 script -qefc \
        "stty rows 25 cols 80; exec $out/bin/sewer-massacre --smoke" \
        /dev/null < /dev/null > "$TMPDIR/f.raw" || status=$?
    test "$status" = 1
    test ! -e "$TMPDIR/f.ready"
    unchanged f "$state"
    no_smoke_dirs

    # interrupt NAME SIGNAL STATUS: hold a smoke at its capture rendezvous,
    # send SIGNAL to the launcher alone once the game is ready, and expect
    # script to report STATUS.  Bash starts background jobs with INT ignored,
    # so env restores its default.
    interrupt() {
      (
        status=0
        env --default-signal=INT TMPDIR="$smoketmp" \
            SEWERS_CAPTURE_READY="$TMPDIR/$1.ready" \
            SEWERS_CAPTURE_DONE="$TMPDIR/$1.never" \
          timeout 300 script -qefc \
            "stty rows 25 cols 80; echo \$\$ > $TMPDIR/$1.pid; exec $out/bin/sewer-massacre --smoke" \
            /dev/null < /dev/null > "$TMPDIR/$1.raw" || status=$?
        echo "$status" > "$TMPDIR/$1.status"
      ) &
      tries=0
      until test -s "$TMPDIR/$1.ready"; do
        tries=$((tries + 1))
        [ "$tries" -le 600 ] || return 1
        sleep 0.1
      done
      kill -s "$2" "$(cat "$TMPDIR/$1.pid")"
      wait "$!"
      test "$(cat "$TMPDIR/$1.status")" = "$3"
      tr -d '\000' < "$TMPDIR/$1.raw" > "$TMPDIR/$1.screen"
      if grep -qF SEWERS_SMOKE_OK "$TMPDIR/$1.screen"; then return 1; fi
    }
    interrupt f-term TERM 143
    unchanged f "$state"
    no_smoke_dirs
    interrupt f-int INT 130
    unchanged f "$state"
    no_smoke_dirs
    interrupt f-hup HUP 129
    unchanged f "$state"
    no_smoke_dirs

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
      exercises map creation, movement and save and restore in a terminal, in a
      private temporary directory that leaves saved games untouched.
    '';
    homepage = "http://common-lisp.net/project/lifp/sewers.htm";
    # r2.lisp: GNU GPL, version 2 text shipped; curses.lisp: "use it for any
    # purpose"; the channel's entry file: GPL-3.0-or-later.
    license = with lib.licenses; [ gpl2Only free gpl3Plus ];
    mainProgram = "sewer-massacre";
    platforms = [ "x86_64-linux" ];
  };
}
