{
  lib,
  kitty,
}:

# Kitty with native bitmap-font support and XKB Meta encoded as terminal Alt.
# Ported from the tay Guix channel (tay packages kitty-bitmap).  The patches
# are the Guix channel's kitty-bitmap patches and apply unchanged to the
# nixpkgs Kitty source; everything else follows the nixpkgs kitty recipe,
# including its checkPhase, which runs the patched kitty_tests/keys.py.
kitty.overrideAttrs (old: {
  pname = "kitty-bitmap";

  patches = (old.patches or [ ]) ++ [
    # Allow non-scalable bitmap fonts by default (from the AUR kitty-bitmap
    # package recipe).
    ./kitty-bitmap-fonts.patch
    # Treat FC_CHARCELL bitmap faces such as Unscii PCF as monospace.
    ./kitty-bitmap-charcell-fonts.patch
    # Use the selected strike's metrics for bitmap faces.
    ./kitty-bitmap-raster-metrics.patch
    # Encode XKB Meta as conventional Alt for the child process only.
    ./kitty-bitmap-meta-as-alt.patch
  ];

  meta = old.meta // {
    description = "GPU-based terminal emulator with native bitmap-font support";
    longDescription = ''
      This Kitty variant changes Kitty's Fontconfig defaults so native
      non-scalable bitmap fonts, including PCF and BDF faces, may be selected
      for the primary terminal font.  Bitmap strikes are fixed-size, so they do
      not zoom or scale cleanly; use an available native font size and, where
      needed, explicit line-height settings.

      For an XKB layout where Meta and Alt are distinct, Meta stays available
      to Kitty shortcut matching but is encoded as conventional Alt for the
      child process, giving legacy terminal applications ESC-prefixed Meta
      chords in both the legacy and extended keyboard protocols.
    '';
    license = lib.licenses.gpl3Plus;
  };
})
