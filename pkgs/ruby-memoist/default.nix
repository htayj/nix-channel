{
  lib,
  buildRubyGem,
  fetchFromGitHub,
  ruby,
}:

let
  rubyWithMinitest = ruby.withPackages (ps: [ ps.minitest ]);
in
buildRubyGem rec {
  gemName = "memoist";
  version = "0.16.2";
  inherit ruby;

  src = fetchFromGitHub {
    owner = "matthewrudy";
    repo = "memoist";
    rev = "b12aff232bd3a41dcab6eb5763907c9c4d13bc41";
    hash = "sha256-1X1LqcPIkro0ZCQQQD5654akHZ9usrm9g3+1o9qEN3A=";
  };

  # The gemspec lists files with `git ls-files`; the fetched source has no
  # repository, so enumerate the tree instead.
  postPatch = ''
    substituteInPlace memoist.gemspec \
      --replace-fail '`git ls-files -z`.split("\x0")' \
        "Dir.glob('**/*').select { |f| File.file?(f) }.sort"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${rubyWithMinitest}/bin/ruby -Ilib:test test/memoist_test.rb
    runHook postInstallCheck
  '';

  postInstall = ''
    install -Dm444 LICENSE.md README.md -t $out/share/doc/ruby-memoist
  '';

  meta = {
    description = "Memoize Ruby method calls";
    longDescription = ''
      Memoist caches Ruby method results, including methods with arguments,
      and supports flushing and reloading the cached values.
    '';
    homepage = "https://github.com/matthewrudy/memoist";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
