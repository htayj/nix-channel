{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  coreutils,
  jdk_headless,
  runtimeShell,
  stripJavaArchivesHook,
  unzip,
}:

let
  maven = path: hash: fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/${path}";
    inherit hash;
  };

  # Clojure 1.10.3 is the version project.clj pins; spec.alpha and
  # core.specs.alpha are the versions its POM requires.  data.json 0.2.6 is
  # pinned by deps.edn and project.clj.  All four are EPL-1.0 and stay on the
  # launcher class path rather than inside liquid.jar.
  runtimeJars = [
    (maven "clojure/1.10.3/clojure-1.10.3.jar" "sha256-fxJHLa7Y9rUXSYqqKrE6ViR1w+31FHjkWBzHYemJeaM=")
    (maven "spec.alpha/0.2.194/spec.alpha-0.2.194.jar" "sha256-z2iZ+YUpjGSxPqEplGrZAo3uja3w6rmuGORVAn04JJw=")
    (maven "core.specs.alpha/0.2.56/core.specs.alpha-0.2.56.jar" "sha256-/PRCveArBKhj8vzFjuaiowxM8Mlw99q4VjTwq3ERZrY=")
    (maven "data.json/0.2.6/data.json-0.2.6.jar" "sha256-f2Jhncxnd1IbbuKeq2mynXH4Jv/w1werN2desioimXQ=")
  ];
  depsClasspath = lib.concatStringsSep ":" runtimeJars;

  testNamespaces = [
    "liq.buffer-test"
    "liq.commands-test"
    "liq.editor-test"
    "liq.extras.freemove-mode-test"
    "liq.extras.html-tool-test"
    "liq.extras.markdownfolds-test"
    "liq.modes.fundamental-mode-test"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "liquid";
  version = "2.1.2-unstable-2022-03-11";

  src = fetchFromGitHub {
    owner = "mogenslund";
    repo = "liquid";
    rev = "045f587b3914485baf85d9eae4f97f968cbfafaa";
    hash = "sha256-zirMtmwhArAkQK+tyMko8A/ZrjWAhrV4oZvkpH4w6fY=";
  };

  nativeBuildInputs = [
    jdk_headless
    stripJavaArchivesHook
    unzip
  ];

  # Terminal control runs stty through /bin/sh, and the shell command runs
  # through /bin/sh as well.  Point both at store paths, checking the exact
  # number of call sites so an upstream change cannot slip through.
  postPatch = ''
    expect_count() {
      local n
      n=$(grep -oF -- "$2" "$1" | wc -l)
      if [ "$n" != "$3" ]; then
        echo "$1: expected $3 occurrences of '$2', found $n" >&2
        exit 1
      fi
    }
    stty_call='"/bin/sh" "-c" "stty '
    expect_count src/liq/tty_input.clj "$stty_call" 5
    expect_count src/liq/tty_output.cljc "$stty_call" 4
    expect_count src/liq/commands.cljc '"/bin/sh"' 1
    substituteInPlace src/liq/tty_input.clj src/liq/tty_output.cljc \
      --replace-fail "$stty_call" '"${runtimeShell}" "-c" "${coreutils}/bin/stty '
    substituteInPlace src/liq/commands.cljc \
      --replace-fail '"/bin/sh"' '"${runtimeShell}"'
    if grep -rnF '/bin/sh' src; then
      echo 'unpatched /bin/sh reference' >&2
      exit 1
    fi
  '';

  dontConfigure = true;

  # Every JVM namespace under src/liq is AOT compiled, including optional
  # extras such as liq.extras.html-tool that liq.core does not load itself.
  # liq/core.cljc ends with (ns user ...), so compiling liq.core also emits
  # top-level user$... classes that liq.core__init loads.  Those go into the
  # jar with the liq classes and the help texts; transitively compiled
  # clojure/data/json classes are dropped because data.json stays on the
  # class path.
  buildPhase = ''
    runHook preBuild
    mkdir classes
    namespaces=$(cd src && find liq -type f \( -name '*.clj' -o -name '*.cljc' \) \
      | LC_ALL=C sort | sed -e 's/\.cljc\?$//' -e 's|/|.|g' -e 's/_/-/g' \
      | sed "s/^/'/" | tr '\n' ' ')
    echo "compiling: $namespaces"
    java -Dfile.encoding=UTF-8 -Duser.home="$TMPDIR" \
      -Dclojure.compile.path=classes \
      -cp "src:resources:classes:${depsClasspath}" \
      clojure.main -e "(doseq [n [$namespaces]] (compile n))" </dev/null
    test -f classes/liq/core__init.class
    test -f classes/liq/extras/html_tool__init.class
    ls classes/user\$*.class >/dev/null
    if find classes -maxdepth 1 -type f -name '*.class' ! -name 'user$*' | grep -q .; then
      echo 'unexpected top-level classes' >&2
      exit 1
    fi
    cp -r resources/help classes/help
    (cd classes && jar --create --file ../liquid.jar \
      --date=1980-01-01T00:00:02Z --main-class liq.core \
      $( (find liq help -type f; find . -maxdepth 1 -type f -name 'user$*.class' -printf '%P\n') | LC_ALL=C sort))
    runHook postBuild
  '';

  # Upstream's clojure.test suite, run against the AOT classes.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    java -Dfile.encoding=UTF-8 -Duser.home="$TMPDIR" \
      -cp "test:liquid.jar:${depsClasspath}" \
      clojure.main -e "
        (require 'clojure.test ${lib.concatMapStringsSep " " (ns: "'${ns}") testNamespaces})
        (let [r (clojure.test/run-tests ${lib.concatMapStringsSep " " (ns: "'${ns}") testNamespaces})]
          (shutdown-agents)
          (System/exit (if (and (pos? (:test r)) (zero? (+ (:fail r) (:error r)))) 0 1)))" </dev/null
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 liquid.jar "$out/share/java/liquid.jar"
    install -Dm444 LICENSE README.md CHANGELOG.md -t "$out/share/doc/liquid"
    mkdir -p "$out/bin"
    cat > "$out/bin/liquid" <<'EOF'
    #!${runtimeShell}
    # Keep JVM performance data out of the shared /tmp, and follow the
    # caller's HOME (for ~/.liq) and TMPDIR.
    exec ${jdk_headless}/bin/java -XX:-UsePerfData -Dfile.encoding=UTF-8 \
      ''${HOME:+"-Duser.home=$HOME"} ''${TMPDIR:+"-Djava.io.tmpdir=$TMPDIR"} \
      -cp '${placeholder "out"}/share/java/liquid.jar:${depsClasspath}' \
      liq.core "$@"
    EOF
    chmod 555 "$out/bin/liquid"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    grep -qF '${jdk_headless}/bin/java' "$out/bin/liquid"
    unzip -Z1 "$out/share/java/liquid.jar" > entries
    grep -qx 'liq/core__init.class' entries
    grep -qx 'help/help.txt' entries
    grep -q '^user\$.*\.class$' entries
    if grep -q '^clojure/' entries; then
      echo 'bundled clojure classes' >&2
      exit 1
    fi
    unzip -p "$out/share/java/liquid.jar" 'liq/tty_input$set_raw_mode.class' | grep -qaF '${coreutils}/bin/stty'
    test -f "$out/share/doc/liquid/LICENSE"
    runHook postInstallCheck
  '';

  meta = {
    description = "Modal terminal text editor written in Clojure";
    longDescription = ''
      Liquid is a Vim-like modal text editor for Clojure and Markdown files
      that runs in a terminal and can be extended with Clojure code at
      runtime.  User configuration is read from ~/.liq.
    '';
    homepage = "https://github.com/mogenslund/liquid";
    # Liquid and its Clojure, spec and data.json runtime jars are EPL-1.0.
    license = lib.licenses.epl10;
    platforms = [ "x86_64-linux" ];
    mainProgram = "liquid";
  };
}
