# B00merang Azurra GTK 3 theme, built from the Azurra_framework collection.
{ lib, stdenvNoCC, fetchFromGitHub, sassc }:

stdenvNoCC.mkDerivation {
  pname = "azurra-gtk-theme";
  version = "4.2.7";

  src = fetchFromGitHub {
    owner = "B00merang-Project";
    repo = "Azurra_framework";
    rev = "80f34032dbdbb8d9b1a61e61b88d6b669e46a34a";
    hash = "sha256-ZReOjpYbb9fV2W5WraaryMHWvKqA4jiZzi6kqXk7QG4=";
  };

  nativeBuildInputs = [ sassc ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    sassc Azurra/gtk.scss Azurra/gtk.css
    sassc Azurra/gtk-dark.scss Azurra/gtk-dark.css
    runHook postBuild
  '';

  # The stylesheets also reference backdrop variants of the selected
  # check and radio icons, which the repository omits.  They are identical
  # to the selected icons, so link them instead of running the SVG renderer.
  installPhase = ''
    runHook preInstall
    theme=$out/share/themes/Azurra
    install -Dm644 -t $theme Azurra/gtk.css Azurra/gtk-dark.css Azurra/theme.conf
    cp -r Azurra/assets Azurra/assets-dark $theme/
    for dir in $theme/assets $theme/assets-dark; do
      for kind in checkbox radio; do
        for state in unchecked checked mixed; do
          for variant in "" -insensitive; do
            base=$kind-$state$variant
            for suffix in .png @2.png; do
              test -e $dir/$base-selected$suffix
              ln -s $base-selected$suffix $dir/$base-unfocused-selected$suffix
            done
          done
        done
      done
    done
    install -Dm644 -t $out/share/doc/azurra-gtk-theme LICENSE README.md
    runHook postInstall
  '';

  meta = {
    description = "Azurra theme for GTK 3 applications";
    longDescription = ''
      Azurra GTK Theme provides the Azurra GTK 3 stylesheet and its committed
      light and dark image assets.  This package installs only the finished
      theme from the B00merang Azurra framework.
    '';
    homepage = "https://github.com/B00merang-Project/Azurra_framework";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.all;
  };
}
