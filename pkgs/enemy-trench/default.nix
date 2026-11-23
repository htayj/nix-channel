{ lib, stdenvNoCC, fetchurl, python3, python-tcod }:

let
  # The game's code uses no API removed in NumPy 2, so it runs on the
  # current NumPy and SoundFile with the channel's SDL2 python-tcod.
  python = python3.withPackages (ps: [ python-tcod ps.numpy ps.soundfile ]);

  tutorialLicense = fetchurl {
    name = "enemy-trench-tutorial-CC0.txt";
    url = "https://raw.githubusercontent.com/TStand90/tcod_tutorial_v2/6df33407c2146f45b424b7ffed15d67a18891b9f/LICENSE.txt";
    hash = "sha256-ogEPNDSH0/dhiv/lT3ifVIdgIzHAqNA/SemnxUfPBJk=";
  };
in
stdenvNoCC.mkDerivation rec {
  pname = "enemy-trench";
  # Untagged final update after the 1.0.5 release.
  version = "1.0.5-unstable-2023-01-29";
  rev = "698bee218f76d16b98abc7eb2991a7690fffd9b4";

  src = fetchurl {
    name = "enemy-trench-${rev}.tar.gz";
    url = "https://gitlab.com/api/v4/projects/30983243/repository/archive.tar.gz?sha=${rev}";
    hash = "sha256-IzRcRT9azRWdCV9kBDXPZq74udDZ+63RSRq4nyc6+x4=";
  };

  # Keep mutable settings and saves in one XDG data directory, and repair
  # the gas handler's missing SoundFile import and audio filename.
  patches = [ ./enemy-trench-paths-and-gas-audio.patch ];

  postPatch = ''
    # All shipped bytecode is stale.
    find . -name '*.pyc' -delete
    find . -name __pycache__ -type d -prune -exec rm -r {} +

    data=$out/share/enemy-trench
    # Load audio by absolute immutable path, decoded as SDL's native float32
    # (SoundFile's float64 default cannot be converted by SDL2).
    sed -i -E \
      -e 's/soundfile\.read\(([^,]*)\)/soundfile.read(\1, dtype="float32")/g' \
      -e "s|soundfile\.read\(\"media/|soundfile.read(\"$data/media/|g" \
      *.py components/*.py
    sed -i -E \
      -e 's/path\.join\(game_dir, "(settings\.ini|saves[^"]*)"/path.join(state_dir, "\1"/g' \
      -e 's|game_dir\+"/saves"|path.join(state_dir, "saves")|g' \
      -e 's/open\("settings\.ini"/open(path.join(state_dir, "settings.ini")/g' \
      -e 's/makedirs\("saves"\)/makedirs(path.join(state_dir, "saves"))/g' \
      main.py setup_game.py input_handlers.py engine.py
    cp ${./enemy_trench_paths.py} enemy_trench_paths.py
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    data=$out/share/enemy-trench
    doc=$out/share/doc/enemy-trench
    mkdir -p $data/components $doc $out/bin
    cp *.py $data/
    cp components/*.py $data/components/
    cp -r media $data/media
    install -Dm644 -t $doc LICENSE.EnemyTrench.txt README.txt requirements.txt
    install -Dm644 ${tutorialLicense} $doc/tutorial-CC0.txt

    cat > $data/launch.py <<EOF
    import sys
    sys.path.insert(0, "$data")
    import main
    main.main()
    EOF
    cat > $out/bin/enemy-trench <<EOF
    #!${stdenvNoCC.shell}
    set -eu
    test \$# -eq 0 || { echo 'usage: enemy-trench' >&2; exit 64; }
    exec ${python}/bin/python3 -I -B $data/launch.py
    EOF
    chmod 555 $out/bin/enemy-trench
    runHook postInstall
  '';

  passthru = { inherit python; };

  meta = {
    description = "World War I graphical turn-based roguelike";
    longDescription = ''
      Enemy Trench is a graphical turn-based roguelike set during the Battle
      of the Somme.  Choose an infantryman, medic or sergeant and advance
      through trenches and other battlefields.  Settings and saves live in
      the user's XDG data directory.
    '';
    homepage = "https://gitlab.com/vulkanoid/enemy-trench";
    license = with lib.licenses; [ gpl3Plus cc0 ];
    mainProgram = "enemy-trench";
    platforms = lib.platforms.linux;
  };
}
