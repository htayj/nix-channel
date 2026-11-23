{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchNpmDeps,
  nodejs,
  closurecompiler,
  jre_headless,
}:

buildNpmPackage (finalAttrs: {
  pname = "litegraph";
  version = "0.7.14-unstable-2024-01-08";

  src = fetchFromGitHub {
    owner = "jagenjo";
    repo = "litegraph.js";
    rev = "0555a2f2a3df5d4657593c6d45eb192359888195";
    hash = "sha256-a1KlRpgdlSSsjzudO1vN8Kbqdkta4+A53cF+6EYCCZ8=";
  };

  # Upstream's lockfile (version 3) records resolved registry URLs and
  # integrity for every entry.
  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    hash = "sha256-DmR18odUxXkN6DARdAaywWaZAMbmfxqeQLnN78LvxvM=";
  };
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ jre_headless ];

  env.NO_UPDATE_NOTIFIER = "1";

  # package.json was bumped without regenerating the lockfile; npm ci needs the
  # devDependency ranges the lockfile was resolved from.  The inactive
  # depth-of-field comment in glfx.js carries an unlicensed third-party shader
  # that concat would copy into the readable bundle, so drop exactly that block.
  postPatch = ''
    ${lib.getExe nodejs} -e '
      const fs = require("fs");
      const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      pkg.devDependencies = lock.packages[""].devDependencies;
      fs.writeFileSync("package.json", JSON.stringify(pkg, null, 4) + "\n");

      const file = "src/nodes/glfx.js";
      const text = fs.readFileSync(file, "utf8");
      const start = text.indexOf("/* not working yet");
      const marker = "global.LGraphDepthOfField = LGraphDepthOfField;\r\n\t*/\r\n";
      const end = start < 0 ? -1 : text.indexOf(marker, start);
      if (end < 0 || !text.slice(start, end).includes("tuxedolabs.blogspot.com")
          || text.indexOf("/* not working yet", end) >= 0)
        throw new Error("unexpected inactive depth-of-field block");
      fs.writeFileSync(file, text.slice(0, start) + text.slice(end + marker.length));

      // base.js declares the same length() helper twice in one scope, which
      // current Closure Compiler rejects.  Both bodies are identical, so keep one.
      const base = "src/nodes/base.js";
      const source = fs.readFileSync(base, "utf8");
      const helper = "    function length(v) {\r\n        if(v && v.length != null)\r\n\t\t\treturn Number(v.length);\r\n\t\treturn 0;\r\n    }\r\n\r\n";
      const first = source.indexOf(helper), second = source.lastIndexOf(helper);
      if (first < 0 || second === first || source.indexOf(helper, first + 1) !== second)
        throw new Error("unexpected length() helpers in base.js");
      fs.writeFileSync(base, source.slice(0, second) + source.slice(second + helper.length));
    '
    # Committed bundles and API docs are outputs, not inputs.
    rm -rf build doc
  '';

  # grunt-closure-tools runs `java -jar` on this fixed Gruntfile path; use the
  # nixpkgs Closure Compiler instead of the jar bundled in the npm package.
  dontNpmBuild = true;
  buildPhase = ''
    runHook preBuild
    rm -f node_modules/google-closure-compiler/compiler.jar
    ln -s ${closurecompiler}/share/java/closure-compiler-v${closurecompiler.version}.jar \
      node_modules/google-closure-compiler/compiler.jar
    node node_modules/grunt-cli/bin/grunt build
    for f in build/litegraph.js build/litegraph.min.js; do
      test "$(stat -c %s "$f")" -gt 100000
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    module=$out/lib/node_modules/litegraph.js
    doc=$out/share/doc/litegraph
    for f in build/litegraph.js build/litegraph.min.js src/litegraph-editor.js \
             src/litegraph.d.ts css/litegraph.css css/litegraph-editor.css LICENSE; do
      install -Dm644 "$f" "$module/$f"
    done
    cat > "$module/package.json" <<'EOF'
    {"name":"litegraph.js","version":"0.7.14","license":"MIT","main":"build/litegraph.js","types":"src/litegraph.d.ts"}
    EOF
    # litegraph-editor.css resolves ../editor/imgs/.
    mkdir -p "$module/editor"
    cp -r editor/imgs "$module/editor/imgs"
    install -Dm644 -t "$doc" LICENSE README.md
    install -Dm644 -t "$doc/guides" guides/README.md
    install -Dm644 ${./litegraph-embedded-notices.txt} "$doc/THIRD-PARTY-NOTICES"
    install -Dm644 ${./litegraph-embedded-notices.txt} "$module/THIRD-PARTY-NOTICES"
    runHook postInstall
  '';

  # Both installed bundles must load in plain Node, execute a 7 + 5 graph,
  # survive a JSON round trip and keep the imported copy independent.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node ${./litegraph-engine.cjs} "$out/lib/node_modules/litegraph.js"
    runHook postInstallCheck
  '';

  meta = {
    description = "JavaScript graph engine with a browser canvas node editor";
    homepage = "https://github.com/jagenjo/litegraph.js";
    # LiteGraph is MIT; the bundles embed BSD-3 GPUImage and MIT shaders, and
    # Closure Compiler may inject Apache-2.0 runtime helpers.
    license = with lib.licenses; [
      mit
      bsd3
      asl20
    ];
    platforms = [ "x86_64-linux" ];
  };
})
