{
  description = "Taylor's package channel";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # Keep Autolith's independent pin: SBCL and its Lisp package set must match.
  inputs.autolith.url = "github:htayj/autolith";

  outputs = { self, nixpkgs, autolith, ... }:
    let
      # Start with the platform validated by this channel.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageSet = system: {
        autolith = autolith.packages.${system}.default;
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
        cadr-fonts-latin = pkgs.callPackage ./pkgs/cadr-fonts { group = "latin"; };
        cadr-fonts-symbols = pkgs.callPackage ./pkgs/cadr-fonts { group = "symbols"; };
        corerl = pkgs.callPackage ./pkgs/corerl { };
        cryptrover = pkgs.callPackage ./pkgs/cryptrover { };
        dhack = pkgs.callPackage ./pkgs/dhack { };
        diabaig = pkgs.callPackage ./pkgs/diabaig { };
        freelarn = pkgs.callPackage ./pkgs/freelarn { };
        genera-fonts-latin = pkgs.callPackage ./pkgs/genera-fonts { group = "latin"; };
        genera-fonts-symbols = pkgs.callPackage ./pkgs/genera-fonts { group = "symbols"; };
        hunger-games = pkgs.callPackage ./pkgs/hunger-games { };
        itstar = pkgs.callPackage ./pkgs/itstar { };
        kbredir = pkgs.callPackage ./pkgs/kbredir { };
        ks10-udis = pkgs.callPackage ./pkgs/ks10-udis { };
        martins-dungeon-bash = pkgs.callPackage ./pkgs/martins-dungeon-bash { };
        narwharl = pkgs.callPackage ./pkgs/narwharl { };
        nrl-text-to-phoneme = pkgs.callPackage ./pkgs/nrl-text-to-phoneme { };
        obumbrata = pkgs.callPackage ./pkgs/obumbrata { };
        pdp10-its-disassembler = pkgs.callPackage ./pkgs/pdp10-its-disassembler { };
        pdp11 = pkgs.callPackage ./pkgs/pdp11 { };
        pdp6 = pkgs.callPackage ./pkgs/pdp6 { };
        plomrogue = pkgs.callPackage ./pkgs/plomrogue { };
        pycat = pkgs.callPackage ./pkgs/pycat { };
        shamogu = pkgs.callPackage ./pkgs/shamogu { };
        tapeutils = pkgs.callPackage ./pkgs/tapeutils { };
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
          inherit (self.packages.${system}) agduria apout aquesttoofar atarist-font atrogue autolith avanor azurra-gtk-theme blincolnlights bootrogue cadr-fonts-latin cadr-fonts-symbols corerl cryptrover dhack diabaig freelarn
            genera-fonts-latin genera-fonts-symbols hunger-games itstar kbredir ks10-udis martins-dungeon-bash narwharl nrl-text-to-phoneme obumbrata pdp10-its-disassembler pdp11 pdp6 plomrogue pycat shamogu
            tapeutils vt05 wrogue;
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
