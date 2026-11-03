{ lib, emacsPackages, fetchFromGitHub }:

emacsPackages.trivialBuild {
  pname = "chatgpt";
  # Upstream declares 0.2 but has no release tag at this revision.
  version = "0.2-unstable-2023-10-31";

  src = fetchFromGitHub {
    owner = "joshcho";
    repo = "ChatGPT.el";
    rev = "51c658aa40a106a4ee3afe4376f5ed3d6024c8a9";
    hash = "sha256-sh/O36RN34osWLaNVNM3mWKE7mJUdom/ZrBoO2U+Yr8=";
  };

  # Required on load, not only for optional formatting.
  packageRequires = [ emacsPackages.polymode ];

  # Upstream shells out to `which' at load time; without `which' the default
  # becomes the shell's error text.  Resolve the user-provided CLI from
  # `exec-path' instead.
  postPatch = ''
    substituteInPlace chatgpt.el \
      --replace-fail '(shell-command-to-string "which lwe")' \
                     '(or (executable-find "lwe") "lwe")'
  '';

  # Upstream ships no test suite.  Load the library with no PATH and no API
  # key, and check the commands and the CLI default.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PATH= OPENAI_API_KEY= ${emacsPackages.emacs}/bin/emacs --batch -Q \
      -l package -f package-initialize -L . --eval "(progn
      (setq exec-path nil)
      (require 'chatgpt)
      (unless (and (featurep 'chatgpt) (commandp 'chatgpt-query)
                   (commandp 'chatgpt-run))
        (error \"ChatGPT commands unavailable\"))
      (unless (equal chatgpt-cli-file-path \"lwe\")
        (error \"unexpected lwe default: %S\" chatgpt-cli-file-path)))"
    runHook postCheck
  '';

  postInstall = ''
    install -Dm644 LICENSE README.org -t $out/share/doc/emacs-chatgpt-el
  '';

  meta = {
    description = "Emacs interface to ChatGPT via the user-provided lwe CLI";
    homepage = "https://github.com/joshcho/ChatGPT.el";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
