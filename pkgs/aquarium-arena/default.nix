{ lib, stdenvNoCC, fetchFromGitHub, python3, makeWrapper, freefont_ttf, liberation_ttf_v1 }:

let
  python = python3.withPackages (ps: [ ps.pygame-ce ]);
  inData = path: "os.path.join(DATA_ROOT, \"${path}\")";
  inGameData = path: "os.path.join(gameEngine.DATA_ROOT, \"${path}\")";
in
stdenvNoCC.mkDerivation {
  pname = "aquarium-arena";
  version = "0.4";

  # The 0.4 release commit; upstream master points at the same revision.
  src = fetchFromGitHub {
    owner = "valrak";
    repo = "AquariumRL";
    rev = "6d494cee8d45f734eaecd56237f33aaec37a0ed8";
    hash = "sha256-0JLP5/Q7l/0xM+X61lP5T/yQ1l1MC/wkXMRYfVInOrk=";
  };

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ python ];

  postPatch = ''
    # Port the Python 2 snapshot to Python 3. The remaining divisions
    # deliberately keep floating point scale factors.
    substituteInPlace mapField.py \
      --replace-fail 'except IndexError, e:' 'except IndexError as e:' \
      --replace-fail 'print "index error at coordinates:", coord, "Exception: ", e' \
                     'print("index error at coordinates:", coord, "Exception: ", e)' \
      --replace-fail 'maxx * maxy / rockamountr' 'maxx * maxy // rockamountr' \
      --replace-fail 'maxx*maxy/95' 'maxx*maxy//95' \
      --replace-fail 'maxx*maxy/60' 'maxx*maxy//60' \
      --replace-fail 'maxx*maxy/70' 'maxx*maxy//70' \
      --replace-fail 'item.has_key("rarity")' '"rarity" in item' \
      --replace-fail 'monster.getparam("hp") <= 0' 'int(monster.getparam("hp")) <= 0'
    substituteInPlace pathfinder.py \
      --replace-fail 'deltax / 2' 'deltax // 2' \
      --replace-fail 'is not 0' '!= 0'
    substituteInPlace monster.py \
      --replace-fail 'int(weapon.getparam("damage") > 0)' 'int(weapon.getparam("damage")) > 0' \
      --replace-fail 'self.getparam("hp") <= 0' 'int(self.getparam("hp")) <= 0'

    # Read data from the package instead of the working directory.
    substituteInPlace gameEngine.py \
      --replace-fail 'params.has_key("flags")' '"flags" in params' \
      --replace-fail 'params.has_key("upgradelevel")' '"upgradelevel" in params' \
      --replace-fail 'import sys' ${lib.escapeShellArg "import sys\nimport os"} \
      --replace-fail 'mapmaxx = 0' ${lib.escapeShellArg "DATA_ROOT = \"${placeholder "out"}/share/aquarium-arena\"\n\nmapmaxx = 0"} \
      --replace-fail '"resources/data/creatures.jsn"' ${lib.escapeShellArg (inData "resources/data/creatures.jsn")} \
      --replace-fail '"resources/data/map.jsn"' ${lib.escapeShellArg (inData "resources/data/map.jsn")} \
      --replace-fail '"resources/data/effects.jsn"' ${lib.escapeShellArg (inData "resources/data/effects.jsn")} \
      --replace-fail '"resources/data/items.jsn"' ${lib.escapeShellArg (inData "resources/data/items.jsn")} \
      --replace-fail '"config/keystrokes.jsn"' ${lib.escapeShellArg (inData "config/keystrokes.jsn")} \
      --replace-fail '"config/settings.jsn"' ${lib.escapeShellArg (inData "config/settings.jsn")} \
      --replace-fail '"resources/texts/helpScreen.txt"' ${lib.escapeShellArg (inData "resources/texts/helpScreen.txt")} \
      --replace-fail '"resources/texts/helpBox.txt"' ${lib.escapeShellArg (inData "resources/texts/helpBox.txt")} \
      --replace-fail '"resources/maps/arena1.csv"' ${lib.escapeShellArg (inData "resources/maps/arena1.csv")}
    substituteInPlace graphicsHandler.py \
      --replace-fail 'bigtilestep / 2' 'bigtilestep // 2' \
      --replace-fail 'int(maxhp) / 5' 'int(maxhp) // 5' \
      --replace-fail 'RESOLUTIONX / 2' 'RESOLUTIONX // 2' \
      --replace-fail 'import pathfinder' ${lib.escapeShellArg "import pathfinder\nimport os"} \
      --replace-fail '"resources/img/MapTiles.png"' ${lib.escapeShellArg (inGameData "resources/img/MapTiles.png")} \
      --replace-fail '"resources/img/CreatureTiles.png"' ${lib.escapeShellArg (inGameData "resources/img/CreatureTiles.png")} \
      --replace-fail '"resources/img/BigCreatureTiles.png"' ${lib.escapeShellArg (inGameData "resources/img/BigCreatureTiles.png")} \
      --replace-fail '"resources/img/EffectTiles.png"' ${lib.escapeShellArg (inGameData "resources/img/EffectTiles.png")} \
      --replace-fail '"resources/img/ItemTiles.png"' ${lib.escapeShellArg (inGameData "resources/img/ItemTiles.png")} \
      --replace-fail '"resources/img/UI.png"' ${lib.escapeShellArg (inGameData "resources/img/UI.png")} \
      --replace-fail '"resources/img/watch.png"' ${lib.escapeShellArg (inGameData "resources/img/watch.png")} \
      --replace-fail '"./resources/fonts/FreeMonoBold.ttf"' ${lib.escapeShellArg (inGameData "resources/fonts/FreeMonoBold.ttf")} \
      --replace-fail "'resources/img/helpscreen.png'" ${lib.escapeShellArg (inGameData "resources/img/helpscreen.png")}

    # The high score is the only mutable file; keep it in the user's XDG
    # data directory.
    cat > hiscore.py <<'EOF'
    import os

    def hiscore_path():
        root = os.environ.get("XDG_DATA_HOME")
        if not root:
            root = os.path.join(os.path.expanduser("~"), ".local", "share")
        directory = os.path.join(root, "aquarium-arena")
        os.makedirs(directory, exist_ok=True)
        return os.path.join(directory, "hiscore")

    def loadhiscore():
        try:
            with open(hiscore_path(), "r") as score_file:
                return score_file.readline()
        except IOError:
            return 0

    def savehiscore(score, hiscore):
        if score == "":
            score = 0
        if hiscore == "":
            hiscore = 0
        if int(hiscore) < int(score):
            with open(hiscore_path(), "w") as score_file:
                score_file.write(str(score))
            return True
        return False
    EOF

    if grep -nE "has_key|is not 0|except [A-Za-z]+, |[(=] *[\"'](\./)?(resources|config)/" *.py; then
      echo "unpatched references remain" >&2
      exit 1
    fi
  '';

  dontConfigure = true;
  dontBuild = true;

  # Upstream has no tests: compile every module and check the runtime assets.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python.interpreter} -m py_compile *.py
    for file in resources/img/{BigCreatureTiles,CreatureTiles,EffectTiles,ItemTiles,MapTiles,UI,helpscreen,watch}.png \
                resources/fonts/{FreeMonoBold,LiberationMono-Bold}.ttf \
                resources/data/{creatures,effects,items,map}.jsn \
                resources/maps/arena1.csv resources/texts/{helpScreen,helpBox}.txt \
                config/{keystrokes,settings}.jsn; do
      test -e "$file" || { echo "missing runtime asset: $file" >&2; exit 1; }
    done
    rm -rf __pycache__
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/aquarium-arena
    doc=$out/share/doc/aquarium-arena
    mkdir -p $data
    cp -r *.py config resources $data/
    install -Dm644 -t $doc LICENSE.md README.md changelog.txt
    # FreeMonoBold.ttf is GNU FreeFont (GPL-3.0-or-later with font exception).
    install -Dm644 ${freefont_ttf.src}/COPYING $doc/FreeMono-COPYING
    # LiberationMono-Bold.ttf is Liberation 1.07.4; this is the identical
    # Liberation 1.7 license text from the 1.07.5 source.
    install -Dm644 ${liberation_ttf_v1.src}/License.txt $doc/LiberationMono-LICENSE
    makeWrapper ${python.interpreter} $out/bin/aquarium-arena \
      --run 'test $# -eq 0 || { echo "usage: aquarium-arena" >&2; exit 64; }' \
      --add-flags $data/AquariumArena.py \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --set PYTHONNOUSERSITE 1 \
      --set PYGAME_HIDE_SUPPORT_PROMPT 1
    runHook postInstall
  '';

  # The game opens straight into play and loops until killed, so a headless
  # run should still be alive when the timeout stops it.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home XDG_DATA_HOME=$TMPDIR/data
    export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
    mkdir -p "$HOME"
    status=0
    $out/bin/aquarium-arena extra 2>/dev/null || status=$?
    [ "$status" -eq 64 ] || { echo "arguments were not rejected ($status)" >&2; exit 1; }
    status=0
    timeout 10 $out/bin/aquarium-arena || status=$?
    [ "$status" -eq 124 ] || { echo "aquarium-arena exited with status $status" >&2; exit 1; }
    test -d "$XDG_DATA_HOME/aquarium-arena"
    test ! -e $out/share/aquarium-arena/__pycache__
    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical turn-based roguelike set in an underwater arena";
    homepage = "https://github.com/valrak/AquariumRL";
    # Game code, art and data are GPL-2.0; FreeMono is GPL-3.0-or-later with
    # the font exception; Liberation Mono 1.07 is GPL-2.0 with the embedding
    # and physical-product exceptions. Notices are in share/doc.
    license = with lib.licenses; [ gpl2Only gpl3Plus ];
    mainProgram = "aquarium-arena";
    platforms = [ "x86_64-linux" ];
  };
}
