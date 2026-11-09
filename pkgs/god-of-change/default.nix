{ lib, stdenv, fetchurl, unzip, libtcod }:

# libtcod is the private 1.5.1 renderer built for dwarftown
# (dwarftown.libtcod); Nixpkgs only packages modern libtcod.
let
  archive = "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/godofchange";

  # The Linux release supplies the original font and its notices.  Its
  # precompiled game and libraries are never extracted.
  assets = fetchurl {
    name = "god-of-change-original-assets.tar.gz";
    url = "${archive}/God%20of%20Change%20-%20Linux.tar.gz";
    hash = "sha256-GShLuQzcv/jHXw8VgjAj2s8ux1T1tSwAZyvHq6Af47g=";
  };

  fontsReadme = fetchurl {
    name = "libtcod-fonts-README.txt";
    url = "https://raw.githubusercontent.com/libtcod/libtcod/468fcaa412843d79ac02ec035cd756cb5412367f/data/fonts/README.txt";
    hash = "sha256-Z2qcS7gdA8/RPVqj1chap1+VSoApJowInyLclSFDW/A=";
  };
in
stdenv.mkDerivation {
  pname = "god-of-change";
  # The official release is unversioned and dated 2011-03-12.
  version = "2011.03.12";

  src = fetchurl {
    name = "god-of-change-2011.03.12-source.zip";
    url = "${archive}/God%20of%20Change%20-%20Source.zip";
    hash = "sha256-b+yXS5qxPQRMQwKInUo1+KhaKHlmFMODc+QVWOdCRA4=";
  };

  nativeBuildInputs = [ unzip ];
  buildInputs = [ libtcod ];

  # The ZIP is flat.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    cd source
    unzip -q $src
    mkdir assets
    tar -xzf ${assets} -C assets terminal.png \
      LIBTCOD-LICENSE.txt LIBTCOD-CREDITS.txt README-SDL.txt
    runHook postUnpack
  '';

  postPatch = ''
    sed -i 's/\r$//' GodOfChange.cpp

    # The original 2011 libtcod waited for key presses only; 1.5.1's
    # waitForKeypress also returns releases, so one tap would act twice.
    # Wait for presses at all four original waits.
    substituteInPlace GodOfChange.cpp \
      --replace-fail 'TCOD_key_t key=TCODConsole::waitForKeypress(true);' \
        'TCOD_key_t key={TCODK_NONE,0}; TCODSystem::waitForEvent(TCOD_EVENT_KEY_PRESS,&key,NULL,true);'
    substituteInPlace GodOfChange.cpp \
      --replace-fail 'key=TCODConsole::waitForKeypress(true);' \
        'key=TCOD_key_t(); TCODSystem::waitForEvent(TCOD_EVENT_KEY_PRESS,&key,NULL,true);'
    test "$(grep -c 'waitForEvent(TCOD_EVENT_KEY_PRESS' GodOfChange.cpp)" = 4
    ! grep -q waitForKeypress GodOfChange.cpp

    # Load the installed original font instead of ./terminal.png.
    substituteInPlace GodOfChange.cpp \
      --replace-fail 'TCODConsole::initRoot(95,61,"God of Change",false);' \
        'TCODConsole::setCustomFont(GOD_OF_CHANGE_FONT,TCOD_FONT_LAYOUT_ASCII_INCOL,16,16); TCODConsole::initRoot(95,61,"God of Change",false);'
  '';

  dontConfigure = true;

  # Upstream has no Makefile; the whole game is one translation unit.
  buildPhase = ''
    runHook preBuild
    $CXX -std=gnu++98 -O2 \
      -I${libtcod}/include \
      -DGOD_OF_CHANGE_FONT=\"$out/share/god-of-change/terminal.png\" \
      GodOfChange.cpp -o god-of-change \
      -L${libtcod}/lib -Wl,-rpath,${libtcod}/lib -ltcodxx -ltcod -lm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin god-of-change
    install -Dm644 -t $out/share/god-of-change assets/terminal.png

    doc=$out/share/doc/god-of-change
    install -Dm644 -t $doc "God of Change license.txt" "God of Change readme.txt"
    for f in LIBTCOD-LICENSE.txt LIBTCOD-CREDITS.txt README-SDL.txt; do
      install -Dm644 assets/$f $doc/bundled-$f
    done
    install -Dm644 -t $doc ${libtcod}/share/doc/dwarftown-libtcod/*
    install -Dm644 ${fontsReadme} $doc/libtcod-fonts-README.txt
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    grep -qF "$out/share/god-of-change/terminal.png" $out/bin/god-of-change
    $READELF -d $out/bin/god-of-change | grep -qF "${libtcod}/lib"
    test "$(stat -c %s $out/share/god-of-change/terminal.png)" = 5011
    ! find $out \( -name 'GodOfChange' -o -name '*.so' \) | grep -q .
    runHook postInstallCheck
  '';

  meta = {
    description = "Roguelike with evolving monsters and an antagonistic deity";
    longDescription = ''
      God of Change is Adam Gatt's 2011 roguelike in which monster species
      acquire new abilities and behaviours as time passes.  Explore four
      randomly generated dungeons and confront the God of Change in the
      fifth.  The original C++ game is built with the historical libtcod
      1.5.1 renderer, keeping its font, controls and 95 by 61 cell display.
      The game has no save system.
    '';
    homepage = "https://code.google.com/archive/p/godofchange/";
    license = [ lib.licenses.bsd3 lib.licenses.zlib ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "god-of-change";
  };
}
