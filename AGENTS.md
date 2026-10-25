# Package channel work

- Re-read current files and Git status before editing; preserve unrelated work.
- When a needed package is unavailable in Nixpkgs, build and maintain its Nix
  package in this channel. Keep reusable packaging out of the NixOS configuration
  repository and consume channel outputs there.
- Put channel-maintained package definitions in `pkgs/<name>/default.nix` and
  expose them through `packages` and the default overlay in `flake.nix`.
  When upstream already provides suitable Nix packaging, re-export its package
  through a pinned flake input rather than duplicating the definition.
- Keep application source in its upstream repository; do not vendor it here.
  Preserve independent upstream Nixpkgs pins when runtime compatibility needs them.
- Never put secrets or private keys in source or print their values.
- Install the staged-secret hook with `scripts/setup-git-hooks`; never bypass it.
  Run `scripts/check-secrets` before builds or commits when adding content.
- For package changes, run `nix flake check path:.` and build the affected package
  on supported platforms. Add platforms only after validating them.
- Sign every new commit with the agent key using:
  `git -c user.email=htayj@users.noreply.github.com -c gpg.format=openpgp -c gpg.program=/home/taylor/.local/share/agent-signing/gpg -c user.signingkey=D0BEDCD5B63A4040FBC5BC00A6398F53FCEC1C10 commit -S`.
  Keep the wrapper and keyring outside this repository. Never fall back to an
  unsigned commit; verify the resulting signature.
