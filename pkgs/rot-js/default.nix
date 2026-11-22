{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  closurecompiler,
}:

buildNpmPackage (finalAttrs: {
  pname = "rot-js";
  version = "2.2.1";

  src = fetchFromGitHub {
    owner = "ondras";
    repo = "rot.js";
    rev = "46782e248c2db9d379a5e4f13bb8323f18dff04b";
    hash = "sha256-s2eaeabzRe4sYQzIGBha3AtYNvsoM8rZAuj9+TYYpW0=";
  };

  nodejs = nodejs_22;

  # Upstream's lockfile (version 3) records resolved URLs and integrity for
  # every entry.  npm skips the optional Closure native images for other
  # platforms and fsevents, the only package with an install script.
  npmDepsHash = "sha256-T1jEVQech9gXauvkhl4qZIEsF7nH5BWUF6f4ZJHSnGs=";
  npmRebuildFlags = [ "--ignore-scripts" ];

  env.NO_UPDATE_NOTIFIER = "1";

  # Rebuild every generated output from src/ instead of shipping upstream's.
  postPatch = ''
    rm -rf lib dist doc .ts.flag
    mkdir lib dist doc
  '';

  # Upstream's Makefile pipeline: tsc, rollup piped through babel, Closure
  # Compiler, then TypeDoc.  nixpkgs' Closure Compiler replaces the npm
  # wrapper's prebuilt jar and native images; the flags pin upstream's
  # SIMPLE optimisation and keep the minified bundle at babel's ES5 level.
  dontNpmBuild = true;
  buildPhase = ''
    runHook preBuild
    make all GCC="${lib.getExe closurecompiler} --compilation_level SIMPLE --language_out ECMASCRIPT5"
    for f in dist/rot.js dist/rot.min.js lib/index.js lib/index.d.ts doc/index.html; do
      test -s "$f"
    done
    runHook postBuild
  '';

  # The files listed in upstream's package.json.  rot.js has no runtime
  # dependencies.
  installPhase = ''
    runHook preInstall
    module=$out/lib/node_modules/rot-js
    mkdir -p "$module" $out/share/doc/rot-js
    cp -r lib dist doc examples addons manual package.json license.txt README.md "$module"
    ln -s "$module"/license.txt "$module"/README.md $out/share/doc/rot-js/
    ln -s "$module"/doc $out/share/doc/rot-js/api
    runHook postInstall
  '';

  # A seeded dungeon, its rooms and a field-of-view computation must agree
  # across the UMD bundle, the Closure-minified bundle and the ES modules.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    cat > run.cjs <<'EOF'
    module.exports = ROT => {
      ROT.RNG.setSeed(12345);
      const map = {};
      let floor = 0;
      const digger = new ROT.Map.Digger(40, 20);
      digger.create((x, y, wall) => {
        map[x + "," + y] = wall;
        if (!wall) floor++;
      });
      const rooms = digger.getRooms();
      if (floor === 0 || rooms.length === 0) throw new Error("empty map");
      const [cx, cy] = rooms[0].getCenter();
      const fov = new ROT.FOV.PreciseShadowcasting((x, y) => map[x + "," + y] === 0);
      let seen = 0;
      fov.compute(cx, cy, 6, () => seen++);
      if (seen < 2) throw new Error("field of view saw nothing");
      return JSON.stringify([floor, rooms.length, seen, ROT.RNG.getUniform()]);
    };
    EOF
    cat > check.cjs <<'EOF'
    const run = require("./run.cjs");
    const m = process.argv[2];
    const umd = run(require(m));
    const min = run(require(m + "/dist/rot.min.js"));
    if (umd !== min) throw new Error("minified bundle differs: " + umd + " vs " + min);
    import(m + "/lib/index.js")
      .then(esm => {
        const mod = run(esm);
        if (mod !== umd) throw new Error("ES modules differ: " + mod + " vs " + umd);
        console.log("rot.js check passed", umd);
      })
      .catch(e => {
        console.error(e);
        process.exit(1);
      });
    EOF
    ${lib.getExe finalAttrs.nodejs} check.cjs $out/lib/node_modules/rot-js
    runHook postInstallCheck
  '';

  meta = {
    description = "Roguelike toolkit in JavaScript";
    homepage = "https://ondras.github.io/rot.js";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
  };
})
