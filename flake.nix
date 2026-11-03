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
        apout = pkgs.callPackage ./pkgs/apout { };
        aquesttoofar = pkgs.callPackage ./pkgs/aquesttoofar { };
        atarist-font = pkgs.callPackage ./pkgs/atarist-font { };
        atrogue = pkgs.callPackage ./pkgs/atrogue { };
        avanor = pkgs.callPackage ./pkgs/avanor { };
        azurra-gtk-theme = pkgs.callPackage ./pkgs/azurra-gtk-theme { };
        blincolnlights = pkgs.callPackage ./pkgs/blincolnlights { };
        bootrogue = pkgs.callPackage ./pkgs/bootrogue { };
        brogue-lite = pkgs.callPackage ./pkgs/brogue-lite { };
        buzz-desktop = pkgs.callPackage ./pkgs/buzz-desktop { };
        cadr-fonts-latin = pkgs.callPackage ./pkgs/cadr-fonts { group = "latin"; };
        cadr-fonts-symbols = pkgs.callPackage ./pkgs/cadr-fonts { group = "symbols"; };
        corerl = pkgs.callPackage ./pkgs/corerl { };
        cryptrover = pkgs.callPackage ./pkgs/cryptrover { };
        dec-fonts = pkgs.callPackage ./pkgs/dec-fonts { };
        dhack = pkgs.callPackage ./pkgs/dhack { };
        diabaig = pkgs.callPackage ./pkgs/diabaig { };
        dicom2mesh = pkgs.callPackage ./pkgs/dicom2mesh { };
        freelarn = pkgs.callPackage ./pkgs/freelarn { };
        genera-fonts-latin = pkgs.callPackage ./pkgs/genera-fonts { group = "latin"; };
        genera-fonts-symbols = pkgs.callPackage ./pkgs/genera-fonts { group = "symbols"; };
        grippy-socks = pkgs.callPackage ./pkgs/grippy-socks { };
        hack = pkgs.callPackage ./pkgs/hack { };
        hunger-games = pkgs.callPackage ./pkgs/hunger-games { };
        itstar = pkgs.callPackage ./pkgs/itstar { };
        kbredir = pkgs.callPackage ./pkgs/kbredir { };
        kbtin = pkgs.callPackage ./pkgs/kbtin { };
        kmuddy = pkgs.callPackage ./pkgs/kmuddy { };
        ks10-udis = pkgs.callPackage ./pkgs/ks10-udis { };
        lyntin = pkgs.callPackage ./pkgs/lyntin { };
        martins-dungeon-bash = pkgs.callPackage ./pkgs/martins-dungeon-bash { };
        mmapper = pkgs.callPackage ./pkgs/mmapper { };
        mushtato = pkgs.callPackage ./pkgs/mushtato { };
        narwharl = pkgs.callPackage ./pkgs/narwharl { };
        nlarn = pkgs.callPackage ./pkgs/nlarn { };
        nrl-text-to-phoneme = pkgs.callPackage ./pkgs/nrl-text-to-phoneme { };
        obumbrata = pkgs.callPackage ./pkgs/obumbrata { };
        pdp10-its-disassembler = pkgs.callPackage ./pkgs/pdp10-its-disassembler { };
        pdp10-xpl-pdp-10 = pkgs.callPackage ./pkgs/pdp10-xpl-pdp-10 { };
        pdp11 = pkgs.callPackage ./pkgs/pdp11 { };
        pdp6 = pkgs.callPackage ./pkgs/pdp6 { };
        plomrogue = pkgs.callPackage ./pkgs/plomrogue { };
        potato = pkgs.callPackage ./pkgs/potato { };
        pycat = pkgs.callPackage ./pkgs/pycat { };
        rapidbrogue = pkgs.callPackage ./pkgs/rapidbrogue { };
        rbw-vaultwarden = pkgs.callPackage ./pkgs/rbw-vaultwarden { };
        shamogu = pkgs.callPackage ./pkgs/shamogu { };
        tapeutils = pkgs.callPackage ./pkgs/tapeutils { };
        donk-messages-image = pkgs.callPackage ./pkgs/donk-messages-image { };
        vt05 = pkgs.callPackage ./pkgs/vt05 { };
        wrogue = pkgs.callPackage ./pkgs/wrogue { };
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
          inherit (self.packages.${system}) agduria apout aquesttoofar atarist-font atrogue autolith avanor azurra-gtk-theme blincolnlights bootrogue brogue-lite cadr-fonts-latin cadr-fonts-symbols corerl cryptrover dec-fonts dhack diabaig dicom2mesh freelarn
            genera-fonts-latin genera-fonts-symbols grippy-socks hack hunger-games itstar kbredir kbtin kmuddy ks10-udis lyntin martins-dungeon-bash mmapper mushtato narwharl nlarn nrl-text-to-phoneme obumbrata pdp10-its-disassembler pdp10-xpl-pdp-10 pdp11 pdp6 plomrogue potato pycat rapidbrogue shamogu
            tapeutils donk-messages-image vt05 wrogue buzz-desktop rbw-vaultwarden m3shapes;
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
