{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  jdk_headless,
  runtimeShell,
  stripJavaArchivesHook,
}:

let
  # Clojure 1.8.0, the exact version project.clj pins.  It has no further
  # dependencies, and the jar is referenced from the store, not bundled.
  clojureJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/clojure/1.8.0/clojure-1.8.0.jar";
    hash = "sha256-Bhp/H+TxpsaIUqHi9AeWbpBY/rDXfIcPByXnYG/TYKg=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "clojure-roguelike";
  version = "0.1.0-unstable-2018-09-21";

  src = fetchFromGitHub {
    owner = "charlesrosenbauer";
    repo = "Clojure-Roguelike";
    rev = "16102d6123a19dbac03f457a13e8b9f1e181f577";
    hash = "sha256-hj0Cm9QwLCV3s/LX2Jz9RNIgs+rxobJpuDikvTVdTQQ=";
  };

  nativeBuildInputs = [
    jdk_headless
    stripJavaArchivesHook
  ];

  dontConfigure = true;

  # Only the game's AOT classes go into the jar; Clojure itself stays on the
  # launcher class path.
  buildPhase = ''
    runHook preBuild
    mkdir classes
    java -Dfile.encoding=UTF-8 -Duser.home="$TMPDIR" \
      -Dclojure.compile.path=classes \
      -cp "src:classes:${clojureJar}" \
      clojure.main -e "(compile 'roguelike.core)" </dev/null
    test -f classes/roguelike/core.class
    (cd classes && jar --create --file ../clojure-roguelike.jar \
      --date=1980-01-01T00:00:02Z --main-class roguelike.core \
      $(find roguelike -type f -name '*.class' | LC_ALL=C sort))
    runHook postBuild
  '';

  # The only upstream test is the Leiningen template placeholder
  # "FIXME, I fail.", which asserts (= 0 1).
  doCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm444 clojure-roguelike.jar "$out/share/java/clojure-roguelike.jar"
    install -Dm444 LICENSE README.md CHANGELOG.md -t "$out/share/doc/clojure-roguelike"
    mkdir -p "$out/bin"
    cat > "$out/bin/clojure-roguelike" <<'EOF'
    #!${runtimeShell}
    exec ${jdk_headless}/bin/java -Dfile.encoding=UTF-8 \
      -cp '${placeholder "out"}/share/java/clojure-roguelike.jar:${clojureJar}' \
      roguelike.core "$@"
    EOF
    chmod 555 "$out/bin/clojure-roguelike"
    runHook postInstall
  '';

  # -main prints one 8x8 room and exits.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    grep -qF '${jdk_headless}/bin/java' "$out/bin/clojure-roguelike"
    timeout -k 5 120 "$out/bin/clojure-roguelike" </dev/null > room 2>&1 || { cat room; exit 1; }
    cat > expected-room <<'EOF'
    ########
    #......#
    #......#
    .......#
    #......#
    #......#
    #......#
    ########
    EOF
    diff -u expected-room room
    runHook postInstallCheck
  '';

  meta = {
    description = "Minimal terminal roguelike prototype written in Clojure";
    longDescription = ''
      Clojure-Roguelike is an early roguelike prototype written in Clojure.
      Its entry point renders a single 8x8 room to the terminal and exits.
    '';
    homepage = "https://github.com/charlesrosenbauer/Clojure-Roguelike";
    # LICENSE is EPL-1.0; the Clojure runtime jar (also EPL-1.0) is referenced
    # on the launcher class path, not redistributed in this output.
    license = lib.licenses.epl10;
    platforms = [ "x86_64-linux" ];
    mainProgram = "clojure-roguelike";
  };
}
