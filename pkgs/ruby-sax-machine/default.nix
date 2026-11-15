{
  lib,
  buildRubyGem,
  fetchFromGitHub,
  ruby,
}:

let
  nokogiri = ruby.gems.nokogiri;
  rubyWithSpecs = ruby.withPackages (ps: [
    ps.rspec
    ps.activerecord
    ps.sqlite3
    ps.nokogiri
  ]);
  rubyWithNokogiri = ruby.withPackages (ps: [ ps.nokogiri ]);
in
buildRubyGem rec {
  gemName = "sax-machine";
  version = "1.3.2";
  inherit ruby;

  src = fetchFromGitHub {
    owner = "pauldix";
    repo = "sax-machine";
    rev = "6d193af3b139215d6946b2db050501024820fa89";
    hash = "sha256-+1UVfs53Mat/XZEbRUmM5n+t0HSgjJ7qq3KLrYuxjUw=";
  };

  propagatedBuildInputs = [ nokogiri ];

  postPatch = ''
    # The gemspec lists files with `git ls-files`; the fetched source has no
    # repository, so enumerate the tree instead.
    substituteInPlace sax-machine.gemspec \
      --replace-fail '`git ls-files`.split("\n")' \
        "Dir.glob('**/*').select { |f| File.file?(f) }.sort" \
      --replace-fail '`git ls-files -- {test,spec,features}/*`.split("\n")' \
        "Dir.glob('{test,spec,features}/**/*').select { |f| File.file?(f) }.sort"

    # ActiveRecord::Inheritance.new forwards nil, and a base class needs its
    # own initializer run before SAX assignment.
    substituteInPlace lib/sax-machine/sax_document.rb \
      --replace-fail 'def initialize(attributes = {})' \
        'def initialize(attributes = nil)
          super()' \
      --replace-fail '      attributes.each do' \
        '      (attributes || {}).each do'
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    # ActiveRecord 7 reads attribute metadata even for an unsaved model, so
    # give the ActiveRecord spec an in-memory table.
    cat > spec/nix-activerecord.rb <<'EOF'
    require 'active_record'
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ActiveRecord::Schema.define { create_table(:my_sax_models) }
    EOF
    HANDLER=nokogiri ${rubyWithSpecs}/bin/rspec -r ./spec/nix-activerecord.rb spec

    # The installed gem parses a document without the source tree.
    (cd "$TMPDIR" && GEM_PATH="$out/${ruby.gemPath}" ${rubyWithNokogiri}/bin/ruby -e '
      require "sax-machine"
      class Entry
        include SAXMachine
        element :title
      end
      abort "unexpected handler" unless SAXMachine.handler == :nokogiri
      abort "unexpected version" unless SAXMachine::VERSION == "${version}"
      abort "unexpected origin" unless $LOADED_FEATURES.grep(/sax_document/).first.start_with?(ENV.fetch("out"))
      title = Entry.parse("<entry><title>Installed</title></entry>").title
      abort "unexpected parse" unless title == "Installed"
    ')

    runHook postInstallCheck
  '';

  postInstall = ''
    install -Dm444 README.md HISTORY.md -t $out/share/doc/ruby-sax-machine
  '';

  meta = {
    description = "Declarative SAX XML parsing for Ruby";
    longDescription = ''
      SAX Machine maps XML elements and attributes to Ruby objects using a
      declarative interface.  This package provides the Nokogiri backend.
    '';
    homepage = "https://github.com/pauldix/sax-machine";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
