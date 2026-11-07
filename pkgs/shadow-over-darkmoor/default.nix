{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  writeText,
  jdk_headless,
  runtimeShell,
  stripJavaArchivesHook,
}:

let
  # Clojure 1.10.0, the version project.clj pins, and the two spec libraries
  # its POM requires.  These jars are referenced from the store, not bundled.
  clojureJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/clojure/1.10.0/clojure-1.10.0.jar";
    hash = "sha256-UBQJSljAV27fgsvWTeJTZRGy9w6cF6x4wRIVJOq7rjg=";
  };
  specAlphaJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/spec.alpha/0.2.176/spec.alpha-0.2.176.jar";
    hash = "sha256-/E6W7P803dKrf9BQ50rhN5NC7gnapgKNpSAkxd6DbMQ=";
  };
  coreSpecsAlphaJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/core.specs.alpha/0.2.44/core.specs.alpha-0.2.44.jar";
    hash = "sha256-Ox7E1vDo5Bv3aEJwkIO+s7Vq3zyC+aTxdMPadHdLOBw=";
  };
  runtimeClasspath = lib.concatStringsSep ":" [
    clojureJar
    specAlphaJar
    coreSpecsAlphaJar
  ];

  # Run the upstream test namespace and exit nonzero on any failure or error.
  runTests = writeText "shadow-over-darkmoor-run-tests.clj" ''
    (require 'clojure.test 'darkmoor.core-test)
    (let [{:keys [test fail error]} (clojure.test/run-tests 'darkmoor.core-test)]
      (shutdown-agents)
      (System/exit (if (and (pos? test) (zero? fail) (zero? error)) 0 1)))
  '';
in
stdenvNoCC.mkDerivation {
  pname = "shadow-over-darkmoor";
  version = "0.2.0-unstable-2023-11-29";

  src = fetchFromGitHub {
    owner = "catspook";
    repo = "Shadow_Over_Darkmoor";
    rev = "fe7d29690ecbefa01bd641d2179d27c6d16a105e";
    hash = "sha256-JCToBkrs5DoWa8ca0kDXrhK/Mi0oNGaR/pPN0Qsnntk=";
  };

  nativeBuildInputs = [
    jdk_headless
    stripJavaArchivesHook
  ];

  dontConfigure = true;

  # darkmoor.core loads the other source files as in-ns scripts, so compiling
  # it ahead of time also compiles them.  Only the game's classes go into the
  # jar: Clojure would prefer equally dated sources over classes, and the
  # compiler also emits core.specs.alpha classes already in the runtime jar.
  buildPhase = ''
    runHook preBuild
    mkdir classes
    java -Dfile.encoding=UTF-8 -Duser.home="$TMPDIR" \
      -Dclojure.compile.path=classes \
      -cp "src:classes:${runtimeClasspath}" \
      clojure.main -e "(compile 'darkmoor.core)" </dev/null
    test -f classes/darkmoor/core.class
    (cd classes && jar --create --file ../shadow-over-darkmoor.jar \
      --date=1980-01-01T00:00:02Z --main-class darkmoor.core \
      $(find darkmoor -type f -name '*.class' | LC_ALL=C sort))
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    # Fail if upstream adds a test file the runner does not list.
    test "$(find test -name '*_test.clj' | wc -l)" -eq 1
    java -Dfile.encoding=UTF-8 -Duser.home="$TMPDIR" \
      -cp "shadow-over-darkmoor.jar:test:${runtimeClasspath}" \
      clojure.main ${runTests} </dev/null
    runHook postCheck
  '';

  # The game reads resources/*.txt relative to its working directory and
  # never writes files, so the launcher runs it from the packaged data
  # directory.  -main takes no arguments.
  installPhase = ''
    runHook preInstall
    install -Dm444 shadow-over-darkmoor.jar "$out/share/java/shadow-over-darkmoor.jar"
    mkdir -p "$out/share/shadow-over-darkmoor" "$out/bin"
    cp -r resources "$out/share/shadow-over-darkmoor/resources"
    install -Dm444 LICENSE README.md CHANGELOG.md -t "$out/share/doc/shadow-over-darkmoor"
    cat > "$out/bin/shadow-over-darkmoor" <<'EOF'
    #!${runtimeShell}
    cd '${placeholder "out"}/share/shadow-over-darkmoor' || exit 1
    exec ${jdk_headless}/bin/java -Dfile.encoding=UTF-8 \
      -cp '${placeholder "out"}/share/java/shadow-over-darkmoor.jar:${runtimeClasspath}' \
      darkmoor.core
    EOF
    chmod 555 "$out/bin/shadow-over-darkmoor"
    runHook postInstall
  '';

  # Play to the first menu and quit.  Pauses accept any line and every menu
  # exits on "q"; end of input would make the main menu recurse until the
  # stack overflows, so supply plenty of lines.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    grep -qF '${jdk_headless}/bin/java' "$out/bin/shadow-over-darkmoor"
    for i in $(seq 40); do echo q; done > quit-input
    if ! timeout 120 "$out/bin/shadow-over-darkmoor" < quit-input > game-output 2>&1; then
      cat game-output
      exit 1
    fi
    grep -qF -- '-____-' game-output
    grep -qF 'Hit ENTER to continue.' game-output
    if grep -q Exception game-output; then
      cat game-output
      exit 1
    fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Text-based roguelike adventure game";
    longDescription = ''
      The Shadow Over Darkmoor is a text-based roguelike adventure game
      written in Clojure.  The player explores the town of Darkmoor and its
      surroundings, loots locations and fights enemies from a terminal menu.
    '';
    homepage = "https://github.com/catspook/Shadow_Over_Darkmoor";
    # project.clj: EPL-2.0 OR GPL-2.0-or-later WITH Classpath-exception-2.0.
    # The Clojure runtime jars (EPL-1.0) are referenced on the launcher class
    # path, not redistributed in this output.
    license = with lib.licenses; [
      epl20
      gpl2Plus
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "shadow-over-darkmoor";
  };
}
