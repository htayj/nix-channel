{
  lib,
  buildRubyGem,
  fetchurl,
  ruby,
  ruby-memoist,
  ruby-sax-machine,
}:

let
  # The bundled teilite.xsd matches TEI P5 1.1.0's dated schema; ship its
  # contemporaneous grant and the selected GPL version alongside it.
  teiCopying = fetchurl {
    url = "https://tei-c.org/Vault/P5/1.1.0/doc/tei-p5-doc/en/html/COPYING.txt";
    hash = "sha256-XgOLc08ezoqdgqju2bXZanPfNMEYQeCdc94pmd24/lI=";
  };
  gpl3 = fetchurl {
    url = "https://www.gnu.org/licenses/gpl-3.0.txt";
    hash = "sha256-OXLcl0T2SZ8Pmy2/dmlvKuetivmyPd5m1q+Gyd+zaYY=";
  };
  # The interpreter wrapper prefixes GEM_PATH with this environment, so the
  # channel gems must be part of it for RubyGems dependency activation.
  rubyWithDeps = ruby.withPackages (ps: [
    ps.builder
    ps.csv
    ps.json
    ps.nokogiri
    ruby-memoist
    ruby-sax-machine
  ]);
in
buildRubyGem rec {
  gemName = "proiel";
  version = "1.3.3";
  inherit ruby;

  # The released gem carries only lib/, the schemas and README/LICENSE; the
  # repository's corpus-derived spec data is not part of it.
  source.sha256 = "sha256-85ODoOZv2H0E0MByXRbGf8/C2uqOBjk1dEQ5pzhu24Y=";
  dontBuild = false;

  propagatedBuildInputs = [
    ruby.gems.builder
    # Ruby 3.4 no longer ships csv as a default gem; lib/proiel.rb requires it.
    ruby.gems.csv
    ruby.gems.json
    ruby.gems.nokogiri
    ruby-memoist
    ruby-sax-machine
  ];

  # proiel only calls Builder::XmlMarkup.new(target:, indent:) and JSON.parse,
  # both available in the current builder 3.3 and json 2.x releases.
  postPatch = ''
    substituteInPlace "$gemspec" \
      --replace-fail '["~> 3.2.4".freeze]' '[">= 3.2.4".freeze]' \
      --replace-fail '["~> 2.3.0".freeze]' '[">= 2.3.0".freeze]'

    substituteInPlace lib/proiel/proiel_xml/proiel-1.0/xml.xsd \
      --replace-fail '<xs:schema' '<!-- XML namespace schema: Copyright 2009 W3C. All Rights Reserved.
    Distributed under https://www.w3.org/copyright/software-license-2002/
    WITHOUT ANY WARRANTY, including MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    2026-11-23: added this required attribution notice; schema unchanged. -->
    <xs:schema'
  '';

  postInstall = ''
    doc=$out/share/doc/proiel
    install -Dm444 LICENSE README.md -t $doc
    install -Dm444 ${./schema-licenses.txt} $doc/SCHEMA-LICENSES
    install -Dm444 ${teiCopying} $doc/TEI-COPYING
    install -Dm444 ${gpl3} $doc/COPYING-GPL-3
    install -Dm444 ${./minimal.xml} $out/share/proiel/examples/minimal.xml
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    (cd "$TMPDIR" && GEM_PATH="$out/${ruby.gemPath}" \
      ${rubyWithDeps}/bin/ruby ${./smoke.rb} $out/share/proiel/examples/minimal.xml)
    runHook postInstallCheck
  '';

  meta = {
    description = "Read and manipulate PROIEL dependency treebanks";
    longDescription = ''
      This Ruby library reads, validates, and manipulates treebanks using the
      PROIEL dependency format.  It provides sentence and token objects,
      annotation schemas, dictionaries, and valency analysis.  This package
      contains no external treebank corpora; its example uses synthetic data.
    '';
    homepage = "https://github.com/syntacticus/proiel";
    license = with lib.licenses; [
      mit
      gpl3Plus
      w3c
    ];
    platforms = [ "x86_64-linux" ];
  };
}
