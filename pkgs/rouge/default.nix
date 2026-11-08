{
  lib,
  stdenv,
  fetchurl,
  applyPatches,
  unzip,
  sbcl,
  ncurses,
  runtimeShell,
}:

let
  version = "1.61";

  # Upstream INIT-CONTROLS reads controls.cfg from the working directory.
  initControlsOld = ''
    (defun init-controls ()
      (setf *controls* (make-hash-table :test #'eql))
      (when (probe-file "controls.cfg")
        (with-open-file (i "controls.cfg")
          (let* ((*read-eval* nil)
  '';

  # User overrides come from XDG_CONFIG_HOME/rouge/controls.cfg, high scores
  # live in XDG_STATE_HOME/rouge/hiscore; relative or empty XDG values fall
  # back to ~/.config and ~/.local/state.  The packaged default controls sit
  # beside the compiled system.  Reading binds *PACKAGE* so the file's bare
  # action names resolve in ROUGELIKE whatever package the caller is in.
  initControlsNew = ''
    (defun user-directory (variable fallback)
      ;; XDG base-directory variables must be absolute; others are ignored.
      (let ((value (uiop:getenv variable)))
        (merge-pathnames
         "rouge/"
         (if (and value (plusp (length value)) (char= (char value 0) #\/))
             (uiop:ensure-directory-pathname value)
             (merge-pathnames fallback (user-homedir-pathname))))))

    (defun control-file ()
      (let ((custom (merge-pathnames "controls.cfg"
                                     (user-directory "XDG_CONFIG_HOME" ".config/"))))
        (if (probe-file custom)
            custom
            (asdf:system-relative-pathname :rouge "controls.cfg"))))

    (defun hiscore-file ()
      (merge-pathnames "hiscore"
                       (user-directory "XDG_STATE_HOME" ".local/state/")))

    (defun init-controls ()
      (setf *controls* (make-hash-table :test #'eql))
      (when (probe-file (control-file))
        (with-open-file (i (control-file))
          (let* ((*package* (find-package :rougelike))
                 (*read-eval* nil)
  '';

  # Draw the splash screen inside UNWIND-PROTECT so the terminal is restored
  # if anything fails after curses starts.  Plain strings keep the leading
  # indentation, which an indented string would strip.
  splashOld = lib.concatStrings [
    "  (erase)\n"
    "  (splash-screen)\n"
    "  (unwind-protect\n"
    "       (progn\n"
  ];
  splashNew = lib.concatStrings [
    "  (unwind-protect\n"
    "       (progn\n"
    "         (erase)\n"
    "         (splash-screen)\n"
  ];

  # Patch the source itself; buildASDFSystem would otherwise run a top-level
  # postPatch on already patched source a second time.
  src = applyPatches {
    name = "rouge-src-${version}";
    src = fetchurl {
      # The 2007-04-16 Linux/source release, not the Windows 1.6 binary.
      url = "https://common-lisp.net/project/lifp/rouge-src.zip";
      name = "rouge-${version}.zip";
      hash = "sha256-4wSTNt1zPj2Y2NoVoGguWJxrSbJAncOPZTz4XelRHX0=";
    };
    nativeBuildInputs = [ unzip ];
    # The ZIP holds readme.txt beside SRC, which is the source root.
    postPatch = ''
      cp ../readme.txt readme.txt
      sed -i 's/\r//g' rouge.lisp curses.lisp rouge.asd controls.cfg
      substituteInPlace curses.lisp \
        --replace-fail '(:unix "libncurses.so.5")' \
          '(:unix "${lib.getLib ncurses}/lib/libncurses.so.6")' \
        --replace-fail '(defctype chtype :long)' '(defctype chtype :unsigned-int)' \
        --replace-fail '(defcfun ("PDC_ungetch" ungetch)' '(defcfun ("ungetch" ungetch)'
      substituteInPlace rouge.lisp \
        --replace-fail ${lib.escapeShellArg initControlsOld} \
          ${lib.escapeShellArg initControlsNew} \
        --replace-fail '(unless (probe-file "hiscore")' '(unless (probe-file (hiscore-file))' \
        --replace-fail '(with-open-file (in "hiscore"' '(with-open-file (in (hiscore-file)' \
        --replace-fail '  (with-open-file (out "hiscore" :direction' \
          ${lib.escapeShellArg "  (ensure-directories-exist (hiscore-file))\n  (with-open-file (out (hiscore-file) :direction"} \
        --replace-fail ${lib.escapeShellArg splashOld} ${lib.escapeShellArg splashNew}
      if grep -qE '(probe-file|with-open-file \((in|out)) "hiscore"' rouge.lisp; then
        echo "rouge.lisp still uses a working-directory hiscore" >&2
        exit 1
      fi
      if grep -q $'\r' rouge.lisp curses.lisp rouge.asd controls.cfg; then
        echo "carriage returns remain in the sources" >&2
        exit 1
      fi
    '';
  };

  rougeSystem = sbcl.buildASDFSystem {
    pname = "rouge";
    inherit version src;
    lispLibs = with sbcl.pkgs; [ cffi md5 trivial-gray-streams ];
  };

  # Every compiled Lisp system the game loads, and nothing from the user.
  lispClosure = map (entry: entry.drv) (builtins.genericClosure {
    startSet = [ { key = rougeSystem.outPath; drv = rougeSystem; } ];
    operator = entry:
      map (drv: { key = drv.outPath; inherit drv; }) (entry.drv.lispLibs or [ ]);
  });
  sourceRegistry = lib.concatMapStringsSep ":" (drv: "${drv}//") lispClosure;
in
stdenv.mkDerivation {
  pname = "rouge";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # Load the compiled ASDF system at launch; no core is saved.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/doc/rouge \
      ${src}/license.txt ${src}/GNU-GPL ${src}/readme.txt
    install -Dm644 ${src}/controls.cfg $out/share/rouge/controls.cfg
    cat > $out/share/doc/rouge/THIRD-PARTY-NOTICES <<'EOF'
    The Rougelike! 1.61, copyright 2006 Timofei Shatrov.
    rouge.lisp: GNU GPL version 2 or later (license.txt and GNU-GPL).
    curses.lisp: license.txt permits use for any purpose.
    controls.cfg and readme.txt: original source-release project material.
    No external tiles, fonts, sounds, maps or prebuilt executables are installed.

    Runtime dependencies are separate, source-built Nixpkgs packages:
    SBCL: public domain and BSD terms; see its source COPYING.
    ncurses: X11/MIT license; see its source COPYING.
    CFFI: MIT license; see its source COPYRIGHT.
    md5 (cl-md5): public domain; see its source md5.lisp.
    trivial-gray-streams: MIT license; see its source COPYING.
    CFFI's Lisp dependencies (alexandria, babel, trivial-features) keep their
    own Nixpkgs license metadata.
    EOF
    mkdir -p $out/bin
    cat > $out/bin/rouge <<'EOF'
    #!@runtimeShell@
    set -eu
    if [ "$#" -ne 0 ]; then
      echo "usage: rouge" >&2
      exit 2
    fi
    export TERMINFO_DIRS="@terminfo@''${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
    export CL_SOURCE_REGISTRY="@sourceRegistry@"
    export ASDF_OUTPUT_TRANSLATIONS="@storeDir@:@storeDir@"
    exec @sbcl@ --noinform --no-userinit --no-sysinit --non-interactive \
      --eval '(require :asdf)' \
      --eval '(asdf:load-system :rouge)' \
      --eval '(rougelike::start-game)'
    EOF
    substituteInPlace $out/bin/rouge \
      --subst-var-by runtimeShell ${runtimeShell} \
      --subst-var-by terminfo ${ncurses}/share/terminfo \
      --subst-var-by sourceRegistry ${lib.escapeShellArg sourceRegistry} \
      --subst-var-by storeDir ${builtins.storeDir} \
      --subst-var-by sbcl ${sbcl}/bin/sbcl
    chmod 555 $out/bin/rouge
    runHook postInstall
  '';

  # Never starts curses or the game.  Loads the compiled system with the
  # launcher's isolated ASDF settings, with HOME and every XDG base directory
  # under TMPDIR, and checks control and high-score paths, the packaged
  # default bindings, a user override, a high-score round trip, home
  # fallbacks for empty or relative XDG values, and that loading and reading
  # controls create nothing.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export LC_ALL=C
    unset CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS XDG_CONFIG_DIRS XDG_DATA_DIRS

    bash -n $out/bin/rouge
    status=0
    $out/bin/rouge --help 2>/dev/null || status=$?
    test "$status" = 2

    defaults=${rougeSystem}/controls.cfg
    cmp "$defaults" $out/share/rouge/controls.cfg

    cat > "$TMPDIR/check.lisp" <<'EOF'
    (require :asdf)
    (asdf:load-system :rouge)
    (defun expect (ok what)
      (unless ok
        (format *error-output* "rouge check failed: ~a~%" what)
        (uiop:quit 1)))
    (defun env (name) (or (uiop:getenv name) ""))
    (let ((mode (env "ROUGE_CHECK"))
          (*package* (find-package :cl-user)))
      (expect (string= (namestring (rougelike::hiscore-file)) (env "EXPECT_HISCORE"))
              "hiscore path")
      (expect (string= (namestring (rougelike::control-file)) (env "EXPECT_CONTROLS"))
              "controls path")
      (rougelike::init-controls)
      (let ((controls rougelike::*controls*))
        (cond ((string= mode "default")
               (expect (typep (gethash 261 controls) 'rougelike::move-to) "right arrow moves")
               (expect (typep (gethash 81 controls) 'rougelike::quit-game) "Q quits")
               (expect (null (rougelike::load-hiscore)) "no high scores yet"))
              ((string= mode "override")
               (expect (typep (gethash 113 controls) 'rougelike::quit-game) "override binds q")
               (expect (null (gethash 81 controls)) "override replaces the defaults"))
              ((string= mode "hiscore")
               (let ((table (list (cons "nix" 42))))
                 (rougelike::save-hiscore table)
                 (expect (equal (rougelike::load-hiscore) table) "high-score round trip")))
              (t (expect nil "unknown mode")))))
    (format t "ROUGE_CHECK_OK ~a~%" (env "ROUGE_CHECK"))
    EOF

    check() {
      env CL_SOURCE_REGISTRY=${lib.escapeShellArg sourceRegistry} \
        ASDF_OUTPUT_TRANSLATIONS=${builtins.storeDir}:${builtins.storeDir} \
        ${sbcl}/bin/sbcl --noinform --script "$TMPDIR/check.lisp" \
        > "$TMPDIR/check.out"
      grep -qxF "ROUGE_CHECK_OK $ROUGE_CHECK" "$TMPDIR/check.out"
    }

    base=$TMPDIR/rouge-check
    export HOME=$base/home XDG_CONFIG_HOME=$base/config XDG_CACHE_HOME=$base/cache \
      XDG_DATA_HOME=$base/data XDG_STATE_HOME=$base/state XDG_RUNTIME_DIR=$base/runtime
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" \
      "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"

    # Packaged defaults; loading and reading controls write nothing anywhere.
    ROUGE_CHECK=default EXPECT_CONTROLS=$defaults \
      EXPECT_HISCORE=$XDG_STATE_HOME/rouge/hiscore check
    test -z "$(find "$base" -mindepth 2 -print -quit)"

    # A user override in XDG_CONFIG_HOME replaces the defaults.
    mkdir "$XDG_CONFIG_HOME/rouge"
    echo '(((quit-game) 113))' > "$XDG_CONFIG_HOME/rouge/controls.cfg"
    ROUGE_CHECK=override EXPECT_CONTROLS=$XDG_CONFIG_HOME/rouge/controls.cfg \
      EXPECT_HISCORE=$XDG_STATE_HOME/rouge/hiscore check
    test ! -e "$XDG_STATE_HOME/rouge"

    # Saving creates XDG_STATE_HOME/rouge/hiscore.
    ROUGE_CHECK=hiscore EXPECT_CONTROLS=$XDG_CONFIG_HOME/rouge/controls.cfg \
      EXPECT_HISCORE=$XDG_STATE_HOME/rouge/hiscore check
    test -s "$XDG_STATE_HOME/rouge/hiscore"

    # Empty or relative XDG values fall back to ~/.config and ~/.local/state.
    mkdir -p "$HOME/.config/rouge"
    cp "$XDG_CONFIG_HOME/rouge/controls.cfg" "$HOME/.config/rouge/controls.cfg"
    XDG_CONFIG_HOME= XDG_STATE_HOME=relative ROUGE_CHECK=override \
      EXPECT_CONTROLS=$HOME/.config/rouge/controls.cfg \
      EXPECT_HISCORE=$HOME/.local/state/rouge/hiscore check
    XDG_CONFIG_HOME=relative XDG_STATE_HOME= ROUGE_CHECK=hiscore \
      EXPECT_CONTROLS=$HOME/.config/rouge/controls.cfg \
      EXPECT_HISCORE=$HOME/.local/state/rouge/hiscore check
    test -s "$HOME/.local/state/rouge/hiscore"
    test ! -e relative
    test -z "$(find "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR" -mindepth 1 -print -quit)"
    runHook postInstallCheck
  '';

  passthru = { inherit rougeSystem; };

  meta = {
    description = "Wikipedia-satire roguelike with a curses interface";
    longDescription = ''
      The Rougelike! is a turn-based Common Lisp roguelike in which a rogue
      Wikipedia administrator earns Rouge points through outrageous actions,
      while karma influences other users.  The original curses interface has
      articles, vandals, trolls, administrators and a banhammer.  Control
      overrides are read from XDG_CONFIG_HOME/rouge/controls.cfg (falling back
      to ~/.config/rouge); the default bindings are in share/rouge/controls.cfg.
      High scores are kept in XDG_STATE_HOME/rouge/hiscore, falling back to
      ~/.local/state/rouge.
    '';
    homepage = "https://common-lisp.net/project/lifp/rouge.htm";
    # rouge.lisp: "subject to GNU General Public License" with no version
    # named, and the GPL v2 text shipped; GPL v2 section 9 then allows any
    # version.  curses.lisp: "you can use it for any purpose".
    license = with lib.licenses; [ gpl2Plus free ];
    mainProgram = "rouge";
    platforms = [ "x86_64-linux" ];
  };
}
