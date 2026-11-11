#!/bin/sh
# Installed-runtime check for goblins-lot.
# Usage: smoke.sh OUT   (needs Xvfb, xdotool, xwd, ImageMagick and coreutils)
#
# GCMain runs Paths::Init (creates the config directory and opens
# goblin-camp.log there), Script::Init (embedded Python with the installed
# gcamp library), Data::LoadConfig (creates config.py), Data::LoadFont,
# Game::LoadingScreen(Mods::Load) and then MainMenu, whose 'q' entry exits.
# Config::Save runs at exit and rewrites config.py with every cvar.
set -eu
out=$1
launcher=$out/bin/goblins-lot
data=$out/share/games/goblins-lot
work=$(mktemp -d)
xpid=
trap '[ -z "$xpid" ] || kill "$xpid" 2>/dev/null || true; rm -rf "$work"' EXIT
fail() { echo "smoke: FAIL: $*" >&2; exit 1; }

mkdir "$work/cwd" "$work/home"
cd "$work/cwd"

# Relative and store config homes are rejected before the game starts.
for bad in relative/config "$out/config" /nix/store; do
  if HOME=$work/home XDG_CONFIG_HOME=$bad "$launcher" 2>"$work/err"; then
    fail "accepted XDG_CONFIG_HOME=$bad"
  fi
  grep -q 'goblins-lot: .*config directory' "$work/err" || fail "no message for $bad"
done
if env -u XDG_CONFIG_HOME HOME=relative "$launcher" 2>"$work/err"; then
  fail "accepted relative HOME"
fi
[ -z "$(ls -A "$work/cwd")$(ls -A "$work/home")" ] || fail "rejected launches wrote files"

Xvfb -displayfd 3 -nolisten tcp -screen 0 1920x1080x24 3>"$work/display" \
  >"$work/xvfb.log" 2>&1 &
xpid=$!
for _ in $(seq 100); do [ -s "$work/display" ] && break; sleep 0.1; done
[ -s "$work/display" ] || fail "Xvfb did not start"
export DISPLAY=:$(cat "$work/display")
export SDL_AUDIODRIVER=dummy
mkdir -m 700 "$work/run"
export XDG_RUNTIME_DIR=$work/run DBUS_SESSION_BUS_ADDRESS=unix:path=$work/run/no-bus

# game_window: print the mapped 640-pixel-or-wider goblins-lot window.  SDL
# also creates small, short-lived helper windows with the same class.
game_window() {
  for w in $(xdotool search --classname '^goblins-lot$' 2>/dev/null); do
    width=$(xdotool getwindowgeometry "$w" 2>/dev/null \
      | awk '/Geometry:/ { split($2, g, "x"); print g[1] }')
    [ -n "$width" ] && [ "$width" -ge 640 ] && { echo "$w"; return; }
  done
}

# play NAME STATE ENV...: start the game, wait for the main menu window,
# capture it, quit with the menu's 'q' shortcut and check STATE.
play() {
  name=$1 state=$2; shift 2
  env "$@" "$launcher" >"$work/$name.out" 2>&1 &
  pid=$!
  wid=
  for _ in $(seq 600); do
    wid=$(game_window) && [ -n "$wid" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  [ -n "$wid" ] || { cat "$work/$name.out" "$state/goblin-camp.log" >&2 || true; fail "$name: no game window"; }
  # Let the loading screen finish and the menu draw.
  sleep 5
  kill -0 "$pid" 2>/dev/null || { cat "$work/$name.out" "$state/goblin-camp.log" >&2 || true; fail "$name: game exited early"; }
  wid=$(game_window)
  [ -n "$wid" ] || fail "$name: game window disappeared"
  xwd -silent -id "$wid" >"$work/$name.xwd"
  colours=$(magick "xwd:$work/$name.xwd" -format '%k' info:)
  echo "smoke: $name: menu window has $colours colours"
  [ "$colours" -gt 2 ] || fail "$name: window is blank"
  for _ in $(seq 50); do
    kill -0 "$pid" 2>/dev/null || break
    xdotool windowfocus "$wid" key q 2>/dev/null || true
    sleep 0.2
  done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; fail "$name: 'q' did not quit"; fi
  status=0; wait "$pid" || status=$?
  cat "$work/$name.out"
  [ "$status" = 0 ] || fail "$name: exit status $status"

  log=$state/goblin-camp.log
  [ -f "$log" ] || fail "$name: no log in $state"
  cat "$log"
  [ "$(stat -c %a "$state")" = 700 ] || fail "$name: state mode $(stat -c %a "$state")"
  for want in \
    "Personal directory: \"$state" \
    "Global data directory: \"$data" \
    "Python 3.12" \
    "Goblins' Lot Python Library Path = $data/lib" \
    "Loading user config." \
    "Loading the font" \
    "CoreTilesets directory: \"$data/lib/tilesets_core" \
    "Trying to load mod 'gcamp_core' from $data/lib/gcamp_core" \
    "Core mod loaded"
  do
    grep -qF "$want" "$log" || fail "$name: log lacks: $want"
  done
  ! grep -qE 'Traceback|Cannot load|ERROR' "$log" || fail "$name: errors in log"
  [ -d "$data/lib/tilesets_core/default" ] && [ -d "$data/lib/tilesets_core/default_x2" ] \
    || fail "core tilesets not installed"
  grep -q "setCVar('renderer'" "$state/config.py" || fail "$name: config.py not saved"
  [ -f "$state/terminal.png" ] || fail "$name: font not copied"
  echo "smoke: $name: menu shown, state in $state"
}

play xdg "$work/xdg/goblins-lot" HOME="$work/home" XDG_CONFIG_HOME="$work/xdg"
play home "$work/home/.config/goblins-lot" -u XDG_CONFIG_HOME HOME="$work/home"

[ -z "$(ls -A "$work/cwd")" ] || fail "game wrote to the invoking directory"
echo "smoke: ok"
