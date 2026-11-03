{ lib, stdenv, fetchFromGitHub, cmake, bison, flex, jansson, ncurses, makeWrapper }:

stdenv.mkDerivation {
  pname = "nitrohack";
  version = "4.0.4";

  # Tag 4.0.4.
  src = fetchFromGitHub {
    owner = "DanielT";
    repo = "NitroHack";
    rev = "21b9774b24efbdafdd20e152f9b1e5ed2a7b4150";
    hash = "sha256-9l3Vd9G6DJdjrvlMxUQjeXpiAXBJ6XodBaO64rlYZmg=";
  };

  postPatch = ''
    # makedefs embeds the build clock in date.h and nhdat; use the commit time.
    substituteInPlace libnitrohack/util/makedefs.c \
      --replace-fail 'time(&clocktim);' 'clocktim = 1329666608L;'
    # nixpkgs installs the wide ncurses headers as include/curses.h.
    substituteInPlace nitrohack/include/nhcurses.h \
      --replace-fail '<ncursesw/curses.h>' '<curses.h>'
    # Pass the prompt strings as data, not as printf formats.
    substituteInPlace nitrohack/src/dialog.c \
      --replace-fail 'mvwprintw(win, 1, 2, prompt);' 'mvwprintw(win, 1, 2, "%s", prompt);' \
      --replace-fail 'mvwprintw(win, 1, 2, query);' 'mvwprintw(win, 1, 2, "%s", query);'
    # Current CMake rejects reading the LOCATION target property; the tool
    # paths are only used in add_custom_command, where $<TARGET_FILE> works.
    for f in libnitrohack/dat/CMakeLists.txt libnitrohack/src/CMakeLists.txt \
             libnitrohack/util/CMakeLists.txt; do
      sed -i -E 's/get_property\(([A-Z_]+) TARGET ([a-z_]+) PROPERTY LOCATION\)/set(\1 $<TARGET_FILE:\2>)/' $f
      if grep -q 'PROPERTY LOCATION' $f; then
        echo "LOCATION patch failed in $f" >&2; exit 1
      fi
    done
  '';

  nativeBuildInputs = [ cmake bison flex makeWrapper ];
  buildInputs = [ jansson ncurses ];

  # The generated parsers, headers and nhdat form one serial build graph.
  enableParallelBuilding = false;

  env.NIX_CFLAGS_COMPILE = "-std=gnu17";

  cmakeFlags = [
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    # Local curses client with its network client; no PostgreSQL server.
    "-DENABLE_SERVER=OFF"
    "-DENABLE_NETCLIENT=ON"
    "-DBINDIR=${placeholder "out"}/libexec/nitrohack"
    "-DLIBDIR=${placeholder "out"}/libexec/nitrohack"
    "-DDATADIR=${placeholder "out"}/share/nitrohack"
    # Upstream's generated shell launcher is replaced by the wrapper below.
    "-DSHELLDIR=${placeholder "out"}/share/nitrohack/upstream-launcher"
    "-DCMAKE_INSTALL_RPATH=${placeholder "out"}/libexec/nitrohack"
  ];

  postInstall = ''
    rm -r $out/share/nitrohack/upstream-launcher
    makeWrapper $out/libexec/nitrohack/nitrohack $out/bin/nitrohack \
      --prefix LD_LIBRARY_PATH : $out/libexec/nitrohack \
      --prefix TERMINFO_DIRS : ${ncurses}/share/terminfo

    doc=$out/share/doc/nitrohack
    install -Dm644 -t $doc ../README ../doc/Guidebook.txt ../dist/debian/copyright
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/nitrohack/nitrohack
    test -s $out/share/nitrohack/nhdat
    grep -qF 'NITROHACK GENERAL PUBLIC LICENSE' $out/share/nitrohack/license
    grep -qF "$out/share/nitrohack" $out/libexec/nitrohack/nitrohack \
      || grep -rqF "$out/share/nitrohack" $out/libexec/nitrohack
    runHook postInstallCheck
  '';

  meta = {
    description = "Modernized fork of the NetHack terminal dungeon game";
    longDescription = ''
      NitroHack is a modernized, network-capable fork of NetHack. This package
      builds the wide-curses client with its network client mode; the
      PostgreSQL server is not built. Configuration, saves and logs live in
      the user's XDG configuration directory.
    '';
    homepage = "https://github.com/DanielT/NitroHack";
    license = lib.licenses.ngpl;
    mainProgram = "nitrohack";
    platforms = [ "x86_64-linux" ];
  };
}
