{
  lib,
  stdenv,
  fetchFromGitHub,
  libsForQt5,
  ruby,
  copyDesktopItems,
  makeDesktopItem,
}:

stdenv.mkDerivation {
  pname = "frostbite";
  version = "1.18.2";

  src = fetchFromGitHub {
    owner = "matoom";
    repo = "frostbite";
    # Tag v1.18.2.
    rev = "21e6306d0600dcc0301bc66c3c886d56056827d2";
    hash = "sha256-nugpXbeDt+GikW//som4IwR9vBFtmRo5hsbFlGHcjus=";
  };

  patches = [
    # Upstream expects a writable directory beside the executable.  Read
    # program resources from FROSTBITE_RESOURCE_DIR and keep client and API
    # settings, profiles, logs and snapshots in the XDG user directories.
    ./xdg-state.patch
    # The first run copies client.ini and the default profiles out of the
    # read-only store, and QFile::copy carries the source permissions over.
    ./writable-user-copies.patch
    # Log4Qt opened the appenders configured in log.ini by their relative
    # names, in the current directory.  Resolve them under the user data
    # directory, where log rotation already expects them.
    ./log-state-dir.patch
  ];

  # The release configuration appends a step that bundles Qt libraries,
  # plugins and a second application tree into a tarball.  Put it behind a
  # CONFIG name nothing sets.  The bundled Log4Qt and the event handler pass
  # a message to fprintf and qFatal as the format string.
  postPatch = ''
    substituteInPlace gui/gui.pro \
      --replace-fail 'CONFIG(release, debug|release) {' 'frostbite_release_bundle {'
    substituteInPlace log4qt/src/log4qt/varia/debugappender.cpp \
      --replace-fail 'fprintf(stderr, message.toLocal8Bit().data());' \
                     'fprintf(stderr, "%s", message.toLocal8Bit().data());'
    substituteInPlace gui/guiapplication.cpp \
      --replace-fail 'qFatal(errorMsg.toLocal8Bit().data());' \
                     'qFatal("%s", errorMsg.toLocal8Bit().data());'
  '';

  nativeBuildInputs = [
    libsForQt5.qmake
    libsForQt5.wrapQtAppsHook
    copyDesktopItems
  ];

  buildInputs = [
    libsForQt5.qtbase
    libsForQt5.qtmultimedia
    libsForQt5.qtwayland
  ];

  # The top-level project builds the client and tests/testxml.
  qmakeFlags = [ "FrostBite.pro" ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export HOME=$TMPDIR/check-home
    mkdir -p $HOME
    QT_QPA_PLATFORM=offscreen \
    QT_PLUGIN_PATH=${libsForQt5.qtbase.bin}/${libsForQt5.qtbase.qtPluginPrefix} \
      tests/testxml
    runHook postCheck
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "frostbite";
      desktopName = "Frostbite";
      comment = "DragonRealms MUD client";
      exec = "frostbite";
      icon = "frostbite";
      categories = [ "Game" "RolePlaying" ];
      terminal = false;
    })
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 Frostbite $out/bin/frostbite

    # Program resources.  Only client.ini and the profiles are copied to
    # user directories, on first use.
    share=$out/share/frostbite
    mkdir -p $share/config
    cp -r deploy/common/scripts deploy/common/maps deploy/common/sounds \
      deploy/common/security deploy/linux/profiles $share/
    install -m644 deploy/common/client.ini $share/config/
    install -m644 deploy/common/log.ini $share/

    install -Dm644 gui/images/shield_64.png \
      $out/share/icons/hicolor/64x64/apps/frostbite.png

    # README.md carries the MIT statement.  The bundled Log4Qt ships its
    # licence and notice; the Qt Solutions and Cleanlooks terms are in their
    # source headers.
    doc=$out/share/doc/frostbite
    install -Dm644 -t $doc README.md
    install -Dm644 -t $doc/licenses \
      log4qt/LICENSE-2.0.txt log4qt/NOTICE.txt \
      singleapp/qtlocalpeer.cpp cleanlooks/qcleanlooksstyle.cpp
    runHook postInstall
  '';

  # Scripts run under the "ruby" found on PATH unless the user configures
  # another interpreter.
  qtWrapperArgs = [
    "--set"
    "FROSTBITE_RESOURCE_DIR"
    "${placeholder "out"}/share/frostbite"
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ ruby ])
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f $out/share/applications/frostbite.desktop
    test -f $out/share/frostbite/security/auth-service.pem
    test -f $out/share/frostbite/log.ini
    ${ruby}/bin/ruby -c $out/share/frostbite/scripts/lib/main.rb

    # There is no command-line interface: start the window off screen and
    # require it to be running when stopped, with its first-run settings and
    # profiles in the user directories and writable.
    export HOME=$TMPDIR/install-check-home
    export XDG_CONFIG_HOME=$HOME/config
    export XDG_DATA_HOME=$HOME/data
    mkdir -p $HOME
    status=0
    QT_QPA_PLATFORM=offscreen timeout 10 $out/bin/frostbite || status=$?
    find $HOME -type f | sort
    test $status = 124
    test -w $XDG_CONFIG_HOME/matoom/Frostbite/client.ini
    test -w $XDG_DATA_HOME/matoom/Frostbite/profiles/frostbite/general.ini
    test -f $XDG_DATA_HOME/matoom/Frostbite/logs/main/main.log
    runHook postInstallCheck
  '';

  meta = {
    description = "Qt MUD client for DragonRealms";
    longDescription = ''
      Frostbite is a graphical MUD client for DragonRealms.  It provides
      windowed game output, scripting through Ruby, sound notifications,
      profiles, logging, maps and snapshots.  Program resources are read
      from share/frostbite; client and API settings live in the XDG
      configuration directory, and profiles, logs and snapshots in the XDG
      data directory, both under matoom/Frostbite.
    '';
    homepage = "https://github.com/matoom/frostbite";
    # Frostbite is MIT.  It bundles Log4Qt (Apache-2.0), the Qt Solutions
    # single-application code (BSD-3-Clause) and the Cleanlooks style, which
    # is offered under LGPL-2.1 with the Qt exception or GPL-3.0.
    license = with lib.licenses; [
      mit
      asl20
      bsd3
      lgpl21Only
      gpl3Only
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "frostbite";
  };
}
