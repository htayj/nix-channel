# Amstelvar parametric variable serif fonts (upstream v1.001 release binaries).
{ lib, stdenvNoCC, fetchurl }:

let
  version = "1.001";
  rev = "f44f670affec72a37c69a1bf103bddc044020f49";
in
stdenvNoCC.mkDerivation {
  pname = "amstelvar";
  inherit version;

  # Flat hash of the codeload archive, as pinned by the Guix channel.
  src = fetchurl {
    url = "https://codeload.github.com/googlefonts/amstelvar/tar.gz/${rev}";
    name = "amstelvar-${rev}.tar.gz";
    hash = "sha256-P/yTdyfdfkwPogH5463YAnvCf5cA3U5o5EaNWsd+mtc=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # Upstream ships no test suite for the release fonts.
  doCheck = false;

  # Extract only the two v1.001 variable fonts and the project notices;
  # fonts/old and other historical binaries stay out of the output.
  installPhase = ''
    runHook preInstall
    mkdir source
    tar -xzf "$src" -C source --strip-components=1 \
      --wildcards --no-wildcards-match-slash \
      '*/OFL.txt' '*/COPYRIGHT.md' '*/AUTHORS.txt' '*/CONTRIBUTORS.txt' \
      '*/FONTLOG.md' '*/README.md' \
      '*/fonts/Amstelvar-Roman*.ttf' '*/fonts/Amstelvar-Italic*.ttf'
    fonts=(source/fonts/*.ttf)
    if [ "''${#fonts[@]}" -ne 2 ]; then
      echo "expected exactly two Amstelvar fonts" >&2
      exit 1
    fi
    install -Dm444 -t "$out/share/fonts/truetype" "''${fonts[@]}"
    install -Dm444 -t "$out/share/doc/amstelvar" \
      source/OFL.txt source/COPYRIGHT.md source/AUTHORS.txt \
      source/CONTRIBUTORS.txt source/FONTLOG.md source/README.md
    runHook postInstall
  '';

  meta = {
    description = "Parametric variable serif font family";
    longDescription = ''
      Amstelvar is a serif typeface inspired by Dutch and Belgian types and the
      first public demonstration of Type Network parametric axes in OpenType
      variable fonts.  This package installs the upstream v1.001 Roman and
      Italic variable fonts from the release commit.
    '';
    homepage = "https://github.com/googlefonts/amstelvar";
    license = lib.licenses.ofl;
    platforms = [ "x86_64-linux" ];
  };
}
