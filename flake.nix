{
  description = "Taylor's package channel";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # Keep Autolith's independent pin: SBCL and its Lisp package set must match.
  inputs.autolith.url = "github:htayj/autolith";
  # Upstream ships its own packaging; build it against the channel's nixpkgs so
  # the QML module matches consumers' Qt.
  inputs.m3shapes.url = "github:soramanew/m3shapes/32ad9ce328bb77ed349b40a3be10ee9ea610b8ab";
  inputs.m3shapes.inputs.nixpkgs.follows = "nixpkgs";
  # Upstream ships its own clj-nix packaging. Keep its nixpkgs pin: the offline
  # build resolves the Clojure release recorded in upstream's deps-lock.json.
  inputs.eca.url = "github:editor-code-assistant/eca/52b6f015b3857d60920f7edbe9ed5692db0ba57d";
  # Upstream ships its own packaging. Build it against the channel's nixpkgs so
  # the embedded CPython is the one consumers already have.
  inputs.mudpuppy.url = "github:mudpuppy-rs/mudpuppy/3199e83e6173df178f17906b721630d927789c87";
  inputs.mudpuppy.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, autolith, eca, m3shapes, mudpuppy, ... }:
    let
      # Start with the platform validated by this channel.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # The JVM build of tag 0.154.0, which upstream's flake names eca-DEV. The
      # source stays upstream's pinned tree; only the name gains the version.
      # The GraalVM native image is not exported.
      ecaPackage = system: eca.packages.${system}.eca-jdk.overrideAttrs (old: {
        version = "0.154.0";
        __intentionallyOverridingVersion = true;
        meta = old.meta // {
          description = "Editor-agnostic code assistant server";
          longDescription = ''
            ECA provides an editor-agnostic JSON-RPC code assistant server and
            CLI.  Start it with `eca server` from an editor client.  Provider
            credentials, network access, model services, plugins and MCP
            servers are runtime concerns of the user.
          '';
          homepage = "https://eca.dev";
          # ECA is Apache-2.0.  Its uberjar bundles Clojure libraries (EPL-1.0),
          # Jetty and the Servlet API (EPL-2.0 or Apache-2.0), MIT and
          # BSD-2-Clause code, and the JAXB and Activation APIs (CDDL-1.1 or
          # GPL-2.0 with the Classpath exception).  Javassist is used under its
          # Apache-2.0 alternative.
          license = with nixpkgs.lib.licenses; [
            asl20 epl10 epl20 mit bsd2
            {
              spdxId = "CDDL-1.1";
              shortName = "cddl11";
              fullName = "Common Development and Distribution License 1.1";
              url = "https://spdx.org/licenses/CDDL-1.1.html";
              free = true;
              redistributable = true;
            }
          ];
          # Compiled here from source; the Maven dependencies are upstream jars.
          sourceProvenance = with nixpkgs.lib.sourceTypes; [ fromSource binaryBytecode ];
          platforms = systems;
        };
      });
      # Upstream's package of the untagged commit pinned above, which its flake
      # names plain "mudpuppy". The source and the Cargo.lock graph stay
      # upstream's; the name gains a version and the licences are installed.
      mudpuppyPackage = system: mudpuppy.packages.${system}.pup.overrideAttrs (old: rec {
        pname = "mudpuppy";
        version = "0.1.0-unstable-2025-12-14";
        name = "${pname}-${version}";
        __intentionallyOverridingVersion = true;
        # Cargo links the locked crates statically, so ship their notices.
        postInstall = (old.postInstall or "") + ''
          install -Dm644 -t $out/share/doc/mudpuppy LICENSE README.md
          for crate in "''${cargoDeps:?}"/*/; do
            find "$crate" -maxdepth 1 -type f \
              \( -iname 'LICEN[SC]E*' -o -iname 'COPYING*' -o -iname 'COPYRIGHT*' \
                 -o -iname 'NOTICE*' -o -iname 'UNLICENSE*' \) \
              -exec install -Dm644 -t \
                "$out/share/doc/mudpuppy/third-party-licenses/$(basename "$crate")" {} +
          done
        '';
        doInstallCheck = true;
        installCheckPhase = ''
          runHook preInstallCheck
          HOME=$TMPDIR $out/bin/mudpuppy --version | grep -F 'mudpuppy 0.1.0'
          test -n "$(find $out/share/doc/mudpuppy/third-party-licenses -type f -print -quit)"
          runHook postInstallCheck
        '';
        meta = (old.meta or { }) // {
          description = "Terminal MUD client with embedded Python scripting";
          longDescription = ''
            Mudpuppy is a terminal client for MUD, MUSH, MUX and MUCK games with
            a Ratatui interface, Telnet negotiation, GMCP, plain TCP and rustls
            TLS connections, aliases, triggers and Python scripting.  Scripts,
            configuration and logs live in the per-user config and data
            directories.
          '';
          homepage = "https://github.com/mudpuppy-rs/mudpuppy";
          license = nixpkgs.lib.licenses.mit;
          mainProgram = "mudpuppy";
          platforms = systems;
        };
      });
      packageSet = system: {
        autolith = autolith.packages.${system}.default;
        eca = ecaPackage system;
        m3shapes = m3shapes.packages.${system}.m3shapes;
        mudpuppy = mudpuppyPackage system;
      };
      # Channel-maintained definitions, built against the consumer's package set.
      localPackages = pkgs: {
        acehack = pkgs.callPackage ./pkgs/acehack { };
        affect = pkgs.callPackage ./pkgs/affect { };
        agduria = pkgs.callPackage ./pkgs/agduria { };
        aiwnios = pkgs.callPackage ./pkgs/aiwnios { };
        aiwnios-bytecode = pkgs.callPackage ./pkgs/aiwnios-bytecode { aiwnios = pkgs.callPackage ./pkgs/aiwnios { }; };
        amstelvar = pkgs.callPackage ./pkgs/amstelvar { };
        apout = pkgs.callPackage ./pkgs/apout { };
        aquarium-arena = pkgs.callPackage ./pkgs/aquarium-arena { };
        aquesttoofar = pkgs.callPackage ./pkgs/aquesttoofar { };
        atarist-font = pkgs.callPackage ./pkgs/atarist-font { };
        atlas-warriors = pkgs.callPackage ./pkgs/atlas-warriors { };
        atrogue = pkgs.callPackage ./pkgs/atrogue { };
        avanor = pkgs.callPackage ./pkgs/avanor { };
        axmud = pkgs.callPackage ./pkgs/axmud { };
        azurra-gtk-theme = pkgs.callPackage ./pkgs/azurra-gtk-theme { };
        bcrawl = pkgs.callPackage ./pkgs/bcrawl { };
        bell-labs-rogue7 = pkgs.callPackage ./pkgs/bell-labs-rogue7 { };
        bell-museum = pkgs.callPackage ./pkgs/bell-museum { };
        bloatcrawl2 = pkgs.callPackage ./pkgs/bloatcrawl2 { };
        gnollcrawl = pkgs.callPackage ./pkgs/gnollcrawl { };
        gooncrawl = pkgs.callPackage ./pkgs/gooncrawl { };
        gnollhack = pkgs.callPackage ./pkgs/gnollhack { };
        blincolnlights = pkgs.callPackage ./pkgs/blincolnlights { };
        bootrogue = pkgs.callPackage ./pkgs/bootrogue { };
        brogue-lite = pkgs.callPackage ./pkgs/brogue-lite { };
        buzz-desktop = pkgs.callPackage ./pkgs/buzz-desktop { };
        cadr-fonts-latin = pkgs.callPackage ./pkgs/cadr-fonts { group = "latin"; };
        cadr-fonts-symbols = pkgs.callPackage ./pkgs/cadr-fonts { group = "symbols"; };
        calcrogue = pkgs.pkgsi686Linux.callPackage ./pkgs/calcrogue { };
        cavechop = pkgs.callPackage ./pkgs/cavechop { };
        city-of-the-condemned = pkgs.callPackage ./pkgs/city-of-the-condemned { };
        clojure-roguelike = pkgs.callPackage ./pkgs/clojure-roguelike { };
        computer-builder = pkgs.callPackage ./pkgs/computer-builder { };
        cracks-and-crevices = pkgs.callPackage ./pkgs/cracks-and-crevices { };
        crashrun = pkgs.callPackage ./pkgs/crashrun { };
        corerl = pkgs.callPackage ./pkgs/corerl { };
        cotd = pkgs.callPackage ./pkgs/cotd { };
        cryptrover = pkgs.callPackage ./pkgs/cryptrover { };
        curseforge = pkgs.callPackage ./pkgs/curseforge { };
        dec-fonts = pkgs.callPackage ./pkgs/dec-fonts { };
        dhack = pkgs.callPackage ./pkgs/dhack { };
        diabaig = pkgs.callPackage ./pkgs/diabaig { };
        dicom2mesh = pkgs.callPackage ./pkgs/dicom2mesh { };
        dnethack = pkgs.callPackage ./pkgs/dnethack { };
        dorxng-mcp = pkgs.callPackage ./pkgs/dorxng-mcp { };
        dynahack = pkgs.callPackage ./pkgs/dynahack { };
        dragonslayer = pkgs.callPackage ./pkgs/dragonslayer { };
        drl = pkgs.callPackage ./pkgs/drl { };
        dungeon-monkey-unlimited = pkgs.callPackage ./pkgs/dungeon-monkey-unlimited { };
        dungeonminder = pkgs.callPackage ./pkgs/dungeonminder { };
        durthang = pkgs.callPackage ./pkgs/durthang { };
        dwarftown = pkgs.callPackage ./pkgs/dwarftown { };
        emacs-chatgpt-el = pkgs.callPackage ./pkgs/emacs-chatgpt-el { };
        emacs-cl = pkgs.callPackage ./pkgs/emacs-cl { };
        emacs-emigo = pkgs.callPackage ./pkgs/emacs-emigo { };
        emacs-org-popup-posframe = pkgs.callPackage ./pkgs/emacs-org-popup-posframe { };
        emacs-pbui = pkgs.callPackage ./pkgs/emacs-pbui { };
        emacs-treesit-sexp = pkgs.callPackage ./pkgs/emacs-treesit-sexp { };
        encircled = pkgs.callPackage ./pkgs/encircled { };
        escape-from-lab-42 = pkgs.callPackage ./pkgs/escape-from-lab-42 { };
        everything-is-fodder = pkgs.callPackage ./pkgs/everything-is-fodder { };
        evilhack = pkgs.callPackage ./pkgs/evilhack { };
        exalt = pkgs.callPackage ./pkgs/exalt { };
        faangband = pkgs.callPackage ./pkgs/faangband { };
        farmingrl = pkgs.callPackage ./pkgs/farmingrl { };
        ffglitch = pkgs.callPackage ./pkgs/ffglitch { };
        fiqhack = pkgs.callPackage ./pkgs/fiqhack { };
        flaghack = pkgs.callPackage ./pkgs/flaghack { };
        font-exppd-unicode = pkgs.callPackage ./pkgs/font-exppd-unicode { };
        for-roguelike = pkgs.callPackage ./pkgs/for-roguelike {
          libtcod = (pkgs.callPackage ./pkgs/dwarftown { }).libtcod;
        };
        freelarn = pkgs.callPackage ./pkgs/freelarn { };
        frostbite = pkgs.callPackage ./pkgs/frostbite { };
        gearhead = pkgs.callPackage ./pkgs/gearhead { };
        gearhead2 = pkgs.callPackage ./pkgs/gearhead2 { };
        geminum-orbis = pkgs.callPackage ./pkgs/geminum-orbis { };
        gened = pkgs.callPackage ./pkgs/gened { inherit (localPackages pkgs) sbcl-mcclim; };
        genera-fonts-latin = pkgs.callPackage ./pkgs/genera-fonts { group = "latin"; };
        genera-fonts-symbols = pkgs.callPackage ./pkgs/genera-fonts { group = "symbols"; };
        go-mud = pkgs.callPackage ./pkgs/go-mud { };
        godisc = pkgs.callPackage ./pkgs/godisc { };
        goblins-lot = pkgs.callPackage ./pkgs/goblins-lot { };
        god-of-change = pkgs.callPackage ./pkgs/god-of-change {
          libtcod = (pkgs.callPackage ./pkgs/dwarftown { }).libtcod;
        };
        grippy-socks = pkgs.callPackage ./pkgs/grippy-socks { };
        gruesome = pkgs.callPackage ./pkgs/gruesome { };
        grunthack = pkgs.callPackage ./pkgs/grunthack { };
        hack = pkgs.callPackage ./pkgs/hack { };
        hackem = pkgs.callPackage ./pkgs/hackem { };
        hellcrawl = pkgs.callPackage ./pkgs/hellcrawl { };
        hunger-games = pkgs.callPackage ./pkgs/hunger-games { };
        hydra-slayer = pkgs.callPackage ./pkgs/hydra-slayer { };
        image-tape = pkgs.callPackage ./pkgs/image-tape { };
        infection = pkgs.callPackage ./pkgs/infection {
          libtcod = (pkgs.callPackage ./pkgs/dwarftown { }).libtcod;
        };
        interlisp-medley = pkgs.callPackage ./pkgs/interlisp-medley { };
        itstar = pkgs.callPackage ./pkgs/itstar { };
        ivory-key = pkgs.callPackage ./pkgs/ivory-key { };
        kbredir = pkgs.callPackage ./pkgs/kbredir { };
        kbtin = pkgs.callPackage ./pkgs/kbtin { };
        kildclient = pkgs.callPackage ./pkgs/kildclient { };
        kimchi = pkgs.callPackage ./pkgs/kimchi { };
        kitty-bitmap = pkgs.callPackage ./pkgs/kitty-bitmap { };
        klh10 = pkgs.callPackage ./pkgs/klh10 { };
        kmuddy = pkgs.callPackage ./pkgs/kmuddy { };
        ks10-udis = pkgs.callPackage ./pkgs/ks10-udis { };
        lbforth = pkgs.callPackage ./pkgs/lbforth { };
        letter-hunt = pkgs.callPackage ./pkgs/letter-hunt { };
        liveonce = pkgs.callPackage ./pkgs/liveonce { };
        liquid = pkgs.callPackage ./pkgs/liquid { };
        lispy-rogue = pkgs.callPackage ./pkgs/lispy-rogue { };
        ludviglundgren-qbittorrent-cli = pkgs.callPackage ./pkgs/ludviglundgren-qbittorrent-cli { };
        lyntin = pkgs.callPackage ./pkgs/lyntin { };
        manna-cadet = pkgs.callPackage ./pkgs/manna-cadet { };
        martins-dungeon-bash = pkgs.callPackage ./pkgs/martins-dungeon-bash { };
        meta-typing = pkgs.callPackage ./pkgs/meta-typing { };
        mmapper = pkgs.callPackage ./pkgs/mmapper { };
        modus = pkgs.callPackage ./pkgs/modus { };
        mushkin = pkgs.callPackage ./pkgs/mushkin { };
        mushtato = pkgs.callPackage ./pkgs/mushtato { };
        narwharl = pkgs.callPackage ./pkgs/narwharl { };
        nlarn = pkgs.callPackage ./pkgs/nlarn { };
        nitrohack = pkgs.callPackage ./pkgs/nitrohack { };
        node-unrs-resolver = pkgs.callPackage ./pkgs/node-unrs-resolver { };
        notion-river = pkgs.callPackage ./pkgs/notion-river { };
        nrl-text-to-phoneme = pkgs.callPackage ./pkgs/nrl-text-to-phoneme { };
        obumbrata = pkgs.callPackage ./pkgs/obumbrata { };
        ocaml-irc-client = pkgs.callPackage ./pkgs/ocaml-irc-client { };
        ocaml-irc-client-unix = pkgs.callPackage ./pkgs/ocaml-irc-client-unix { ocaml-irc-client = pkgs.callPackage ./pkgs/ocaml-irc-client { }; };
        ocaml-irc-client-lwt = pkgs.callPackage ./pkgs/ocaml-irc-client-lwt { ocaml-irc-client = pkgs.callPackage ./pkgs/ocaml-irc-client { }; };
        ocaml-irc-client-lwt-ssl = pkgs.callPackage ./pkgs/ocaml-irc-client-lwt-ssl { ocaml-irc-client = pkgs.callPackage ./pkgs/ocaml-irc-client { }; };
        oh-my-opencode-slim-companion = pkgs.callPackage ./pkgs/oh-my-opencode-slim-companion { };
        openclaw-desktop = pkgs.callPackage ./pkgs/openclaw-desktop { };
        pdp10-gcc = pkgs.callPackage ./pkgs/pdp10-gcc { };
        pdp10-its-disassembler = pkgs.callPackage ./pkgs/pdp10-its-disassembler { };
        pdp10-suppty = pkgs.callPackage ./pkgs/pdp10-suppty { };
        pdp10-xpl-pdp-10 = pkgs.callPackage ./pkgs/pdp10-xpl-pdp-10 { };
        pdp11 = pkgs.callPackage ./pkgs/pdp11 { };
        pdp6 = pkgs.callPackage ./pkgs/pdp6 { };
        persephil = pkgs.callPackage ./pkgs/persephil { };
        plomrogue = pkgs.callPackage ./pkgs/plomrogue { };
        potato = pkgs.callPackage ./pkgs/potato { };
        proiel = pkgs.callPackage ./pkgs/proiel { inherit (localPackages pkgs) ruby-memoist ruby-sax-machine; };
        pycat = pkgs.callPackage ./pkgs/pycat { };
        qbcl = pkgs.callPackage ./pkgs/qbcl { };
        raelives = pkgs.callPackage ./pkgs/raelives { };
        rapidbrogue = pkgs.callPackage ./pkgs/rapidbrogue { };
        rbw-vaultwarden = pkgs.callPackage ./pkgs/rbw-vaultwarden { };
        react-blessed = pkgs.callPackage ./pkgs/react-blessed { };
        revengate = pkgs.callPackage ./pkgs/revengate { };
        rot-js = pkgs.callPackage ./pkgs/rot-js { };
        rouge = pkgs.callPackage ./pkgs/rouge { };
        ruby-memoist = pkgs.callPackage ./pkgs/ruby-memoist { };
        ruby-sax-machine = pkgs.callPackage ./pkgs/ruby-sax-machine { };
        rust-computus = pkgs.callPackage ./pkgs/rust-computus { };
        rust-effects = pkgs.callPackage ./pkgs/rust-effects { };
        savescummer = pkgs.callPackage ./pkgs/savescummer { };
        scala-ts = pkgs.callPackage ./pkgs/scala-ts { };
        secretpathway = pkgs.callPackage ./pkgs/secretpathway { };
        sbcl-cl-libheif = pkgs.callPackage ./pkgs/sbcl-cl-libheif { };
        sbcl-cl-libtiff = pkgs.callPackage ./pkgs/sbcl-cl-libtiff { };
        sbcl-common-lisp-jupyter-imago = pkgs.callPackage ./pkgs/sbcl-common-lisp-jupyter-imago { };
        sbcl-imago = pkgs.callPackage ./pkgs/sbcl-imago { inherit (localPackages pkgs) sbcl-cl-libheif sbcl-cl-libtiff sbcl-common-lisp-jupyter-imago; };
        sbcl-mcclim = pkgs.callPackage ./pkgs/sbcl-mcclim { };
        sbcl-rplaca = pkgs.callPackage ./pkgs/sbcl-rplaca { inherit (localPackages pkgs) sbcl-mcclim; };
        sewer-massacre = pkgs.callPackage ./pkgs/sewer-massacre { };
        shadow-over-darkmoor = pkgs.callPackage ./pkgs/shadow-over-darkmoor { };
        shamogu = pkgs.callPackage ./pkgs/shamogu { };
        six-two-one = pkgs.callPackage ./pkgs/six-two-one { };
        slashem = pkgs.callPackage ./pkgs/slashem { };
        soundthread = pkgs.callPackage ./pkgs/soundthread { };
        splicehack-rewrite = pkgs.callPackage ./pkgs/splicehack-rewrite { };
        sporkhack = pkgs.callPackage ./pkgs/sporkhack { };
        srogue = pkgs.callPackage ./pkgs/srogue { };
        stoat-soup = pkgs.callPackage ./pkgs/stoat-soup { };
        talmudifier = pkgs.callPackage ./pkgs/talmudifier { };
        tapeutils = pkgs.callPackage ./pkgs/tapeutils { };
        tassh = pkgs.callPackage ./pkgs/tassh { };
        terminaldrome = pkgs.callPackage ./pkgs/terminaldrome { };
        tetraworld = pkgs.callPackage ./pkgs/tetraworld { };
        the-smiths-hand = pkgs.callPackage ./pkgs/the-smiths-hand { };
        trebuchet = pkgs.callPackage ./pkgs/trebuchet { };
        trial-by-combat = pkgs.callPackage ./pkgs/trial-by-combat { };
        tui = pkgs.callPackage ./pkgs/tui { };
        uc-explorer = pkgs.callPackage ./pkgs/uc-explorer { };
        donk-messages-image = pkgs.callPackage ./pkgs/donk-messages-image { };
        vt05 = pkgs.callPackage ./pkgs/vt05 { };
        wanderers = pkgs.callPackage ./pkgs/wanderers { };
        wrogue = pkgs.callPackage ./pkgs/wrogue { };
        xnethack = pkgs.callPackage ./pkgs/xnethack { };
        you-can-datamosh-on-linux = pkgs.callPackage ./pkgs/you-can-datamosh-on-linux { };
      };
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # CurseForge is the channel's only unfree package. Permit that one
          # name here; the overlay leaves the decision to the consumer.
          curseforgePkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "curseforge";
          };
        in packageSet system // localPackages pkgs // {
          inherit (localPackages curseforgePkgs) curseforge;
          gitleaks = pkgs.gitleaks;
        });

      # Re-export upstream derivations rather than rebuilding against a
      # potentially incompatible consumer package set.
      overlays.default = final: _prev:
        packageSet final.stdenv.hostPlatform.system // localPackages final;

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in {
            inherit (self.packages.${system}) acehack affect agduria aiwnios aiwnios-bytecode amstelvar apout aquarium-arena aquesttoofar atarist-font atlas-warriors atrogue autolith avanor axmud azurra-gtk-theme bcrawl bell-labs-rogue7 bell-museum blincolnlights bloatcrawl2 gnollcrawl gooncrawl gnollhack bootrogue brogue-lite cadr-fonts-latin cadr-fonts-symbols calcrogue cavechop city-of-the-condemned clojure-roguelike computer-builder corerl cotd cracks-and-crevices crashrun cryptrover curseforge dec-fonts dhack diabaig dicom2mesh dnethack dorxng-mcp dynahack dragonslayer drl dungeon-monkey-unlimited dungeonminder durthang dwarftown emacs-chatgpt-el emacs-cl emacs-emigo emacs-org-popup-posframe emacs-pbui emacs-treesit-sexp encircled escape-from-lab-42 everything-is-fodder evilhack exalt faangband farmingrl fiqhack flaghack font-exppd-unicode for-roguelike freelarn frostbite
            gearhead gearhead2 geminum-orbis gened genera-fonts-latin genera-fonts-symbols go-mud god-of-change godisc goblins-lot grippy-socks gruesome grunthack hack hackem hellcrawl hunger-games hydra-slayer image-tape infection interlisp-medley itstar ivory-key kbredir kbtin kildclient kimchi kitty-bitmap klh10 kmuddy ks10-udis lbforth letter-hunt liveonce liquid lispy-rogue ludviglundgren-qbittorrent-cli lyntin manna-cadet martins-dungeon-bash meta-typing mmapper modus mushkin mushtato narwharl nitrohack nlarn node-unrs-resolver notion-river nrl-text-to-phoneme obumbrata ocaml-irc-client ocaml-irc-client-unix ocaml-irc-client-lwt ocaml-irc-client-lwt-ssl oh-my-opencode-slim-companion pdp10-gcc pdp10-its-disassembler pdp10-suppty pdp10-xpl-pdp-10 pdp11 pdp6 persephil plomrogue potato proiel pycat qbcl raelives rapidbrogue react-blessed revengate rot-js rouge ruby-memoist ruby-sax-machine rust-computus rust-effects savescummer scala-ts secretpathway sbcl-cl-libheif sbcl-cl-libtiff sbcl-common-lisp-jupyter-imago sbcl-imago sbcl-mcclim sbcl-rplaca sewer-massacre shadow-over-darkmoor shamogu six-two-one slashem soundthread splicehack-rewrite sporkhack srogue stoat-soup
            talmudifier tapeutils tassh terminaldrome tetraworld the-smiths-hand trebuchet trial-by-combat tui uc-explorer donk-messages-image vt05 wanderers wrogue xnethack you-can-datamosh-on-linux buzz-desktop openclaw-desktop rbw-vaultwarden m3shapes eca mudpuppy;
          overlay = assert pkgs.autolith.drvPath == self.packages.${system}.autolith.drvPath;
            pkgs.runCommand "channel-overlay-check" {} "touch $out";
          secrets = pkgs.runCommand "channel-secret-scan" {
            nativeBuildInputs = [ pkgs.gitleaks ];
          } ''
            gitleaks dir --redact --no-banner --ignore-gitleaks-allow \
              --config ${./.gitleaks.toml} ${./.}
            touch $out
          '';
        });
    };
}
