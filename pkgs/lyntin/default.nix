{ lib, python3Packages, fetchurl }:

python3Packages.buildPythonApplication rec {
  pname = "lyntin";
  version = "5.0.1";
  pyproject = true;

  # Lyntin V is published on PyPI as the lyntinv distribution.
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/db/ba/5cf625b1d669f023ca0c52d4dad2e461e06f054d9f1148c0b0eed28ac8ea/lyntinv-${version}.tar.gz";
    hash = "sha256-0lz6MR1ftaRToYufT4nUd2xFTmfJHxy/CfodJm+2qYs=";
  };

  postPatch = ''
    # The 5.0.1 release still reports 5.0 at runtime.
    substituteInPlace lyntin/__init__.py \
      --replace-fail "__version__ = '5.0'" "__version__ = '5.0.1'" \
      --replace-fail "__version_tuple__ = (5, 0, 0)" "__version_tuple__ = (5, 0, 1)"

    # main() catches its own SystemExit, turning --help and --version into
    # status 1.  Return normally after those completed requests.
    substituteInPlace lyntin/engine.py \
      --replace-fail "        sys.exit(0)" "        return"

    # Ship only the lyntin package, not the top-level scripts/tools dirs.
    cat >> pyproject.toml <<'EOF'

    [tool.hatch.build.targets.wheel]
    packages = ["lyntin"]
    EOF

    # The historical launcher starts with "##!" instead of a shebang.
    substituteInPlace scripts/runlyntin.py \
      --replace-fail '##!/usr/bin/env python' '#!/usr/bin/env python3'
  '';

  build-system = [ python3Packages.hatchling ];

  postInstall = ''
    install -Dm755 scripts/runlyntin.py $out/bin/lyntin
    install -Dm644 -t $out/share/doc/lyntin README.md LICENSE
  '';

  pythonImportsCheck = [ "lyntin" "lyntin.engine" ];

  # Upstream ships a standalone unittest script that expects to run from
  # tools/ against the source tree.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    (cd tools && ${python3Packages.python.interpreter} lyntinunittest.py)
    test "$($out/bin/lyntin --version)" != ""
    $out/bin/lyntin --version | grep -F 5.0.1
    $out/bin/lyntin --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Python MUD client with aliases, triggers and scripting (Lyntin V)";
    longDescription = ''
      Lyntin V is a Python MUD client.  The lyntin command starts the
      upstream text-mode interface.
    '';
    homepage = "https://pypi.org/project/lyntinv/";
    license = lib.licenses.gpl3Plus;
    mainProgram = "lyntin";
    platforms = [ "x86_64-linux" ];
  };
}
