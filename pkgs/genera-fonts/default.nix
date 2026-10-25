# Genera 8.5 resident bitmap fonts, published as two complementary release
# groups.  Select one with `group`.
{ lib, stdenvNoCC, fetchurl, group }:

let
  version = "0.1.3";
  tag = "v${version}";

  groups = {
    latin = {
      hash = "sha256-cAH4K/A5Q9YcwUgbB+SLuMbR/9AIgM1WV8hkaBTCrmc=";
      description = "Genera bitmap fonts containing visible Basic Latin glyphs";
      longDescription = ''
        This package contains complete Genera 8.5 resident fonts selected by
        visible Basic Latin glyph content.  It installs ISO 10646-1 BDF
        typefaces and display-equivalent OTB conversions, with required
        provenance and notices.
      '';
    };
    symbols = {
      hash = "sha256-534ZOLpwvtWJ5/2s9BNNCauKTvB8Hak4dYLf06qG8nY=";
      description = "Genera specialty bitmap fonts without visible Basic Latin glyphs";
      longDescription = ''
        This package contains the complementary Genera 8.5 resident specialty
        fonts without visible Basic Latin letters.  It installs ISO 10646-1
        BDF typefaces and display-equivalent OTB conversions, with required
        provenance and notices.
      '';
    };
  };

  info = groups.${group};
in
stdenvNoCC.mkDerivation {
  pname = "genera-fonts-${group}";
  inherit version;

  src = fetchurl {
    url = "https://github.com/htayj/genera-fonts/releases/download/${tag}/Genera-fonts-${group}-${tag}.tar.gz";
    inherit (info) hash;
  };

  dontConfigure = true;
  dontBuild = true;

  # The release carries checksums for every file it ships.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    sha256sum --check --quiet SHA256SUMS
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    fontRoot=$out/share/fonts/genera-fonts/${group}
    dataRoot=$out/share/genera-fonts/${group}
    docRoot=$out/share/doc/genera-fonts-${group}
    mkdir -p $fontRoot $dataRoot
    cp -r fonts/. $fontRoot
    cp -r metadata $dataRoot/metadata
    install -Dm644 -t $dataRoot RELEASE-MANIFEST.json SHA256SUMS
    install -Dm644 -t $docRoot LICENSE NOTICE.md README.release.md
    runHook postInstall
  '';

  meta = {
    inherit (info) description longDescription;
    homepage = "https://github.com/htayj/genera-fonts";
    license = [
      lib.licenses.bsd3
      {
        shortName = "genera-fonts-notice";
        fullName = "Typeface redistribution basis; not a license grant";
        url = "https://github.com/htayj/genera-fonts/blob/${tag}/NOTICE.md";
        free = true;
        redistributable = true;
      }
    ];
    platforms = lib.platforms.all;
  };
}
