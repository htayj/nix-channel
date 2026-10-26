{ lib, stdenv, fetchFromGitHub, gzip }:

stdenv.mkDerivation (finalAttrs: {
  pname = "itstar";
  # The README identifies this revision as V1.10; upstream has no release tag.
  version = "1.10-unstable-b709cd8";

  src = fetchFromGitHub {
    owner = "PDP-10";
    repo = "itstar";
    rev = "b709cd82ebcfa2cc78f79da8ca9e81c31f53a7c3";
    hash = "sha256-Gni8gdgGgEWoUhweHxwDuYFAY9xKkXeba2TK0jjH0Qs=";
  };

  postPatch = ''
    # BSD make's `!=' assignment and hard-coded cc are unnecessary here.
    substituteInPlace Makefile \
      --replace-fail 'UNAME != uname' 'UNAME := Linux' \
      --replace-fail 'strip itstar' 'true'
    sed -i 's/\bcc\b/$(CC)/' Makefile

    # Disable the legacy host:device rmt path, which needs rexec(3).
    # Local tape images and devices are unaffected.
    sed -i 's|else .*rmt.*remote host.*|else {\n\t\tfprintf(stderr, "?Remote rmt tape paths are unsupported in this build\\n");\n\t\texit(1);\n#if 0|' tapeio.c
    substituteInPlace tapeio.c --replace-fail 'free(host);' $'free(host);\n#endif'

    # zopen runs zcat with an empty environment; call gzip at its store path.
    substituteInPlace zopen.c \
      --replace-fail '/bin/zcat' '${gzip}/bin/gzip' \
      --replace-fail '"zcat", NULL' '"gzip", "-d", "-c", NULL'
  '';

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin itstar
    install -Dm644 -t $out/share/doc/itstar README itstar.doc COPYING "Relicensing Permission.txt"
    runHook postInstall
  '';

  meta = {
    description = "Create, list, and extract PDP-10 ITS DUMP tape images";
    longDescription = ''
      ITSTAR creates, lists, appends to, and extracts PDP-10 ITS DUMP tape
      images.  It translates ITS filenames and evacuated 36-bit word data and
      supports compressed .Z input.  Remote rmt tape paths are disabled.
    '';
    homepage = "https://github.com/PDP-10/itstar";
    license = lib.licenses.gpl3Plus;
    mainProgram = "itstar";
    platforms = lib.platforms.linux;
  };
})
