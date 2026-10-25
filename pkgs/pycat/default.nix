{ lib, stdenvNoCC, fetchFromGitHub, python3 }:

let
  # Python 3.13 removed telnetlib from the standard library.
  python = python3.withPackages (ps: [ ps.standard-telnetlib ]);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pycat";
  # Upstream publishes no releases; pin the latest upstream commit.
  version = "0-unstable-2024-07-31";

  src = fetchFromGitHub {
    owner = "cizra";
    repo = "pycat";
    rev = "55c0389b8be3d5623a707698c00a9baa1f393f4e";
    hash = "sha256-ymHW7eCgQlq/FxkQSLorgIJE6h1oFOvM+fWAvZ4wv44=";
  };

  nativeCheckInputs = [ python ];

  dontConfigure = true;
  dontBuild = true;

  # Complete upstream unit suite, plus a compile check of every module.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 tests.py
    python3 -m compileall -q .
    find . -name __pycache__ -type d -prune -exec rm -rf {} +
    runHook postCheck
  '';

  # Upstream is a collection of importable modules run as
  # `python3 ./pycat.py WORLD PORT`.  The launcher keeps that behaviour and
  # lets WORLD be a module in the invoking directory, preferring it over a
  # bundled module of the same name without letting the directory shadow
  # pycat's own modules.
  installPhase = ''
    runHook preInstall
    data=$out/share/pycat
    mkdir -p $data $out/bin
    cp -r . $data
    install -Dm644 -t $out/share/doc/pycat README.md LICENSE
    cat > $out/bin/pycat <<EOF
    #!${python.interpreter}
    import importlib.abc
    import importlib.machinery
    import importlib.util
    import os
    import runpy
    import sys
    source = '$data'
    cwd = os.path.realpath(os.getcwd())
    sys.path[:] = [source] + [entry for entry in sys.path
                              if os.path.realpath(entry or cwd) != cwd
                              and entry != source]
    world_name = sys.argv[1] if len(sys.argv) > 1 else None
    if world_name and world_name.isidentifier():
        world_path = os.path.join(cwd, world_name + '.py')
        if os.path.isfile(world_path):
            class UserWorldLoader(importlib.machinery.SourceFileLoader):
                def exec_module(self, module):
                    sys.path.insert(1, cwd)
                    try:
                        super().exec_module(module)
                    finally:
                        del sys.path[1]
            class UserWorldFinder(importlib.abc.MetaPathFinder):
                def find_spec(self, fullname, path=None, target=None):
                    if fullname == '_pycat_user_world':
                        return importlib.util.spec_from_file_location(
                            fullname, world_path,
                            loader=UserWorldLoader(fullname, world_path))
                    return None
            sys.meta_path.insert(0, UserWorldFinder())
            sys.argv[1] = '_pycat_user_world'
    runpy.run_path(os.path.join(source, 'pycat.py'), run_name='__main__')
    EOF
    chmod 555 $out/bin/pycat
    runHook postInstall
  '';

  # Offline smoke: usage, and a user world module from the working directory
  # taking precedence over the bundled sample world.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # Keep the smoke run from leaving bytecode in the output.
    export PYTHONDONTWRITEBYTECODE=1
    if $out/bin/pycat > usage.out; then exit 1; fi
    grep -q 'Usage:' usage.out
    mkdir smoke
    echo 'raise SystemExit("user world loaded")' > smoke/sample.py
    (cd smoke && ! $out/bin/pycat sample 4000 2> ../world.err)
    grep -q 'user world loaded' world.err
    runHook postInstallCheck
  '';

  meta = {
    description = "Modular Python MUD proxy client";
    longDescription = ''
      Pycat is a modular, hackable MUD client written in Python.  It connects
      to a MUD server and offers an IPv6 loopback proxy for a conventional
      terminal client, retaining output while that frontend reconnects.
      Users select a world module from their current directory to provide
      server settings, triggers, aliases, timers and other client behaviour.
    '';
    homepage = "https://github.com/cizra/pycat";
    license = lib.licenses.unlicense;
    platforms = lib.platforms.unix;
    mainProgram = "pycat";
  };
})
