{
  lib,
  sbcl,
  sbcl-mcclim,
  fetchFromGitHub,
  runtimeShell,
  runCommand,
}:

let
  version = "0.1.0-unstable-2026-07-29";

  rplaca-lisp = sbcl.buildASDFSystem {
    pname = "rplaca";
    inherit version;

    src = fetchFromGitHub {
      owner = "htayj";
      repo = "rplaca";
      rev = "7cffbb8cbd626bbea0834d5d4bf63adc1344cc6c";
      hash = "sha256-jxshTh/zruJE9EiuTlnxperS2TcqPrx3of6EYeasiEM=";
    };

    # Both systems live in the source tree; lispi is RPLACA's local dependency.
    systems = [
      "lispi"
      "rplaca"
    ];

    # McCLIM 1.0.0 also provides esa-mcclim and drei-mcclim.
    lispLibs =
      [ sbcl-mcclim ]
      ++ (with sbcl.pkgs; [
        alexandria
        bordeaux-threads
        chipz
        cl-json
        coalton
        drakma
        flexi-streams
      ]);
  };

  sbclWithRplaca = sbcl.withPackages (_: [ rplaca-lisp ]);
in
runCommand "rplaca-${version}"
  {
    passthru = {
      lisp = rplaca-lisp;
      inherit sbclWithRplaca;
    };
    meta = {
      description = "Lisp-native Emacs-inspired LLM chat interface";
      longDescription = ''
        RPLACA is an Emacs-inspired chat interface written in Common Lisp.  It
        uses McCLIM for its presentation-rich GUI and provides agent tools,
        structured project and session state, and a Lisp data mode for
        interacting with local files and Common Lisp systems.
      '';
      homepage = "https://github.com/htayj/rplaca";
      license = lib.licenses.agpl3Only;
      mainProgram = "rplaca";
      platforms = lib.platforms.linux;
    };
  }
  # The system is loaded at launch instead of dumped into an executable so that
  # its user-state paths follow the invoking user's home directory.
  ''
    mkdir -p $out/bin
    cat > $out/bin/rplaca <<EOF
    #!${runtimeShell}
    exec ${sbclWithRplaca}/bin/sbcl --noinform --non-interactive \\
      --eval '(require :asdf)' \\
      --eval '(asdf:load-system :rplaca)' \\
      --eval '(rplaca:rplaca-main)' "\$@"
    EOF
    chmod 555 $out/bin/rplaca
  ''
