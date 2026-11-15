{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  makeWrapper,
  nodejs,
}:

let
  notice = name: url: hash: fetchurl {
    name = "persephil-${name}";
    inherit url hash;
  };
  # Six locked archives are published without their license text.  Each file
  # comes from the upstream commit, or the version-pinned Debian copyright
  # file, that states the grant for exactly the locked version.
  suppliedNotices = {
    "buffers/LICENSE-GRANT-MIT-X11" = notice "buffers-0.1.1-MIT-X11-grant"
      "https://raw.githubusercontent.com/bitpay/node-buffers/1b745ee35d33eb166e15ef1866073a07c6d7de87/README.markdown"
      "sha256-PUOXGkRO5XjO/nXFpTKtDl5710ku1nIVRfLMcS0MDJA=";
    "buffers/LICENSE-MIT" = notice "buffers-0.1.1-MIT-notice"
      "https://sources.debian.org/data/main/n/node-buffers/0.1.1-2/debian/copyright"
      "sha256-l0I6A7xEdqmN4r8/p+//VbPzONp2p7PL90e03G9SoFY=";
    "chainsaw/LICENSE-MIT-X11" = notice "chainsaw-0.1.0-MIT-X11-notice"
      "https://sources.debian.org/data/main/n/node-chainsaw/0.1.0-2/debian/copyright"
      "sha256-5pgdOVlC8ofJUDlo3+/akXXetLzSsv8ipXzZZV6oUuU=";
    "saxes/LICENSE" = notice "saxes-5.0.1-LICENSE"
      "https://raw.githubusercontent.com/lddubeau/saxes/6ef6a275b20f19cb67808daf0d8f64e06aaf5b0e/LICENSE"
      "sha256-D6wjdDgGIbIua1BFEFdyGpxSk1sC0W0Qap8EiX8GHQ4=";
    "saxes/AUTHORS" = notice "saxes-5.0.1-AUTHORS"
      "https://raw.githubusercontent.com/lddubeau/saxes/6ef6a275b20f19cb67808daf0d8f64e06aaf5b0e/AUTHORS"
      "sha256-Tpv+4dDtCovay9wazwqZmxcFSqe/xS7/AOhpRyvipcw=";
    "set-immediate-shim/LICENSE" = notice "set-immediate-shim-1.0.1-LICENSE"
      "https://raw.githubusercontent.com/sindresorhus/set-immediate-shim/4c50df7ade5a368e106fee82351ee0a378c990f7/license"
      "sha256-b7l1RhHCD2ZJ9ogF6MmQ6DJh8pMW4p3p5s7a5ge4Y0w=";
    "json-schema/LICENSE" = notice "json-schema-0.2.3-LICENSE"
      "https://raw.githubusercontent.com/kriszyp/json-schema/4f3db68fb98d9444850fec0ef5ed981c8beacfb6/LICENSE"
      "sha256-kDfJRvcOY5feKXRfSMrr+AwrEsHUJtHSNYHLHIWVlo4=";
    # binary 0.3.0 declares MIT without any notice; these are the canonical
    # SPDX terms, not an upstream-authored copyright statement.
    "binary/LICENSE-MIT-TERMS" = notice "binary-0.3.0-MIT-terms"
      "https://raw.githubusercontent.com/spdx/license-list-data/d46e94e2c78ceede1cfc63cfa0396472d2798d4c/text/MIT.txt"
      "sha256-sFeF+fGOZxa6tjQksRRUUTuZQ6IiWVtwQRAJIC/FkrU=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "persephil";
  version = "1.0.0-unstable-2021-05-22";

  src = fetchFromGitHub {
    owner = "cookinrelaxin";
    repo = "persephil";
    rev = "1e10afbbcb8c6f56d2cc22db0c915a9d64ecd8d6";
    hash = "sha256-tXZhAq5ttKGgljdDqi4+6iV94ie37hIaerdftSsa7bQ=";
  };

  # Upstream's complete package-lock.json: 214 registry entries, no native
  # addons and no install scripts.
  npmDepsHash = "sha256-Acd/rrxanFFq/RtRtuRwH2vreNp8LNIHVw2z1SGwWV8=";

  nativeBuildInputs = [ makeWrapper ];

  # npm's package name is lower-case, also on case-sensitive file systems.
  postPatch = ''
    substituteInPlace main.js \
      --replace-fail "require('excelJS')" "require('exceljs')"
  '';

  # Plain JavaScript: upstream has no build script.
  dontNpmBuild = true;

  doCheck = true;
  # package.json's `test` script is the npm-init placeholder that exits 1.
  checkPhase = ''
    runHook preCheck
    node --check main.js
    node -e "for (const name of ['exceljs', 'got', 'jsdom', 'moment']) require(name)"
    runHook postCheck
  '';

  postInstall = ''
    module=$out/lib/node_modules/persephil

    ${lib.concatStrings (lib.mapAttrsToList (path: file: ''
      test ! -e "$module/node_modules/${path}"
      install -Dm444 ${file} "$module/node_modules/${path}"
    '') suppliedNotices)}

    install -Dm444 -t $out/share/doc/persephil README.md LICENSE package-lock.json

    # No --chdir: upstream writes its dated workbook in the caller's working
    # directory.
    makeWrapper ${lib.getExe nodejs} $out/bin/persephil \
      --add-flags "$module/main.js"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node ${./check-export.js} $out/bin/persephil $out/lib/node_modules/persephil
    runHook postInstallCheck
  '';

  meta = {
    description = "Export legacy PhiloLogic Latin search results to spreadsheets";
    longDescription = ''
      Persephil exports a legacy PhiloLogic HTML keyword-in-context result page
      to an XLSX workbook.  It takes the search-results URL as its argument and
      writes a dated workbook in the caller's working directory, with search
      matches in bold and the work and passage references in their own
      columns.  It parses the legacy HTML pages, not the current PhiloLogic
      JSON API.
    '';
    homepage = "https://github.com/cookinrelaxin/persephil";
    # The authored LICENSE is GPLv3; package.json's ISC field is the untouched
    # npm-init template.  The others cover the installed node_modules tree.
    license = with lib.licenses; [
      gpl3Only
      mit
      isc
      x11
      asl20
      bsd2
      bsd3
      unlicense
      zlib
    ];
    mainProgram = "persephil";
    platforms = [ "x86_64-linux" ];
  };
})
