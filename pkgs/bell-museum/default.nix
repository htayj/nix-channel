{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
  jq,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "bell-museum";
  version = "0-unstable-2026-07-26";

  # The Inferno 1e1 submodule (SSH URL, separate limited-use license) is
  # deliberately not fetched; the renderer takes --source for a local checkout.
  src = fetchFromGitHub {
    owner = "htayj";
    repo = "bell-museum";
    rev = "15f0093f4a9808580b09d8d77c018d57961ee635";
    hash = "sha256-fO64tW6mUl/ANd6BeVPykiY1MBOXpkQoOLtzbqs9UoA=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];
  nativeCheckInputs = [ python3 jq ];

  dontConfigure = true;
  dontBuild = true;

  # Upstream tests need the excluded Inferno tree.  Check the renderer's
  # argument parser and the source commit and output count it records.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 scripts/render-inferno-specimens.py --help > /dev/null
    jq -e '.source_commit == "a3c06a9d046c66c83120a4eed91b82dc674719f6"
           and (.outputs | length) == 7' docs/assets/inferno-specimens.json
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/bell-museum
    mkdir -p $data
    cp -r docs scripts $data/
    install -Dm644 -t $data LICENSE README.md
    makeWrapper ${python3.interpreter} $out/bin/bell-museum-render-inferno-specimens \
      --add-flags $data/scripts/render-inferno-specimens.py
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/bell-museum-render-inferno-specimens --help | grep -qF -- '--source'
    runHook postInstallCheck
  '';

  meta = {
    description = "Source-grounded Bell Labs software museum documentation";
    longDescription = ''
      Bell Museum installs source-grounded documentation and deterministic
      Inferno 1e1 specimen-rendering tooling under share/bell-museum.  The
      bell-museum-render-inferno-specimens command takes --source and --output
      (defaulting to sources/inferno-1e1 and docs/assets relative to the
      current directory), so it renders from a separately obtained local
      Inferno checkout without network access.  The Inferno source tree is
      not included: its pinned checkout carries both an MIT notice and a
      separate limited-use license file.
    '';
    homepage = "https://github.com/htayj/bell-museum";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "bell-museum-render-inferno-specimens";
  };
})
