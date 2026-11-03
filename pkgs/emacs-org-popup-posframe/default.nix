{ lib, emacsPackages, fetchFromGitHub }:

emacsPackages.trivialBuild {
  pname = "org-popup-posframe";
  version = "0.0.1-unstable-2024-05-27";

  src = fetchFromGitHub {
    owner = "A7R7";
    repo = "org-popup-posframe";
    rev = "d39cb7c2c9a996689b0d6519695eed3d807c0c85";
    hash = "sha256-yZJBx/uJ9W9ZAdYieZ7ArRvigt0391rIyTt+DEIHHjU=";
  };

  packageRequires = [ emacsPackages.posframe ];

  # Upstream ships no test suite.  Load the library, then enable and disable
  # the global mode in batch Emacs, where posframe display is a no-op.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    emacs --batch -Q -l package -f package-initialize -L . --eval "(progn
      (require 'org-popup-posframe)
      (org-popup-posframe-mode 1)
      (unless org-popup-posframe-mode
        (error \"org-popup-posframe-mode did not enable\"))
      (org-popup-posframe-mode -1))"
    runHook postCheck
  '';

  postInstall = ''
    install -Dm644 LICENSE readme.org -t $out/share/doc/emacs-org-popup-posframe
  '';

  meta = {
    description = "Show Org popup buffers in posframes";
    homepage = "https://github.com/A7R7/org-popup-posframe";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
