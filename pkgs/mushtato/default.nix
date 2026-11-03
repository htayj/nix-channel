{ lib, python3Packages, fetchFromGitHub, qt6, copyDesktopItems, makeDesktopItem }:

python3Packages.buildPythonApplication rec {
  pname = "mushtato";
  version = "1.9.3";
  pyproject = true;

  # v1.9.3 is an annotated tag; pin its peeled release commit.
  src = fetchFromGitHub {
    owner = "N0NJY";
    repo = "mushtato";
    rev = "3fc327a07efff7b421c24022f017b3837add3dec";
    hash = "sha256-UQVjtKBKfLfkdn9VX+l55trxxovbaIiLUIO5GshEGoY=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    asyncssh
    google-re2
    platformdirs
    pyside6
    restrictedpython
  ];

  nativeBuildInputs = [ qt6.wrapQtAppsHook copyDesktopItems ];
  buildInputs = [ qt6.qtbase qt6.qtwayland ];

  # PySide6 programs are Python scripts; pass the Qt environment to the
  # Python wrapper instead of wrapping twice.
  dontWrapQtApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${qtWrapperArgs[@]}")
  '';

  postInstall = ''
    site=$out/${python3Packages.python.sitePackages}

    # setuptools installs only Python modules; the GUI resolves its icon
    # and splash artwork relative to gui/__file__.
    cp -r gui/assets $site/gui/assets

    # Upstream has no console entry point.
    mkdir -p $out/bin
    cat > $out/bin/mushtato <<EOF
    #!${python3Packages.python.interpreter}
    from gui.app import main
    raise SystemExit(main())
    EOF
    chmod 755 $out/bin/mushtato

    for size in 16 24 32 48 64 128 256 512 1024; do
      install -Dm644 gui/assets/icon/$size.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/mushtato.png
    done

    doc=$out/share/doc/mushtato
    install -Dm644 -t $doc LICENSE README.md INSTALL.md CREDITS.md \
      CHANGELOG.md TROUBLESHOOTING.md SPEC.md
    cp -r THIRD-PARTY-LICENSES $doc/THIRD-PARTY-LICENSES
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "mushtato";
      desktopName = "MushTato";
      comment = "Python MUD and MUSH client";
      exec = "mushtato";
      icon = "mushtato";
      categories = [ "Game" "Network" ];
      startupNotify = true;
    })
  ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  # GUI tests need a display; the headless engine suite covers sandboxing
  # and local loopback Telnet, TLS, SOCKS4 and SSH protocol handling.
  enabledTestPaths = [ "tests/engine" ];
  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  pythonImportsCheck = [ "engine" "gui.app" ];

  postInstallCheck = ''
    test -f $out/${python3Packages.python.sitePackages}/gui/assets/icon/1024.png
    test -f $out/share/doc/mushtato/THIRD-PARTY-LICENSES/Qt-LGPL-3.0.txt
  '';

  meta = {
    description = "Cross-platform Python GUI client for MUD and MUSH games";
    longDescription = ''
      MushTato is a graphical MUD and MUSH client inspired by Potato and
      TinyFugue, with tabbed sessions, address-book profiles, Telnet and SSH
      connections, optional TLS and SOCKS4 support, and sandboxed Python
      scripting.  User profiles, logs, maps and plugins live in the
      platformdirs per-user data directory.
    '';
    homepage = "https://github.com/N0NJY/mushtato";
    license = with lib.licenses; [ mit lgpl3Only gpl3Only ];
    mainProgram = "mushtato";
    platforms = [ "x86_64-linux" ];
  };
}
