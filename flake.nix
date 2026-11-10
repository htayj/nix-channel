{
  description = "Taylor's package channel";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # Keep Autolith's independent pin: SBCL and its Lisp package set must match.
  inputs.autolith.url = "github:htayj/autolith";
  # Upstream ships its own packaging; build it against the channel's nixpkgs so
  # the QML module matches consumers' Qt.
  inputs.m3shapes.url = "github:soramanew/m3shapes/32ad9ce328bb77ed349b40a3be10ee9ea610b8ab";
  inputs.m3shapes.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, autolith, m3shapes, ... }:
    let
      # Start with the platform validated by this channel.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageSet = system: {
        autolith = autolith.packages.${system}.default;
        m3shapes = m3shapes.packages.${system}.m3shapes;
      };
      # Channel-maintained definitions, built against the consumer's package set.
      localPackages = pkgs: {
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
        bell-museum = pkgs.callPackage ./pkgs/bell-museum { };
        blincolnlights = pkgs.callPackage ./pkgs/blincolnlights { };
        bootrogue = pkgs.callPackage ./pkgs/bootrogue { };
        brogue-lite = pkgs.callPackage ./pkgs/brogue-lite { };
        buzz-desktop = pkgs.callPackage ./pkgs/buzz-desktop { };
        cadr-fonts-latin = pkgs.callPackage ./pkgs/cadr-fonts { group = "latin"; };
        cadr-fonts-symbols = pkgs.callPackage ./pkgs/cadr-fonts { group = "symbols"; };
        cavechop = pkgs.callPackage ./pkgs/cavechop { };
        city-of-the-condemned = pkgs.callPackage ./pkgs/city-of-the-condemned { };
        clojure-roguelike = pkgs.callPackage ./pkgs/clojure-roguelike { };
        crashrun = pkgs.callPackage ./pkgs/crashrun { };
        corerl = pkgs.callPackage ./pkgs/corerl { };
        cotd = pkgs.callPackage ./pkgs/cotd { };
        cryptrover = pkgs.callPackage ./pkgs/cryptrover { };
        dec-fonts = pkgs.callPackage ./pkgs/dec-fonts { };
        dhack = pkgs.callPackage ./pkgs/dhack { };
        diabaig = pkgs.callPackage ./pkgs/diabaig { };
        dicom2mesh = pkgs.callPackage ./pkgs/dicom2mesh { };
        dnethack = pkgs.callPackage ./pkgs/dnethack { };
        dynahack = pkgs.callPackage ./pkgs/dynahack { };
        dragonslayer = pkgs.callPackage ./pkgs/dragonslayer { };
        dungeon-monkey-unlimited = pkgs.callPackage ./pkgs/dungeon-monkey-unlimited { };
        durthang = pkgs.callPackage ./pkgs/durthang { };
        dwarftown = pkgs.callPackage ./pkgs/dwarftown { };
        emacs-chatgpt-el = pkgs.callPackage ./pkgs/emacs-chatgpt-el { };
        emacs-org-popup-posframe = pkgs.callPackage ./pkgs/emacs-org-popup-posframe { };
        emacs-pbui = pkgs.callPackage ./pkgs/emacs-pbui { };
        emacs-treesit-sexp = pkgs.callPackage ./pkgs/emacs-treesit-sexp { };
        encircled = pkgs.callPackage ./pkgs/encircled { };
        escape-from-lab-42 = pkgs.callPackage ./pkgs/escape-from-lab-42 { };
        everything-is-fodder = pkgs.callPackage ./pkgs/everything-is-fodder { };
        faangband = pkgs.callPackage ./pkgs/faangband { };
        farmingrl = pkgs.callPackage ./pkgs/farmingrl { };
        ffglitch = pkgs.callPackage ./pkgs/ffglitch { };
        fiqhack = pkgs.callPackage ./pkgs/fiqhack { };
        freelarn = pkgs.callPackage ./pkgs/freelarn { };
        genera-fonts-latin = pkgs.callPackage ./pkgs/genera-fonts { group = "latin"; };
        genera-fonts-symbols = pkgs.callPackage ./pkgs/genera-fonts { group = "symbols"; };
        godisc = pkgs.callPackage ./pkgs/godisc { };
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
        itstar = pkgs.callPackage ./pkgs/itstar { };
        kbredir = pkgs.callPackage ./pkgs/kbredir { };
        kbtin = pkgs.callPackage ./pkgs/kbtin { };
        kildclient = pkgs.callPackage ./pkgs/kildclient { };
        kmuddy = pkgs.callPackage ./pkgs/kmuddy { };
        ks10-udis = pkgs.callPackage ./pkgs/ks10-udis { };
        lbforth = pkgs.callPackage ./pkgs/lbforth { };
        liveonce = pkgs.callPackage ./pkgs/liveonce { };
        ludviglundgren-qbittorrent-cli = pkgs.callPackage ./pkgs/ludviglundgren-qbittorrent-cli { };
        lyntin = pkgs.callPackage ./pkgs/lyntin { };
        manna-cadet = pkgs.callPackage ./pkgs/manna-cadet { };
        martins-dungeon-bash = pkgs.callPackage ./pkgs/martins-dungeon-bash { };
        mmapper = pkgs.callPackage ./pkgs/mmapper { };
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
        openclaw-desktop = pkgs.callPackage ./pkgs/openclaw-desktop { };
        pdp10-gcc = pkgs.callPackage ./pkgs/pdp10-gcc { };
        pdp10-its-disassembler = pkgs.callPackage ./pkgs/pdp10-its-disassembler { };
        pdp10-suppty = pkgs.callPackage ./pkgs/pdp10-suppty { };
        pdp10-xpl-pdp-10 = pkgs.callPackage ./pkgs/pdp10-xpl-pdp-10 { };
        pdp11 = pkgs.callPackage ./pkgs/pdp11 { };
        pdp6 = pkgs.callPackage ./pkgs/pdp6 { };
        plomrogue = pkgs.callPackage ./pkgs/plomrogue { };
        potato = pkgs.callPackage ./pkgs/potato { };
        pycat = pkgs.callPackage ./pkgs/pycat { };
        raelives = pkgs.callPackage ./pkgs/raelives { };
        rapidbrogue = pkgs.callPackage ./pkgs/rapidbrogue { };
        rbw-vaultwarden = pkgs.callPackage ./pkgs/rbw-vaultwarden { };
        rouge = pkgs.callPackage ./pkgs/rouge { };
        ruby-memoist = pkgs.callPackage ./pkgs/ruby-memoist { };
        savescummer = pkgs.callPackage ./pkgs/savescummer { };
        secretpathway = pkgs.callPackage ./pkgs/secretpathway { };
        sbcl-cl-libheif = pkgs.callPackage ./pkgs/sbcl-cl-libheif { };
        sbcl-cl-libtiff = pkgs.callPackage ./pkgs/sbcl-cl-libtiff { };
        sewer-massacre = pkgs.callPackage ./pkgs/sewer-massacre { };
        shadow-over-darkmoor = pkgs.callPackage ./pkgs/shadow-over-darkmoor { };
        shamogu = pkgs.callPackage ./pkgs/shamogu { };
        six-two-one = pkgs.callPackage ./pkgs/six-two-one { };
        slashem = pkgs.callPackage ./pkgs/slashem { };
        srogue = pkgs.callPackage ./pkgs/srogue { };
        tapeutils = pkgs.callPackage ./pkgs/tapeutils { };
        tassh = pkgs.callPackage ./pkgs/tassh { };
        terminaldrome = pkgs.callPackage ./pkgs/terminaldrome { };
        tetraworld = pkgs.callPackage ./pkgs/tetraworld { };
        the-smiths-hand = pkgs.callPackage ./pkgs/the-smiths-hand { };
        trebuchet = pkgs.callPackage ./pkgs/trebuchet { };
        tui = pkgs.callPackage ./pkgs/tui { };
        uc-explorer = pkgs.callPackage ./pkgs/uc-explorer { };
        donk-messages-image = pkgs.callPackage ./pkgs/donk-messages-image { };
        vt05 = pkgs.callPackage ./pkgs/vt05 { };
        wrogue = pkgs.callPackage ./pkgs/wrogue { };
        xnethack = pkgs.callPackage ./pkgs/xnethack { };
        you-can-datamosh-on-linux = pkgs.callPackage ./pkgs/you-can-datamosh-on-linux { };
      };
    in {
      packages = forAllSystems (system: packageSet system
        // localPackages nixpkgs.legacyPackages.${system} // {
          gitleaks = nixpkgs.legacyPackages.${system}.gitleaks;
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
            inherit (self.packages.${system}) agduria aiwnios aiwnios-bytecode amstelvar apout aquarium-arena aquesttoofar atarist-font atlas-warriors atrogue autolith avanor axmud azurra-gtk-theme bcrawl bell-museum blincolnlights bootrogue brogue-lite cadr-fonts-latin cadr-fonts-symbols cavechop city-of-the-condemned clojure-roguelike corerl cotd crashrun cryptrover dec-fonts dhack diabaig dicom2mesh dnethack dynahack dragonslayer dungeon-monkey-unlimited durthang dwarftown emacs-chatgpt-el emacs-org-popup-posframe emacs-pbui emacs-treesit-sexp encircled escape-from-lab-42 everything-is-fodder faangband farmingrl fiqhack freelarn
            genera-fonts-latin genera-fonts-symbols god-of-change godisc grippy-socks gruesome grunthack hack hackem hellcrawl hunger-games hydra-slayer itstar kbredir kbtin kildclient kmuddy ks10-udis lbforth liveonce ludviglundgren-qbittorrent-cli lyntin manna-cadet martins-dungeon-bash mmapper mushtato narwharl nitrohack nlarn node-unrs-resolver notion-river nrl-text-to-phoneme obumbrata ocaml-irc-client ocaml-irc-client-unix ocaml-irc-client-lwt ocaml-irc-client-lwt-ssl pdp10-gcc pdp10-its-disassembler pdp10-suppty pdp10-xpl-pdp-10 pdp11 pdp6 plomrogue potato pycat raelives rapidbrogue rouge ruby-memoist savescummer secretpathway sbcl-cl-libheif sbcl-cl-libtiff sewer-massacre shadow-over-darkmoor shamogu six-two-one slashem srogue
            tapeutils tassh terminaldrome tetraworld the-smiths-hand trebuchet tui uc-explorer donk-messages-image vt05 wrogue xnethack you-can-datamosh-on-linux buzz-desktop openclaw-desktop rbw-vaultwarden m3shapes;
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
