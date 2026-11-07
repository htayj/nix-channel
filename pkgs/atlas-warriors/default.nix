{ lib, stdenvNoCC, fetchFromGitHub, python3, makeWrapper, dejavu_fonts }:

let
  python = python3.withPackages (ps: [ ps.pygame-ce ]);

  # Python expression for the per-user directory holding error.log and
  # tutorial.json.
  stateDirectory = "os.path.join(os.environ.get('XDG_STATE_HOME', os.path.join(os.path.expanduser('~'), '.local', 'state')), 'atlas-warriors')";
  fontPath = name: "os.path.join(os.path.dirname(__file__), \"${name}\")";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "atlas-warriors";
  version = "0.0.9";

  # alpha-009, the final playable snapshot, is a lightweight tag; pin its commit.
  src = fetchFromGitHub {
    owner = "lkingsford";
    repo = "AtlasWarriors";
    rev = "d5354adbe29884016aec2867c9ded52d15f9fcd1";
    hash = "sha256-eNVy7fMbtO91BjX5APuyHGgLKpjomN6TOz+CRk4kVbA=";
  };

  sourceRoot = "${finalAttrs.src.name}/src";

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ python ];

  postPatch = ''
    # Windows packaging helpers and a thumbnail cache, not runtime files.
    rm pygame2exe.py setup.py Assets/Thumbs.db

    # Read resources from the package data directory, write the error log
    # to the user's XDG state directory, and initialize pygame before
    # opening the window.
    substituteInPlace rl.py \
      --replace-fail "import traceback" ${lib.escapeShellArg "import traceback\n\nDATA_ROOT = \"${placeholder "out"}/share/atlas-warriors\"\n"} \
      --replace-fail "filename='error.log'," "filename=os.path.join(state_directory, 'error.log')," \
      --replace-fail "logging.basicConfig(" ${lib.escapeShellArg "state_directory = ${stateDirectory}\nos.makedirs(state_directory, exist_ok=True)\nlogging.basicConfig("} \
      --replace-fail "screen = pygame.display.set_mode" ${lib.escapeShellArg "pygame.init()\nscreen = pygame.display.set_mode"} \
      --replace-fail "xml2object.parse('items.xml', item.Item)" "xml2object.parse(os.path.join(DATA_ROOT, 'items.xml'), item.Item)" \
      --replace-fail "os.path.join('assets','back_level_" "os.path.join(DATA_ROOT, 'assets', 'back_level_"

    # Load fonts from the installed data directory regardless of the
    # working directory.
    for file in context.py inventoryDialog.py messageBox.py messagesDialog.py pygcurse.py rl.py skillsDialog.py; do
      substituteInPlace "$file" --replace-fail "import pygame" ${lib.escapeShellArg "import pygame\nimport os"}
    done
    substituteInPlace context.py pygcurse.py rl.py \
      --replace-fail '"DejaVuSansMono.ttf"' ${lib.escapeShellArg (fontPath "DejaVuSansMono.ttf")}
    substituteInPlace inventoryDialog.py messageBox.py messagesDialog.py rl.py skillsDialog.py \
      --replace-fail '"DejaVuSerif.ttf"' ${lib.escapeShellArg (fontPath "DejaVuSerif.ttf")}

    # pygame-ce reports colors as pygame.color.Color, which the old type
    # string test misses.
    substituteInPlace pygcurse.py \
      --replace-fail "    elif value in colornames:" ${lib.escapeShellArg "    elif isinstance(value, pygame.Color):\n        return value\n    elif value in colornames:"}

    # Tutorial progress is user state.
    substituteInPlace tutorial.py \
      --replace-fail "import json" ${lib.escapeShellArg "import json\nimport os\n\nTUTORIAL_PATH = os.path.join(${stateDirectory}, 'tutorial.json')"} \
      --replace-fail 'open("tutorial.json"' "open(TUTORIAL_PATH" \
      --replace-fail "        # Saves settings to tutorial.json " ${lib.escapeShellArg "        # Saves settings to the user's XDG state directory\n        os.makedirs(os.path.dirname(TUTORIAL_PATH), exist_ok=True)"}

    # The menu entries that opened a browser do nothing instead.
    substituteInPlace mainmenu.py \
      --replace-fail "import webbrowser" "" \
      --replace-fail 'webbrowser.open_new_tab("http://www.nerdygentleman.com")' "pass" \
      --replace-fail 'webbrowser.open_new_tab("https://pledgie.com/campaigns/27179")' "pass"

    if grep -n 'webbrowser\|Font("DejaVu' *.py; then
      echo "unpatched references remain" >&2
      exit 1
    fi
  '';

  dontConfigure = true;
  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python.interpreter} -m py_compile *.py
    for file in items.xml Assets/back_level_{0,1,2,3}.png; do
      test -e "$file" || { echo "missing runtime asset: $file" >&2; exit 1; }
    done
    rm -rf __pycache__
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/atlas-warriors
    doc=$out/share/doc/atlas-warriors
    install -Dm644 -t $data *.py items.xml
    install -Dm644 -t $data/assets Assets/back_level_{0,1,2,3}.png
    # The bundled fonts ship without their notice; use the same DejaVu 2.37
    # files from nixpkgs and install the DejaVu license.
    for font in DejaVuSans.ttf DejaVuSansMono.ttf DejaVuSerif.ttf; do
      install -Dm444 ${dejavu_fonts}/share/fonts/truetype/$font $data/$font
    done
    install -Dm644 -t $doc ../LICENSE ../README.md ../CHANGELOG.md
    install -Dm644 ${dejavu_fonts.full-ttf.src}/LICENSE $doc/DejaVu-LICENSE
    makeWrapper ${python.interpreter} $out/bin/atlas-warriors \
      --add-flags $data/rl.py \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --set PYTHONNOUSERSITE 1 \
      --set PYGAME_HIDE_SUPPORT_PROMPT 1
    runHook postInstall
  '';

  # Start headless at the main menu and directly in an easiest game
  # (argument 0 skips the menu). Both should still be running when the
  # timeout stops them.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR XDG_STATE_HOME=$TMPDIR/state
    export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
    for args in "" 0; do
      rm -rf "$XDG_STATE_HOME"
      status=0
      timeout 10 $out/bin/atlas-warriors $args || status=$?
      if [ "$status" -ne 124 ]; then
        echo "atlas-warriors $args exited with status $status" >&2
        cat "$XDG_STATE_HOME/atlas-warriors/error.log" >&2 || true
        exit 1
      fi
      test -f "$XDG_STATE_HOME/atlas-warriors/error.log"
      if grep -n CRITICAL "$XDG_STATE_HOME/atlas-warriors/error.log"; then
        echo "atlas-warriors $args logged a critical error" >&2
        exit 1
      fi
    done
    test ! -e $out/share/atlas-warriors/__pycache__
    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical turn-based fantasy roguelike";
    homepage = "https://nerdygentleman.itch.io/atlas-warriors";
    # Game code is MIT; pygcurse.py is BSD-2; the four level backgrounds are
    # modified Dark Paper Pack art (CC-BY-3.0); the fonts are DejaVu.
    license = with lib.licenses; [ mit bsd2 cc-by-30 bitstreamVera ];
    mainProgram = "atlas-warriors";
    platforms = [ "x86_64-linux" ];
  };
})
