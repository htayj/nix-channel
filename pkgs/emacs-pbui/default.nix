{ lib, emacsPackages, fetchFromGitHub }:

emacsPackages.trivialBuild {
  pname = "pbui";
  # Upstream declares 0.1 in pbui.el but has no release tag.
  version = "0.1-unstable-2025-06-08";

  src = fetchFromGitHub {
    owner = "mmontone";
    repo = "pbui";
    rev = "19a606d95cc63ed388e8b1e3459f68eaf8c4659e";
    hash = "sha256-Pzgih4PiepqNmBk84ln+F4X2XobkfckA+J+4MKKN5ao=";
  };

  # dash for pbui; s and request for the command and demo modules; inspector
  # for pbui-util and the optional inspect command.  The remaining libraries
  # are bundled with Emacs.
  packageRequires = with emacsPackages; [ dash inspector request s ];

  # Upstream relies on libraries already loaded in the author's session.
  # Require them where they are used so every module loads in a fresh Emacs,
  # give pbui-util its missing feature, fix the selected-presentation
  # argument name, and resolve desktop helpers through `exec-path'.
  postPatch = ''
    substituteInPlace pbui.el \
      --replace-fail $'(require \'dash)' \
        $'(require \'dash)\n(require \'eieio)\n(require \'subr-x)\n(require \'text-property-search)' \
      --replace-fail '(defun pbui:goto-selected-presentation (selected-presentation)' \
        '(defun pbui:goto-selected-presentation (sel)'
    substituteInPlace pbui-standard-commands.el \
      --replace-fail $'(require \'pbui)' $'(require \'pbui)\n(require \'s)' \
      --replace-fail '"/usr/bin/xdg-open"' '"xdg-open"'
    substituteInPlace pbui-contacts-app.el \
      --replace-fail $'(require \'request)' $'(require \'request)\n(require \'json)' \
      --replace-fail '"/usr/bin/xdg-open"' '"xdg-open"' \
      --replace-fail '"/usr/bin/thunderbird"' '"thunderbird"'
    substituteInPlace pbui-util.el \
      --replace-fail '(defun inspect-text-properties-at-point' \
        $'(require \'pbui)\n(require \'inspector)\n\n(defun inspect-text-properties-at-point'
    printf "\n(provide 'pbui-util)\n" >> pbui-util.el
    ! grep -n /usr/bin *.el
  '';

  # Upstream ships no test suite.  Load every library in a fresh Emacs and
  # check the main entry points.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${emacsPackages.emacs}/bin/emacs --batch -Q \
      -l package -f package-initialize -L . --eval "(progn
      (dolist (f '(pbui pbui-util pbui-standard-commands pbui-dired pbui-org
                   pbui-calendar pbui-email pbui-contacts-app))
        (require f))
      (unless (and (fboundp 'pbui-mode) (fboundp 'pbui-modal-mode)
                   (fboundp 'pbui:goto-selected-presentation))
        (error \"PBUI entry points unavailable\")))"
    runHook postCheck
  '';

  postInstall = ''
    install -Dm644 README.org -t $out/share/doc/emacs-pbui
  '';

  meta = {
    description = "Presentation-based user interface for Emacs";
    homepage = "https://github.com/mmontone/pbui";
    # pbui.el and four companion files state GPLv3-or-later; the remaining
    # short files carry no notice and fall under the project's notices.
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
