{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  writeText,
  jdk_headless,
  runtimeShell,
}:

let
  # Clojure 1.12.6 and the two spec libraries its POM requires.  Upstream tui
  # declares no other runtime dependencies.  These jars are referenced from
  # the store, not bundled into this package's jar.
  clojureJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/clojure/1.12.6/clojure-1.12.6.jar";
    hash = "sha256-IbV42ziajnSyhs55xKf4bsZB4m2IsS8Y1pAwkWsOGMo=";
  };
  specAlphaJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/spec.alpha/0.5.238/spec.alpha-0.5.238.jar";
    hash = "sha256-lM2ZtupjlkHzevSGCmQ7btOZ7lqL5dcXz/C2Y8jXUHc=";
  };
  coreSpecsAlphaJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/core.specs.alpha/0.4.74/core.specs.alpha-0.4.74.jar";
    hash = "sha256-63OsCM9JuoQMiLpnvu8RM2ylVDM9lAiAjXiUbg/rnds=";
  };
  runtimeClasspath = lib.concatStringsSep ":" [
    clojureJar
    specAlphaJar
    coreSpecsAlphaJar
  ];

  # Run every upstream test namespace and exit nonzero on any failure or error.
  # deps.edn's cognitect test-runner alias would need network access.
  runTests = writeText "tui-run-tests.clj" ''
    (require 'clojure.test)
    (def test-namespaces
      '[me.pmatiello.tui.core-test
        me.pmatiello.tui.internal.ansi-test
        me.pmatiello.tui.internal.rendering-test])
    (apply require test-namespaces)
    (let [{:keys [test fail error]} (apply clojure.test/run-tests test-namespaces)]
      (shutdown-agents)
      (System/exit (if (and (pos? test) (zero? fail) (zero? error)) 0 1)))
  '';
in
stdenvNoCC.mkDerivation {
  pname = "tui";
  version = "0.2.0-unstable-2023-06-22";

  src = fetchFromGitHub {
    owner = "pmatiello";
    repo = "tui";
    rev = "e435b1b60dbcc86b91060ccff70fe765b3285224";
    hash = "sha256-lbNpl9AOI6R9C26oY7Ex409ihEstHKogR1qyLsr6R8g=";
  };

  nativeBuildInputs = [ jdk_headless ];

  dontConfigure = true;

  # A source-only jar: Clojure compiles the namespaces when they load.
  # Sorted entries and a fixed date keep the jar reproducible.
  buildPhase = ''
    runHook preBuild
    (cd src && jar --create --file ../tui.jar --date=1980-01-01T00:00:02Z \
      $(find . -type f -name '*.clj' | LC_ALL=C sort))
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    # Fail if upstream adds a test file the runner does not list.
    test "$(find test -name '*_test.clj' | wc -l)" -eq 3
    java -Dfile.encoding=UTF-8 -Duser.home="$HOME" -Djava.io.tmpdir="$TMPDIR" \
      -cp "tui.jar:test:${runtimeClasspath}" clojure.main ${runTests} </dev/null
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 tui.jar "$out/share/java/tui.jar"
    mkdir -p "$out/share/tui" "$out/bin"
    cp -r test "$out/share/tui/tests"
    install -Dm444 LICENSE README.md CHANGELOG.md deps.edn build.clj \
      -t "$out/share/doc/tui"
    cat > "$out/bin/tui-clojure" <<'EOF'
    #!${runtimeShell}
    exec ${jdk_headless}/bin/java -Dfile.encoding=UTF-8 \
      -Djava.io.tmpdir="''${TMPDIR:-/tmp}" \
      -Duser.home="''${HOME:-/tmp}" \
      -cp '${placeholder "out"}/share/java/tui.jar:${runtimeClasspath}'"''${CLASSPATH:+:$CLASSPATH}" \
      clojure.main "$@"
    EOF
    chmod 555 "$out/bin/tui-clojure"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    "$out/bin/tui-clojure" -e '(require (quote me.pmatiello.tui.core)) (print (me.pmatiello.tui.core/render [{:style [:bold] :body "x"}])) (flush)' \
      </dev/null > rendered
    printf '\033[1mx\033[0m' > expected
    cmp rendered expected
    CLASSPATH="$out/share/tui/tests" "$out/bin/tui-clojure" ${runTests} </dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Styled terminal text and line input for Clojure";
    longDescription = ''
      Tui renders pages of ANSI-styled text and reads lines from standard
      input for Clojure programs.  The tui-clojure launcher starts a Clojure
      REPL or script with the library and the Clojure runtime on the class
      path, without Maven or Git dependency resolution.
    '';
    homepage = "https://github.com/pmatiello/tui";
    # tui is EPL-2.0.  The Clojure runtime jars (EPL-1.0) are referenced on
    # the launcher class path, not redistributed in this output.
    license = lib.licenses.epl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "tui-clojure";
  };
}
