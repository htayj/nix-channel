{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  python3Minimal,
}:

buildNpmPackage (finalAttrs: {
  pname = "computer-builder";
  version = "0.1.0-unstable-2026-05-14";

  src = fetchFromGitHub {
    owner = "htayj";
    repo = "computer-builder";
    rev = "3f7e89d9e6ecdffa7fa11ab2231b2bfbbe38b8fa";
    hash = "sha256-VUQvov1dSV6h2mXQ5E5y5fEOtgw81lFg36LBhmC5pOo=";
  };

  # Upstream's complete package-lock.json: 87 registry entries.  The compiler,
  # test runner and bundler in it are build-time tools; the installed site is
  # static.
  npmDepsHash = "sha256-UWiRgB6NsJ6O4BDuecTftBlJKWsPNKehWQ5IJUzXbXM=";

  nativeBuildInputs = [ makeWrapper ];

  # The default `build` script type-checks, then bundles into dist/.

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';

  # An application, not an npm module: install the built site and a launcher
  # serving it on localhost.  Arguments reach http.server, so a port may follow.
  installPhase = ''
    runHook preInstall

    site=$out/share/computer-builder
    mkdir -p "$site"
    cp -r dist/. "$site"

    doc=$out/share/doc/computer-builder
    install -Dm444 -t "$doc" README.md LICENSE
    # The bundle contains these libraries; keep their notices beside it.
    for module in react react-dom scheduler effect @standard-schema/spec fast-check pure-rand; do
      notices=$(find "node_modules/$module" -maxdepth 1 -type f -iname 'licen[cs]e*')
      test -n "$notices"
      install -Dm444 -t "$doc/bundled/$module" $notices
    done

    makeWrapper ${python3Minimal.interpreter} $out/bin/computer-builder \
      --add-flags "-m http.server --bind 127.0.0.1 --directory $site"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${python3Minimal.interpreter} ${./check-serve.py} \
      $out/bin/computer-builder $out/share/computer-builder
    runHook postInstallCheck
  '';

  meta = {
    description = "Interactive PC component catalog web application";
    longDescription = ''
      Computer Builder is a locally hosted web application for exploring PC
      component catalogs.  It validates structured GPU, CPU, motherboard, and
      power supply data, and presents the GPU catalog with sortable
      specifications, resources, capabilities, and performance marks.  The
      launcher serves the static application on localhost, port 8000 unless a
      port is given.
    '';
    homepage = "https://github.com/htayj/computer-builder";
    # The application is AGPL; the bundled libraries are MIT.
    license = with lib.licenses; [
      agpl3Plus
      mit
    ];
    mainProgram = "computer-builder";
    platforms = [ "x86_64-linux" ];
  };
})
