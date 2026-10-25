# Atari ST 8x16 system bitmap font, extended with Cyrillic glyphs.
{ lib, stdenvNoCC, fetchFromGitHub, bdftopcf }:

stdenvNoCC.mkDerivation {
  pname = "atarist-font";
  version = "0-unstable-52b91b2";

  src = fetchFromGitHub {
    owner = "ntwk";
    repo = "atarist-font";
    rev = "52b91b269f671c1e3816a685a6bd3d7d0e6da0cc";
    hash = "sha256-VA4BelsNPwNV7ZJtrmFe4XIUgJFhApH+JZUjyXZsBzo=";
  };

  nativeBuildInputs = [ bdftopcf ];

  # The BDF contains 322 glyph records but its header declares 324.
  # Correct only that declaration; no glyph data changes.
  postPatch = ''
    test "$(grep -c '^STARTCHAR' atarist-normal.bdf)" = 322
    substituteInPlace atarist-normal.bdf --replace-fail 'CHARS 324' 'CHARS 322'
  '';

  dontConfigure = true;

  # bdftopcf rejects malformed BDF input and produces the optional PCF
  # format documented upstream.
  buildPhase = ''
    runHook preBuild
    bdftopcf -o atarist-normal.pcf atarist-normal.bdf
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/fonts/misc atarist-normal.bdf atarist-normal.pcf
    install -Dm644 -t $out/share/doc/atarist-font LICENSE README.md
    runHook postInstall
  '';

  meta = {
    description = "Atari ST bitmap font";
    longDescription = ''
      Atarist is an 8x16 monospaced bitmap font based on the high-resolution
      system font of the Atari ST home computer.  This package installs the
      Unicode-encoded BDF font, extended with Cyrillic glyphs, and a PCF
      conversion.
    '';
    homepage = "https://github.com/ntwk/atarist-font";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.all;
  };
}
