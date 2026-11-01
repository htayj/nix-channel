{ rbw, fetchzip }:
rbw.overrideAttrs (old: {
  version = "1.15.0-vaultwarden.1";
  src = fetchzip {
    url = "https://git.tozt.net/rbw/snapshot/rbw-1.15.0.tar.gz";
    hash = "sha256-N/s1flB+s2HwEeLsf7YlJG+5TJgP8Wu7PHNPWmVfpIo=";
  };
  # Upstream PR #386, commit d65cba5c0353e477b46b0faba7d1598d602259db.
  # Preserve the existing database and authentication format.
  patches = (old.patches or [ ]) ++ [ ./encrypted-for.patch ];
  # Version-only metadata changes after the unchanged vendor lock is checked.
  preBuild = (old.preBuild or "") + ''
    substituteInPlace Cargo.toml --replace-fail \
      'version = "1.15.0"' 'version = "1.15.0+vaultwarden.1"'
    substituteInPlace Cargo.lock --replace-fail \
      'name = "rbw"
    version = "1.15.0"' 'name = "rbw"
    version = "1.15.0+vaultwarden.1"'
  '';
})
