# FarmingRL: unchanged browser game opened in a pinned Ungoogled Chromium
# application window.
{ lib, stdenvNoCC, fetchFromGitHub, runtimeShell, coreutils
, ungoogled-chromium, dejavu_fonts, makeFontsConf }:

let
  # The game's default monospace face is available without host font
  # discovery.
  fontsConf = makeFontsConf { fontDirectories = [ dejavu_fonts ]; };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "farmingrl";
  # The archived upstream repository has no tagged releases.
  version = "0-unstable-5f4e722";

  src = fetchFromGitHub {
    owner = "horaguchi";
    repo = "FarmingRL";
    rev = "5f4e722644d1fe266aae4a015cc366e7e1dec6f4";
    hash = "sha256-YUwv92JcqrTpRzNOolEiJpqwa9CofXzvL+7FiRezdJo=";
  };

  dontConfigure = true;
  dontBuild = true;

  # All five upstream files are installed without rewriting them.  The
  # launcher keeps the browser profile, configuration and cache below the
  # XDG base directories, falling back to absolute HOME locations.
  installPhase = ''
    runHook preInstall

    install -Dm644 -t $out/share/farmingrl index.html game.js rot.js
    install -Dm644 -t $out/share/doc/farmingrl LICENSE README.md

    mkdir -p $out/bin
    cat > $out/bin/farmingrl <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    case "\''${XDG_DATA_HOME:-}" in
      /*) data=\$XDG_DATA_HOME/farmingrl ;;
      *) data=\''${HOME:?HOME must be set}/.local/share/farmingrl ;;
    esac
    case "\''${XDG_CONFIG_HOME:-}" in
      /*) config=\$XDG_CONFIG_HOME/farmingrl ;;
      *) config=\''${HOME:?HOME must be set}/.config/farmingrl ;;
    esac
    case "\''${XDG_CACHE_HOME:-}" in
      /*) cache=\$XDG_CACHE_HOME/farmingrl ;;
      *) cache=\''${HOME:?HOME must be set}/.cache/farmingrl ;;
    esac
    case \$data:\$config:\$cache in
      /*:/*:/*) ;;
      *) echo 'farmingrl: HOME fallback must be absolute' >&2; exit 1 ;;
    esac
    export XDG_DATA_HOME="\$data" XDG_CONFIG_HOME="\$config"
    export XDG_CACHE_HOME="\$cache"
    ${coreutils}/bin/mkdir -p -- "\$data/chromium" "\$config" "\$cache/chromium"
    export FONTCONFIG_FILE=${fontsConf}
    exec ${lib.getExe ungoogled-chromium} --user-data-dir="\$data/chromium" \\
      --disk-cache-dir="\$cache/chromium" \\
      --app="file://$out/share/farmingrl/index.html" "\$@"
    EOF
    chmod 555 $out/bin/farmingrl

    runHook postInstall
  '';

  meta = {
    description = "Browser roguelike with farming and automatic combat";
    longDescription = ''
      FarmingRL is a browser roguelike in which movement, farming and
      repeated battles develop the player character.  This package installs
      the unchanged upstream HTML, JavaScript and bundled rot.js, and opens
      the local game in a dedicated Ungoogled Chromium application window.
      No server or runtime downloads are needed.  The browser profile
      resides below $XDG_DATA_HOME/farmingrl, with configuration and cache
      below $XDG_CONFIG_HOME/farmingrl and $XDG_CACHE_HOME/farmingrl; unset
      or relative XDG directories use the standard absolute HOME fallbacks.
      Additional command-line options are passed to the browser.
    '';
    homepage = "https://github.com/horaguchi/FarmingRL";
    # LICENSE includes Koji Horaguchi's Expat notice and the three-clause
    # BSD notice for Ondrej Zara's bundled rot.js.
    license = with lib.licenses; [ mit bsd3 ];
    mainProgram = "farmingrl";
    platforms = ungoogled-chromium.meta.platforms;
  };
})
