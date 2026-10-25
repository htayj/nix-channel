# CADR bitmap fonts recovered from the MIT CADR source and System 46 runtime,
# published as two complementary release groups.  Select one with `group`.
{ lib, stdenvNoCC, fetchurl, group }:

let
  version = "0.1.2";
  tag = "v${version}";

  groups = {
    latin = {
      hash = "sha256-nGQYpt8SBKoDvi6a8V1AIDPLCtL8LyP0p/UD3lrWIJM=";
      sourceCount = 118;
      runtimeCount = 42;
      description = "CADR bitmap fonts containing visible Basic Latin glyphs";
      longDescription = ''
        CADR Fonts recovers bitmap fonts from the MIT CADR source and System
        46 runtime.  This package contains the complete source and runtime
        artifacts that have at least one visible Basic Latin letter.  It
        installs ISO 10646-1 BDF fonts and deterministic OpenType Bitmap
        conversions while retaining the two historical profiles as separate
        directories.
      '';
    };
    symbols = {
      hash = "sha256-hT4GrA/JnONOBhHoCCqMKccMwaRnIuQR3UTNy4mMGnk=";
      sourceCount = 33;
      runtimeCount = 7;
      description = "CADR specialty bitmap fonts without visible Basic Latin letters";
      longDescription = ''
        CADR Fonts recovers bitmap fonts from the MIT CADR source and System
        46 runtime.  This package contains the complementary specialty set,
        including drawing, symbol, APL, Cyrillic, Greek, mathematical, music,
        and sprite families.  It installs ISO 10646-1 BDF fonts and
        deterministic OpenType Bitmap conversions while retaining the two
        historical profiles as separate directories.
      '';
    };
  };

  info = groups.${group};
in
stdenvNoCC.mkDerivation {
  pname = "cadr-fonts-${group}";
  inherit version;

  src = fetchurl {
    url = "https://github.com/htayj/CADR-fonts/releases/download/${tag}/CADR-fonts-${group}-${tag}.tar.gz";
    inherit (info) hash;
  };

  dontConfigure = true;
  dontBuild = true;

  # The release checksums cover every payload file, including the generated
  # OTB conversions, so this verifies them without rebuilding.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    sha256sum --check --quiet SHA256SUMS
    checkCount() {
      local n
      n=$(find "$1" -type f -name "*.$2" | wc -l)
      if [ "$n" -ne "$3" ]; then
        echo "$1: expected $3 .$2 files, found $n" >&2
        exit 1
      fi
    }
    checkCount fonts/unicode/source bdf ${toString info.sourceCount}
    checkCount fonts/unicode/runtime bdf ${toString info.runtimeCount}
    checkCount fonts/otb/source otb ${toString info.sourceCount}
    checkCount fonts/otb/runtime otb ${toString info.runtimeCount}
    runHook postCheck
  '';

  # Install only Unicode BDFs and their OTB conversions; raw CADR-code BDFs
  # remain provenance-only.
  installPhase = ''
    runHook preInstall
    fontRoot=$out/share/fonts/cadr-fonts/${group}
    dataRoot=$out/share/cadr-fonts/${group}
    docRoot=$out/share/doc/cadr-fonts-${group}
    mkdir -p $fontRoot/bdf $fontRoot/otb $dataRoot
    cp -r fonts/unicode/source $fontRoot/bdf/source
    cp -r fonts/unicode/runtime $fontRoot/bdf/runtime
    cp -r fonts/otb/source $fontRoot/otb/source
    cp -r fonts/otb/runtime $fontRoot/otb/runtime
    cp -r metadata $dataRoot/metadata
    install -Dm644 -t $dataRoot RELEASE-MANIFEST.json SHA256SUMS
    install -Dm644 -t $docRoot LICENSE.project LICENSE.source README.release.md
    runHook postInstall
  '';

  meta = {
    inherit (info) description longDescription;
    homepage = "https://github.com/htayj/CADR-fonts";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.all;
  };
}
