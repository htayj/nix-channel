{ lib, emacsPackages, fetchFromGitHub }:

emacsPackages.trivialBuild {
  pname = "treesit-sexp";
  version = "0.1.0-unstable-2026-01-17";

  src = fetchFromGitHub {
    owner = "alexispurslane";
    repo = "treesit-sexp";
    rev = "c9aafc4e5f705a70e96ac733aa5a0960c50de7f2";
    hash = "sha256-mBVZtLqp5t8BXyod2qUTjqRuDMgwQ6Eu+ZE7X8UcRJQ=";
  };

  # Keep the ERT fixture out of the compiled and installed libraries.
  postPatch = ''
    mkdir tests
    mv test-structural-editing.el tests/
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    # Exercise the no-grammar fallback, then the bundled offline ERT suite.
    emacs --batch -Q -L . --eval "(progn
      (require 'treesit-sexp)
      (with-temp-buffer
        (insert \"(a b)\")
        (goto-char (point-min))
        (treesit-sexp-forward 1)
        (unless (= (point) (point-max))
          (error \"treesit-sexp fallback navigation failed\"))))"
    emacs --batch -Q -L . -l tests/test-structural-editing.el \
      -f ert-run-tests-batch-and-exit
    runHook postCheck
  '';

  postInstall = ''
    install -Dm644 LICENSE README.md -t $out/share/doc/emacs-treesit-sexp
  '';

  meta = {
    description = "Tree-sitter based structural editing for Emacs";
    homepage = "https://github.com/alexispurslane/treesit-sexp";
    license = lib.licenses.bsd0;
    platforms = [ "x86_64-linux" ];
  };
}
