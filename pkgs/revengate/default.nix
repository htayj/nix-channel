# Revengate, the original Godot project with its assets imported at build time.
{
  lib,
  stdenvNoCC,
  fetchFromGitLab,
  godot_4_6,
  python3,
  runtimeShell,
}:

let
  engine = lib.getExe godot_4_6;
in
stdenvNoCC.mkDerivation {
  pname = "revengate";
  version = "0.13.0";

  src = fetchFromGitLab {
    owner = "ygingras";
    repo = "revengate";
    rev = "21b0cb49a84a1fada7e171064b68f1183818c32c";
    hash = "sha256-R7Jjp8YfVe3XAvuItJD2EM5zigkcF/eD2hAvGMdWEns=";
  };

  # Nodes the game creates without a parent are never freed, and Godot reports
  # them as errors at exit.
  patches = [ ./node-ownership.patch ];

  # The bundled dialogue editor plugin compiles the .dialogue files during the
  # import.  Its update check goes, and its translation parser, written for
  # Godot 4.3, takes the signature Godot 4.6 calls.
  postPatch = ''
    substituteInPlace addons/dialogue_manager/components/update_button.gd \
      --replace-fail 'if DialogueSettings.get_user_value("check_for_updates", true):' \
                     'if false:'

    parser=addons/dialogue_manager/editor_translation_parser_plugin.gd
    substituteInPlace $parser \
      --replace-fail 'func _parse_file(path: String, msgids: Array, msgids_context_plural: Array) -> void:' \
                     $'func _parse_file(path: String) -> Array[PackedStringArray]:\n\tvar msgids_context_plural: Array[PackedStringArray] = []' \
      --replace-fail 'func _get_recognized_extensions' \
                     $'\treturn msgids_context_plural\n\nfunc _get_recognized_extensions'
    sed -E -i 's/msgids_context_plural\.append\(\[(.*)\]\)/msgids_context_plural.append(PackedStringArray([\1]))/' $parser
    grep -q 'msgids_context_plural.append(PackedStringArray(' $parser
  '';

  nativeBuildInputs = [ python3 ];

  dontConfigure = true;
  # The project tree is installed as imported, upstream's tools included.
  dontPatchShebangs = true;

  # Godot can exit 0 after a failed script or import, so every run is judged
  # by its log as well.
  preBuild = ''
    export HOME=$TMPDIR/home
    export XDG_CONFIG_HOME=$HOME/config XDG_CACHE_HOME=$HOME/cache XDG_DATA_HOME=$HOME/data
    mkdir -p $HOME

    runChecked() {
      local log=$TMPDIR/$1.log status=0
      shift
      timeout --kill-after=10 600 "$@" --headless --audio-driver Dummy >"$log" 2>&1 || status=$?
      cat "$log"
      if [ "$status" -ne 0 ] || grep -qE '^(USER )?(SCRIPT )?ERROR:' "$log"; then
        echo "Godot failed (exit $status) or reported an error" >&2
        return 1
      fi
    }
  '';

  buildPhase = ''
    runHook preBuild

    # The theme uses fonts that exist only after a first import, so that
    # import runs without the theme and a second one with it.
    cp project.godot $TMPDIR/project.godot
    sed -i '/^theme\/custom=/d' project.godot
    runChecked initial-import ${engine} --path . --editor --import
    cp $TMPDIR/project.godot project.godot
    runChecked import ${engine} --path . --editor --import
    grep -q '^theme/custom=' project.godot

    # Godot appends to the UID cache in import order: u32 count, then records
    # of u64 id, u32 length and path.  Sort the records by id.
    python3 - <<'EOF'
    import struct

    path = ".godot/uid_cache.bin"
    data = open(path, "rb").read()
    (count,) = struct.unpack_from("<I", data, 0)
    offset, records = 4, []
    for _ in range(count):
        uid, size = struct.unpack_from("<QI", data, offset)
        records.append((uid, data[offset:offset + 12 + size]))
        offset += 12 + size
    assert offset == len(data), "unexpected Godot UID cache format"
    with open(path, "wb") as out:
        out.write(struct.pack("<I", count))
        out.write(b"".join(record for _, record in sorted(records)))
    EOF

    # The editor caches record build paths and modification times, and the
    # imported project no longer needs the editor plugin.
    rm -rf .godot/editor .godot/shader_cache
    substituteInPlace project.godot --replace-fail \
      'enabled=PackedStringArray("res://addons/dialogue_manager/plugin.cfg")' \
      'enabled=PackedStringArray()'

    runHook postBuild
  '';

  # Upstream's combat simulator, autoloads included, on a copy that runs 50
  # fights for each of its three stages instead of 1000 (a quarter of an hour).
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cp -R . $TMPDIR/combat
    substituteInPlace $TMPDIR/combat/src/combat/combat_sim.gd \
      --replace-fail 'const NB_SIMS_PER_RUN = 1000' 'const NB_SIMS_PER_RUN = 50'
    runChecked combat ${engine} --path $TMPDIR/combat --scene src/combat/combat_sim.tscn
    grep -qx 'Done!' $TMPDIR/combat.log
    rm -r $TMPDIR/combat
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    data=$out/share/revengate
    doc=$out/share/doc/revengate
    mkdir -p $data $out/bin
    cp -R . $data/

    install -Dm444 -t $doc COPYING.txt CREDITS.md README.md
    cp -R docs/legal $doc/legal
    for notice in \
      addons/dialogue_manager/LICENSE \
      addons/kenney_particle_pack/LICENSE.txt \
      assets/dcss/LICENSE.txt \
      assets/dcss/README.txt
    do
      install -Dm444 $notice $doc/third-party/$notice
    done
    cat > $doc/NIX-CHANGES <<'EOF'
    Changes made to Revengate 0.13.0 by this package (2026-11-19):
    The project is imported at build time with Godot 4.6.
    The dialogue plugin's translation parser is adapted to Godot 4.6.
    The dialogue plugin's update check and its activation in the editor are disabled.
    Default deck builders and the disposal limbo node belong to their scenes,
    removed HUD buttons are freed, and temporary highlight nodes are freed
    after their scenes are packed.
    EOF

    cat > $out/bin/revengate <<EOF
    #!${runtimeShell}
    exec ${engine} --path $data "\$@"
    EOF
    chmod 555 $out/bin/revengate

    runHook postInstall
  '';

  # The launcher on a read-only project, as in the store: the engine is the
  # one that imported it and the main scene starts.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    chmod -R a-w $out/share/revengate
    $out/bin/revengate --version | grep -F ${lib.versions.majorMinor godot_4_6.version}.
    runChecked launch $out/bin/revengate --quit-after 120
    chmod -R u+w $out/share/revengate
    runHook postInstallCheck
  '';

  meta = {
    description = "Steampunk roguelike set in nineteenth-century Lyon";
    longDescription = ''
      Revengate is a graphical, turn-based roguelike set in steampunk Lyon.
      Explore its streets and dungeons, talk to its characters and pursue
      quests.  This package runs the original Godot project with assets
      imported at build time; saved games are kept in the user's data
      directory.
    '';
    homepage = "https://revengate.org/";
    # The game is GPL-3.0-or-later.  CREDITS.md and docs/legal carry the grants
    # for the bundled plugin, artwork, sounds and fonts; several artists grant
    # CC-BY or CC-BY-SA without naming a version.
    license = with lib.licenses; [
      gpl3Plus
      mit
      cc0
      publicDomain
      cc-by-30
      cc-by-40
      {
        fullName = "Creative Commons Attribution (version unspecified)";
        url = "https://gitlab.com/ygingras/revengate/-/blob/v0.13.0/CREDITS.md";
        free = true;
        redistributable = true;
      }
      {
        fullName = "Creative Commons Attribution-ShareAlike (version unspecified)";
        url = "https://gitlab.com/ygingras/revengate/-/blob/v0.13.0/CREDITS.md";
        free = true;
        redistributable = true;
      }
      {
        fullName = "Symbola font grant: free for any use, modification, packaging and redistribution";
        url = "https://gitlab.com/ygingras/revengate/-/blob/v0.13.0/CREDITS.md";
        free = true;
        redistributable = true;
      }
    ];
    mainProgram = "revengate";
    platforms = [ "x86_64-linux" ];
  };
}
