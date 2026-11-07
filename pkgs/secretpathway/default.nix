{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  jdk17,
  jdk17_headless,
  runtimeShell,
  stripJavaArchivesHook,
  makeDesktopItem,
  copyDesktopItems,
  writeText,
}:

let
  # Upstream has no test suite.  Load the finished jar in a separate JVM and
  # check its version constant and a fail-closed connection-construction path.
  checkSource = writeText "SecretPathwayCheck.java" ''
    import mhahnFr.SecretPathway.core.Constants;
    import mhahnFr.SecretPathway.core.net.ConnectionFactory;

    public final class SecretPathwayCheck {
      public static void main(String[] args) {
        if (!"1.0".equals(Constants.VERSION))
          throw new AssertionError(Constants.VERSION);
        if (ConnectionFactory.create("127.0.0.1", 0) != null)
          throw new AssertionError("invalid endpoint accepted");
      }
    }
  '';
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "secretpathway";
  version = "1.0.0-unstable-2023-05-22";

  # fetchSubmodules pins the JUtilities submodule at
  # 564dd18b6c8e034b912a04dc73f621ec479c62b3.
  src = fetchFromGitHub {
    owner = "mhahnFr";
    repo = "SecretPathway";
    rev = "2ea2e6bac49aa96781d726f7b3c14bd5fbc7c141";
    fetchSubmodules = true;
    hash = "sha256-RnxGNchDuY1Ora1uHFackKva3J5g9LYbqmGvRrHMU4g=";
  };

  nativeBuildInputs = [
    jdk17_headless
    stripJavaArchivesHook
    copyDesktopItems
  ];

  dontConfigure = true;

  # JUtilities calls Desktop.getDesktop() unconditionally to install macOS
  # global menu handlers, which aborts Swing startup on Linux.  Skip that path
  # so JUtilities uses its ordinary Swing menu bar.  The Gradle wrapper jars
  # are unused prebuilt binaries.
  postPatch = ''
    substituteInPlace JUtilities/src/mhahnFr/utils/gui/menu/MenuFactory.java \
      --replace-fail '    private MenuFactory() {' '    private MenuFactory() {
            if (!System.getProperty("os.name").toLowerCase().contains("mac")
                    || !Desktop.isDesktopSupported()) {
                menubar = false;
                return;
            }'
    rm gradle/wrapper/gradle-wrapper.jar JUtilities/gradle/wrapper/gradle-wrapper.jar
  '';

  # Upstream builds with Gradle, which needs network access.  The sources have
  # no resources or dependencies, so compile them and the JUtilities submodule
  # into one jar, as upstream's jar task does.
  buildPhase = ''
    runHook preBuild
    cp -r JUtilities/src/mhahnFr/utils src/mhahnFr/utils
    find src -name '*.java' | LC_ALL=C sort > sources.txt
    javac --release 17 -encoding UTF-8 -d classes @sources.txt
    jar --create --file secretpathway.jar --date=1980-01-01T00:00:02Z \
      --main-class mhahnFr.SecretPathway.SecretPathway -C classes .
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    mkdir check-classes
    # javac requires a public class's source file to carry the class name.
    cp ${checkSource} SecretPathwayCheck.java
    javac --release 17 -cp secretpathway.jar -d check-classes SecretPathwayCheck.java
    java -Djava.awt.headless=true -Duser.home="$TMPDIR" \
      -cp secretpathway.jar:check-classes SecretPathwayCheck
    runHook postCheck
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "secretpathway";
      desktopName = "SecretPathway";
      comment = "Connect to text-based MUD servers";
      exec = "secretpathway";
      terminal = false;
      categories = [ "Game" "Network" ];
    })
  ];

  installPhase = ''
    runHook preInstall
    install -Dm444 secretpathway.jar "$out/share/java/secretpathway.jar"
    install -Dm444 README.md LICENSE -t "$out/share/doc/secretpathway"
    install -Dm444 JUtilities/LICENSE "$out/share/doc/secretpathway/JUtilities-LICENSE"
    mkdir -p "$out/bin"
    # Java derives user.home from the account database and can ignore HOME.
    # Keep the Preferences tree under HOME explicitly.
    cat > "$out/bin/secretpathway" <<'EOF'
    #!${runtimeShell}
    exec ${jdk17}/bin/java -Duser.home="''${HOME:-$PWD}" \
      -jar '${placeholder "out"}/share/java/secretpathway.jar' "$@"
    EOF
    chmod 555 "$out/bin/secretpathway"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    grep -qF '${jdk17}/bin/java' "$out/bin/secretpathway"
    grep -qF "$out/share/java/secretpathway.jar" "$out/bin/secretpathway"
    grep -qF '"''${HOME:-$PWD}"' "$out/bin/secretpathway"
    mkdir manifest-check
    (cd manifest-check && jar xf "$out/share/java/secretpathway.jar" META-INF/MANIFEST.MF)
    grep -q 'Main-Class: mhahnFr.SecretPathway.SecretPathway' manifest-check/META-INF/MANIFEST.MF
    java -Djava.awt.headless=true -Duser.home="$TMPDIR" \
      -cp "$out/share/java/secretpathway.jar:check-classes" SecretPathwayCheck
    test -f "$out/share/applications/secretpathway.desktop"
    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical MUD client with an LPC source editor";
    longDescription = ''
      SecretPathway is a graphical Java MUD client.  It supports Telnet, ANSI
      colors, the SecretPathway protocol, and an integrated LPC source editor.
    '';
    homepage = "https://github.com/mhahnFr/SecretPathway";
    # README says GPL 3.0; the source headers of both SecretPathway and the
    # bundled JUtilities grant version 3 or any later version.
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "secretpathway";
  };
})
