{ lib, stdenvNoCC, emacsPackages, fetchFromGitHub }:

stdenvNoCC.mkDerivation {
  pname = "emacs-cl";
  # The top-level Makefile declares 0.5; upstream has no release tag.
  version = "0.5-unstable-2016-03-14";

  src = fetchFromGitHub {
    owner = "larsbrinkhoff";
    repo = "emacs-cl";
    rev = "19e950e73a336aad476b0d051819a682863a2eff";
    hash = "sha256-B5qMLt0YzePjtBLbdvcT2DjrzD1fX/uDqILSbB2GFg4=";
  };

  # Port the loader, evaluator and compiler to current Emacs.  Upstream has
  # been inactive since 2016.
  patches = [ ./emacs-30-compat.patch ];
  patchFlags = [ "-p1" "--fuzz=0" ];

  nativeBuildInputs = [ emacsPackages.emacs ];

  # Upstream's compile-cl step does not work with eager macro expansion.
  # Install the sources uncompiled; load-cl.el evaluates them form by form.
  dontBuild = true;

  # Run the upstream suite and require its exact summary.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    (
      cd src
      emacs --batch -Q -L . -l load-cl.el -l batch.el -l tests.el -f test-cl \
        < /dev/null > test.log 2>&1 || { cat test.log; exit 1; }
      grep -E '^Test |^[[:space:]]*(PASS|FAIL)' test.log
      awk '
        /^[[:space:]]*PASS:/ { pass = $2; summaries++ }
        /^[[:space:]]*FAIL evaluation:/ { eval = $3; summaries++ }
        /^[[:space:]]*FAIL compilation:/ { comp = $3; summaries++ }
        /^[[:space:]]*FAIL execution:/ { exe = $3; summaries++ }
        END { exit !(summaries == 4 && pass == 180 &&
                     eval == 0 && comp == 0 && exe == 0) }
      ' test.log
    )
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    lispdir=$out/share/emacs/site-lisp/emacs-cl
    # tests.el is the upstream test driver, not runtime code.
    rm src/tests.el
    install -Dm644 src/*.el -t $lispdir
    install -Dm644 COPYING README HOWTO -t $out/share/doc/emacs-cl
    runHook postInstall
  '';

  # Load the installed copy in a fresh Emacs and exercise the evaluator,
  # the compiler, FORMAT and bignum arithmetic.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    lispdir=$out/share/emacs/site-lisp/emacs-cl
    test ! -e $lispdir/tests.el
    test -z "$(find $out -type f ! -name '*.el' ! -path "$out/share/doc/*")"
    export HOME=$TMPDIR/home
    mkdir -p $HOME
    emacs --batch -Q -L $lispdir -l load-cl -l batch --eval '(let
        ((sum (EVAL (READ-FROM-STRING "(let ((x 0)) (dotimes (i 5 x) (incf x i)))")))
         (square (FUNCALL (COMPILE nil (READ-FROM-STRING "(lambda (n) (* n n))")) 7))
         (text (FORMAT nil "~D:~A" 42 "ok"))
         (big (PRIN1-TO-STRING (EVAL (READ-FROM-STRING "(expt 2 100)")))))
      (unless (and (eql sum 10) (eql square 49) (equal text "42:ok")
                   (equal big "1267650600228229401496703205376"))
        (error "emacs-cl smoke failed: %S" (list sum square text big)))
      (message "emacs-cl smoke: %S" (list sum square text big)))'
    runHook postInstallCheck
  '';

  meta = {
    description = "Common Lisp implemented in Emacs Lisp";
    longDescription = ''
      Emacs Common Lisp is an implementation of Common Lisp written in Emacs
      Lisp.  Loading load-cl.el loads the interpreter, compiler and Common
      Lisp listener; M-x emacs-cl starts the listener.
    '';
    homepage = "https://github.com/larsbrinkhoff/emacs-cl";
    # COPYING is GPL version 2 and the sources name no later version.
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
