{ lib, stdenvNoCC, fetchFromGitHub, perl }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "nrl-text-to-phoneme";
  # Upstream publishes no releases; pin the latest upstream commit.
  version = "0-unstable-f99c64a";

  src = fetchFromGitHub {
    owner = "greg-kennedy";
    repo = "p5-NRL-TextToPhoneme";
    rev = "f99c64ac84cf483b5ad51422e05277a3a383d869";
    hash = "sha256-ofI1sCwqEEH1n2go2y2JcB4awkhKtNVOHEPGu1XEi6k=";
  };

  # The script only needs Perl core modules (List::Util, JSON::PP).
  nativeBuildInputs = [ perl ];
  buildInputs = [ perl ];

  dontConfigure = true;
  dontBuild = true;

  # The default rules path is relative to the working directory.  Point it at
  # the installed English-to-IPA table; an explicit first argument still
  # selects another rule set.
  postPatch = ''
    patchShebangs NRL-TTP.pl test.pl
    substituteInPlace NRL-TTP.pl \
      --replace-fail "'rules/eng_to_ipa.json'" \
                     "'$out/share/nrl-text-to-phoneme/rules/eng_to_ipa.json'"
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 NRL-TTP.pl $out/bin/nrl-text-to-phoneme
    install -Dm444 -t $out/share/nrl-text-to-phoneme/rules rules/*.json
    install -Dm444 -t $out/share/doc/nrl-text-to-phoneme README.md LICENSE
    runHook postInstall
  '';

  # Upstream's test suite runs ./NRL-TTP.pl, whose default rules path now
  # names the installed table; also exercise the installed command from an
  # unrelated directory.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    perl test.pl
    mkdir smoke
    (cd smoke && echo RATIO | $out/bin/nrl-text-to-phoneme > ../ratio.out)
    grep -qx '/R//EY//SH//OW//< >/' ratio.out
    runHook postInstallCheck
  '';

  meta = {
    description = "English text-to-phoneme converter using the NRL rules";
    longDescription = ''
      NRL-TTP converts normalized English text to phoneme sequences using the
      Naval Research Laboratory letter-to-sound rules described by Elovitz et
      al.  It installs the Perl command-line converter with its English-to-IPA
      rule table, plus the upstream Votrax and SP0256 rule tables for explicit
      use.
    '';
    homepage = "https://github.com/greg-kennedy/p5-NRL-TextToPhoneme";
    license = lib.licenses.unlicense;
    platforms = lib.platforms.unix;
    mainProgram = "nrl-text-to-phoneme";
  };
})
