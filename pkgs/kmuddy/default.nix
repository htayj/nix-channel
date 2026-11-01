{
  lib,
  stdenv,
  fetchgit,
  cmake,
  pkg-config,
  zlib,
  kdePackages,
}:

let
  rev = "e88c93646c21b31456072f75baf9738eacb9e5b6";

  # KMuddy has no current release tag.  This master commit introduced the
  # Qt 6/KF 6 port and version 1.1.
  src = fetchgit {
    url = "https://invent.kde.org/games/kmuddy.git";
    inherit rev;
    hash = "sha256-2v3InBZbIEHUL7uJw/AZ3j5o68+FNk6j0QXAKJsVsSc=";
  };

  # The top-level project does not build the bundled MXP parser, but its
  # optional MXP support looks for a system libmxp.  Build it privately from
  # the same source tree.
  libmxp = stdenv.mkDerivation {
    pname = "libmxp";
    version = "0.2.4";
    inherit src;
    sourceRoot = "${src.name}/libmxp";

    nativeBuildInputs = [ cmake ];

    # CMake 4 rejects the historical 2.3 minimum; only basic target and
    # install commands are used.
    postPatch = ''
      substituteInPlace CMakeLists.txt \
        --replace-fail 'cmake_minimum_required(VERSION 2.3)' \
                       'cmake_minimum_required(VERSION 3.16)'
    '';

    postInstall = ''
      install -Dm644 -t $out/share/doc/libmxp \
        ../AUTHORS ../COPYING ../COPYING.LIB ../NEWS ../README ../TODO
    '';

    meta = {
      description = "Parser for MUD Extension Protocol streams, bundled with KMuddy";
      homepage = "https://invent.kde.org/games/kmuddy";
      license = lib.licenses.lgpl2Plus;
      platforms = [ "x86_64-linux" ];
    };
  };
in
stdenv.mkDerivation {
  pname = "kmuddy";
  version = "1.1-unstable-e88c936";
  inherit src;

  # Without a new-style kmuddyrc (every first launch), cGlobalSettings::load
  # takes the old-config path and never hands the plug-in manager a config
  # group, so loading plug-ins dereferences an invalid KConfigGroup.  Bind
  # the "Plugins" group before either path runs.
  postPatch = ''
    substituteInPlace libs/cglobalsettings.cpp \
      --replace-fail '  if (!config->hasGroup ("Version Info")) {' \
                     $'  cPluginManager::self()->setConfigGroup (config->group ("Plugins"));\n  if (!config->hasGroup ("Version Info")) {'
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    kdePackages.extra-cmake-modules
    kdePackages.wrapQtAppsHook
  ];

  buildInputs = with kdePackages; [
    karchive
    kcmutils
    kcodecs
    kcompletion
    kconfig
    kcoreaddons
    kiconthemes
    ki18n
    kio
    knotifications
    kservice
    kstatusnotifieritem
    ktextwidgets
    kwidgetsaddons
    kxmlgui
    qtbase
    qtdeclarative
    qtmultimedia
    libmxp
    zlib
  ];

  postInstall = ''
    install -Dm644 -t $out/share/doc/kmuddy \
      ../LICENSE ../libmxp/COPYING ../libmxp/COPYING.LIB
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/bin/kmuddy
    # The build must have found the private MXP library.
    grep -q '#define HAVE_MXP' config-mxp.h
    runHook postInstallCheck
  '';

  passthru = { inherit libmxp; };

  meta = {
    description = "KDE MUD client with scripting and protocol extensions";
    longDescription = ''
      KMuddy is a graphical MUD client for KDE.  It provides aliases,
      triggers, timers, scripting, plugins, logging, automapping, MCCP
      compression, MSP sound support, and MXP parsing through a private
      build of the bundled libmxp.
    '';
    homepage = "https://invent.kde.org/games/kmuddy";
    license = [
      lib.licenses.gpl2Plus
      lib.licenses.lgpl2Plus
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "kmuddy";
  };
}
