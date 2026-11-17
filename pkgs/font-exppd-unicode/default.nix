# ExpPD Unicode Sans: the complete Noto Sans Regular and AOSP Gingerbread
# Droid Sans Fallback TrueType data merged into one font by compose.py.
{ lib, stdenvNoCC, fetchurl, python3 }:

let
  # Tip of AOSP's gingerbread branch.  Its fallback font keeps the older
  # CJK and Hangul repertoire; later files of the same name differ.
  droidCommit = "9b19b93a5b0018414784cfdc070b462ea65451d8";
  droidUrl = file:
    "https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/${droidCommit}/data/fonts/${file}";

  # notofonts.github.io tag noto-monthly-release-2026.01.01, the release
  # compose.py names in the installed NOTICE.txt.
  notoRelease = "noto-monthly-release-2026.01.01";
  notoCommit = "e3bdd5e75581e2b46d93343ec98594f3c89669c0";
  notoUrl = path:
    "https://raw.githubusercontent.com/notofonts/notofonts.github.io/${notoCommit}/fonts/${path}";

  droidFallback = fetchurl {
    url = droidUrl "DroidSansFallback.ttf";
    hash = "sha256-9jaU8tCRDi8x0AqBjiOxPI46JK8EZyeJwZwfscnaJM4=";
  };
  droidNotice = fetchurl {
    url = droidUrl "NOTICE";
    name = "DroidSansFallback-NOTICE";
    hash = "sha256-OHUSRTieHiP3Pm9ThLXL5/qXLMRBDFrcnASwgqC5Vho=";
  };
  notoSans = fetchurl {
    url = notoUrl "NotoSans/hinted/ttf/NotoSans-Regular.ttf";
    hash = "sha256-R4xVjqcWAzzWDANDj2KN+nVpTc9rX21QWi8F/StPOCM=";
  };
  notoLicense = fetchurl {
    url = notoUrl "LICENSE";
    name = "Noto-OFL.txt";
    hash = "sha256-8glbCL7QiyOm/iYRL81nmivuPwAu7wd+sF0hXtEFG9g=";
  };

  python = python3.withPackages (ps: [ ps.fonttools ]);
in
stdenvNoCC.mkDerivation {
  pname = "font-exppd-unicode";
  version = "1";

  dontUnpack = true;
  dontConfigure = true;

  nativeBuildInputs = [ python ];

  # compose.py is the Guix channel's composer.  Its provenance line names the
  # Guix Noto package; here the TTF comes from the Noto release itself.
  buildPhase = ''
    runHook preBuild
    substitute ${./compose.py} compose.py \
      --replace-fail '"Noto input: Guix font-google-noto " + args.noto_version + " (ttf output)"' \
                     '"Noto input: notofonts.github.io " + args.noto_version + " (hinted TTF)"'
    python3 compose.py \
      --noto ${notoSans} \
      --noto-version ${notoRelease} \
      --droid ${droidFallback} \
      --noto-license ${notoLicense} \
      --droid-notice ${droidNotice} \
      --output ExpPDUnicodeSans.ttf \
      --doc-dir notices
    runHook postBuild
  '';

  # The composer already refuses to drop a source code point.  Reopen the
  # saved font and check its identity, scale and both repertoires.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 - <<'EOF'
    from fontTools.ttLib import TTFont

    font = TTFont("ExpPDUnicodeSans.ttf")
    cmap = font.getBestCmap()
    names = {record.nameID: record.toUnicode() for record in font["name"].names}
    assert font["head"].unitsPerEm == 1000, font["head"].unitsPerEm
    assert names[1] == "ExpPD Unicode Sans", names[1]
    assert names[6] == "ExpPDUnicodeSans-Regular", names[6]
    sources = set()
    for path in ("${notoSans}", "${droidFallback}"):
        sources |= set(TTFont(path).getBestCmap())
    assert sources <= set(cmap), sorted(sources - set(cmap))[:10]
    # Latin and Cyrillic from Noto; CJK, kana and Hangul from Droid.
    for codepoint in (0x41, 0x416, 0x4E2D, 0x3042, 0xD55C):
        assert codepoint in cmap, hex(codepoint)
        assert font["glyf"][cmap[codepoint]].numberOfContours != 0, hex(codepoint)
    print("font-exppd-unicode check ok:", len(cmap), "code points,",
          font["maxp"].numGlyphs, "glyphs")
    EOF
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/fonts/truetype ExpPDUnicodeSans.ttf
    install -Dm644 -t $out/share/doc/font-exppd-unicode notices/*
    runHook postInstall
  '';

  meta = {
    description = "Composite Unicode font for Experienced Pixel Dungeon";
    longDescription = ''
      ExpPD Unicode Sans combines the complete Noto Sans Regular and AOSP
      Gingerbread Droid Sans Fallback font data in one TrueType font.  Noto
      supplies shared character mappings, while the fallback supplies its
      additional CJK and Hangul repertoire, rescaled from 256 to 1000 units
      per em.  The composite has a neutral family name and fixed font
      timestamps, and installs the original copyright and license notices.

      The font is composed from upstream TrueType data with FontTools, not
      compiled from outline-design sources, and its typography differs from
      the game's original font.  The modified font as a whole is distributed
      under SIL OFL 1.1; the Droid data retains its Apache 2.0 notices.
    '';
    homepage = "https://github.com/TrashboxBobylev/Experienced-Pixel-Dungeon";
    license = with lib.licenses; [ ofl asl20 ];
    platforms = lib.platforms.all;
  };
}
