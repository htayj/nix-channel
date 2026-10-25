# nix-channel

Taylor's flake-based package channel. This is a Git repository consumed through
flake inputs; it does not publish legacy `nix-channel` archives.

Currently validated on `x86_64-linux`.

## Remotes and mirror

- Primary (`origin`): https://forge.nogroup.group/tay/nix-channel (private).
- GitHub mirror (`github`): https://github.com/htayj/nix-channel (private).

Push to Forgejo with `git push`; `main` tracks `origin/main`. Forgejo mirrors
on every push, with an eight-hour periodic sync as a fallback. Make changes on
Forgejo; issues, pull requests, and settings are not mirrored. The mirror uses
a Forgejo-generated SSH key with write access only to the GitHub repository.
Credentials remain outside this repository.


## Packages

- `autolith`: upstream Autolith, preserving its own Nixpkgs/SBCL pin.
- `gitleaks`: maintenance tool used by the secret-scanning hook.

## Try locally

```sh
nix build path:/home/taylor/projects/nix-channel#autolith
nix shell path:/home/taylor/projects/nix-channel#autolith
```

## Consume from another flake

Add an input (Git access to the private repository is required):

```nix
inputs.taylor-packages.url = "git+https://forge.nogroup.group/tay/nix-channel.git";
inputs.taylor-packages.inputs.nixpkgs.follows = "nixpkgs";
```

Include `taylor-packages` in your outputs arguments, then use
`taylor-packages.packages.${system}.autolith` in `home.packages` or
`environment.systemPackages`. For local development, use
`path:/home/taylor/projects/nix-channel` instead.

Alternatively, apply `taylor-packages.overlays.default` to your Nixpkgs import
(or NixOS `nixpkgs.overlays`) and use `pkgs.autolith`. For standalone Home Manager,
apply the overlay to the package set passed to `homeManagerConfiguration`.
The overlay exposes Autolith only; the scanner is a maintenance package.

The channel's Nixpkgs may follow the consumer's pin. Autolith's Nixpkgs must stay
independent because its SBCL and Lisp dependencies are coupled.

## Maintain

```sh
scripts/setup-git-hooks
scripts/check-secrets
nix flake check path:.
```

Update a source deliberately, inspect the lock diff, scan, and check:

```sh
nix flake update autolith
scripts/check-secrets
nix flake check path:.
```

Add external flake packages to `packageSet` in `flake.nix`; keep source in its
upstream repository. Packages maintained here can live in `pkgs/<name>/default.nix`
and be instantiated with `callPackage`. Export NixOS or Home Manager modules only
when a package needs service or user configuration. Add platforms only after
validating their builds. A binary cache can be added later.

Commit `flake.lock`. Never put credentials or private keys in Nix source.
The staged-secret hook must stay enabled; new commits must be signed with the
agent signing key configured outside this repository.
