{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
}:

buildNpmPackage (finalAttrs: {
  pname = "react-blessed";
  version = "0.7.2";

  src = fetchFromGitHub {
    owner = "Yomguithereal";
    repo = "react-blessed";
    rev = "b686438af2726111637ef17b998f0f6967623640";
    hash = "sha256-FKbMzUcK+QZFrMe9T22MTkw+ib+t/FQ+xwUqxI4qnu8=";
  };

  nodejs = nodejs_22;

  # Upstream's lock records exact versions but omits 'resolved' and
  # 'integrity' for 447 of its 448 entries, so npm ci cannot install it
  # offline.  package-lock.json here is that lock with registry tarball URLs
  # and integrity filled in for the same versions and tree layout.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';
  npmDepsHash = "sha256-8249JPSejRnTh4j6GPjY5vRnjxGOMgLDQ+uYzFhh+lM=";
  npmRebuildFlags = [ "--ignore-scripts" ];

  env.NO_UPDATE_NOTIFIER = "1";

  # The default build is upstream's `npm run build`: rimraf dist, then the
  # rollup CommonJS and ES module bundles.

  doCheck = true;
  # Mocha with @babel/register over test/endpoint.js.
  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';

  # Install the bundles with their runtime closure.  React and Blessed are
  # peers; they are included so the module works on its own, as in Guix.
  # The optional react-devtools-core integration is not included.
  installPhase = ''
    runHook preInstall

    module=$out/lib/node_modules/react-blessed
    mkdir -p "$module/node_modules" $out/share/doc/react-blessed
    cp -r dist package.json LICENSE.txt README.md "$module"
    for dep in blessed js-tokens loose-envify object-assign react \
               react-reconciler scheduler; do
      cp -r "node_modules/$dep" "$module/node_modules/$dep"
    done
    ln -s "$module/LICENSE.txt" "$module/README.md" $out/share/doc/react-blessed/

    runHook postInstall
  '';

  doInstallCheck = true;
  # Render a component into an off-terminal Blessed screen from the installed
  # module, then update its state and check that React patched the same box.
  installCheckPhase = ''
    runHook preInstallCheck

    cat > check.cjs <<'EOF'
    const { PassThrough } = require('stream');
    const moduleDir = process.argv[2];
    const blessed = require(moduleDir + '/node_modules/blessed');
    const React = require(moduleDir + '/node_modules/react');
    const { render } = require(moduleDir);

    const output = new PassThrough();
    output.columns = 80;
    output.rows = 24;
    output.resume();
    const screen = blessed.screen({
      input: new PassThrough(),
      output,
      terminal: 'xterm',
      warnings: false,
    });

    // React Blessed renders string children as a text element inside the box.
    const text = box => box && box.children.find(child => child.type === 'text');

    let setLabel;
    function View() {
      const [label, set] = React.useState('first');
      setLabel = set;
      return React.createElement('box', { label: 'check', width: 20, height: 3 }, label);
    }

    render(React.createElement(View), screen);
    const box = screen.children[0];
    if (screen.children.length !== 1 || box.type !== 'box' || text(box).getContent() !== 'first')
      throw new Error('initial render failed');
    setLabel('second');
    if (screen.children.length !== 1 || screen.children[0] !== box || text(box).getContent() !== 'second')
      throw new Error('update failed');
    screen.destroy();
    console.log('react-blessed render check passed');
    EOF
    ${lib.getExe finalAttrs.nodejs} check.cjs $out/lib/node_modules/react-blessed

    runHook postInstallCheck
  '';

  meta = {
    description = "React renderer for Blessed terminal interfaces";
    homepage = "https://github.com/Yomguithereal/react-blessed";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
