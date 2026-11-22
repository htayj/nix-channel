{
  lib,
  sbcl,
  sbcl-mcclim,
  fetchFromGitHub,
  applyPatches,
  runtimeShell,
  runCommand,
}:

let
  version = "0-unstable-2021-10-31";

  # Upstream GenEd ported to SBCL and McCLIM 1.0.0, following the Guix
  # channel's adapt-to-mcclim phase.  The ASDF system, the McCLIM shims and
  # the launcher entry point replace the vendor defsystem loader.  The edits
  # are applied to src because buildASDFSystem would run a top-level postPatch
  # a second time on the already patched source.
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "lambdamikel";
      repo = "GenEd";
      rev = "0d847a3bdffefcea6999926aac6be1382e7d6b33";
      hash = "sha256-ja3bRJhRKbQQAAJaS4HDTUrSWRMZPYaahf34oCPvEho=";
    };
    patches = [ ./gened-duplicate-definitions.patch ];
    postPatch = ''
      cp ${./gened.asd} gened.asd
      cp ${./gened-mcclim.lisp} gened-mcclim.lisp
      cp ${./gened-main.lisp} gened-main.lisp

      # Portable package designators; CLASSIC stays disabled.  The McCLIM
      # extension panes are imported into GENED.
      sed -i \
        -e 's/(:use clim-lisp/(:use #:clim-lisp/' \
        -e 's/^[[:space:]]*clim$/        #:clim/' \
        -e 's/#+:classic classic/#+:classic #:classic/' \
        -e 's/#+:classic krss-classic/#+:classic #:krss-classic/' \
        -e 's/(:shadowing-import-from classic/(:shadowing-import-from #:classic/' \
        -e 's/(defpackage gened/(defpackage gened\n  (:import-from #:clim-extensions\n    #:accept-values-pane #:accept-values-pane-displayer)/' \
        src/gened-packages.lisp
      grep -q '#:accept-values-pane-displayer)' src/gened-packages.lisp

      # The portable OUTL definition is supplied before FRAME2.  Property
      # panes rerun their displayer so accepted values update the editor,
      # and CLIM completion names are strings.
      substituteInPlace src/frame2.lisp \
        --replace-fail '#+(or mcl lispworks)' '#+nil' \
        --replace-fail 'accept-values-pane-displayer' \
          'accept-values-pane-displayer :resynchronize-every-pass t' \
        --replace-fail ':name-key identity' ':name-key princ-to-string'

      # McCLIM returns an action keyword from NOTIFY-USER, so confirmations
      # go through CONFIRM-OPERATION and cancellation stays false.
      substituteInPlace src/main.lisp \
        --replace-fail 'yes-or-no (notify-user' 'yes-or-no (confirm-operation'
      substituteInPlace src/inout.lisp \
        --replace-fail 'not (notify-user' 'not (confirm-operation'

      # Direct printing exists only on Allegro; PostScript export remains.
      substituteInPlace src/comtable.lisp \
        --replace-fail '("Print Scene" :command' '#+allegro ("Print Scene" :command'

      # CLIM 2 separates menu entries from command registration.
      substituteInPlace src/undo.lisp \
        --replace-fail remove-command-from-command-table remove-undo-menu-item \
        --replace-fail add-command-to-command-table add-undo-menu-item

      # Translator arglists begin with the presented object.
      test "$(grep -c '^  (x y)' src/creator.lisp)" = 1
      sed -i 's/^  (x y)/  (object x y)/' src/creator.lisp

      # McCLIM's text-field gadget dialog is broken; use the textual dialog.
      substituteInPlace src/creator.lisp \
        --replace-fail ":view 'gadget-dialog-view" ":view 'textual-dialog-view"
    '';
  };

  gened-lisp = sbcl.buildASDFSystem {
    pname = "gened";
    inherit version src;
    systems = [ "gened" ];
    lispLibs = [ sbcl-mcclim ];
  };

  sbclWithGened = sbcl.withPackages (_: [ gened-lisp ]);
in
runCommand "gened-${version}"
  {
    passthru = {
      lisp = gened-lisp;
      inherit sbclWithGened;
    };
    meta = {
      description = "Visual notation editor using Common Lisp and CLIM";
      longDescription = ''
        GenEd is a graphical editor for visual notations with geometric and
        spatial relationships.  This package runs the upstream editor on SBCL
        and McCLIM 1.0.0, including graphical primitives, text, object
        manipulation, scene files and object libraries.  The CLASSIC
        description-logic integration was disabled by upstream and is not
        included.  Example scenes, libraries and label assets are copied into
        writable XDG user data on launch without overwriting existing files.
        The editor needs an X display.
      '';
      homepage = "https://github.com/lambdamikel/GenEd";
      license = lib.licenses.gpl3Only;
      mainProgram = "gened";
      platforms = lib.platforms.linux;
    };
  }
  ''
    mkdir -p $out/bin
    cat > $out/bin/gened <<EOF
    #!${runtimeShell}
    exec ${sbclWithGened}/bin/sbcl --noinform --non-interactive \\
      --eval '(require :asdf)' \\
      --eval '(asdf:load-system :gened)' \\
      --eval '(gened:main)' "\$@"
    EOF
    chmod 555 $out/bin/gened
  ''
