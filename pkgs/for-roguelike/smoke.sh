#!/bin/sh
# Installed-runtime check for for-roguelike.
# Usage: smoke.sh OUT   (needs Xvfb, xdotool and coreutils on PATH)
#
# Game::Init always takes its loadDebug branch: it generates a 70x70
# Junktown, writes leveldump.txt, visdump.txt, edgedump.txt and pathdump.txt
# to the working directory, parses data/items.cfg (printing each structure),
# then Gui::Init parses data/tileset.cfg, loads font.png and opens the
# 100x60 "FOR" window.  Parser errors throw uncaught C strings and abort.
# Escape makes MainLoop return false and main return 0.
set -eu
out=$1
launcher=$out/bin/for-roguelike
work=$(mktemp -d)
xpid=
trap '[ -z "$xpid" ] || kill "$xpid" 2>/dev/null || true; rm -rf "$work"' EXIT
fail() { echo "smoke: FAIL: $*" >&2; exit 1; }

mkdir "$work/cwd" "$work/home"
cd "$work/cwd"

# Relative and store state homes are rejected before anything is created.
for bad in relative/state "$out/state" /nix/store; do
  if HOME=$work/home XDG_STATE_HOME=$bad "$launcher" 2>"$work/err"; then
    fail "accepted XDG_STATE_HOME=$bad"
  fi
  grep -q 'for-roguelike: .*state directory' "$work/err" || fail "no message for $bad"
done
[ -z "$(ls -A "$work/cwd")$(ls -A "$work/home")" ] || fail "rejected launches wrote files"

Xvfb -displayfd 3 -nolisten tcp -screen 0 1280x1024x24 3>"$work/display" \
  >"$work/xvfb.log" 2>&1 &
xpid=$!
for _ in $(seq 100); do [ -s "$work/display" ] && break; sleep 0.1; done
[ -s "$work/display" ] || fail "Xvfb did not start"
export DISPLAY=:$(cat "$work/display")
unset SDL_VIDEODRIVER
export SDL_AUDIODRIVER=dummy
# Keep SDL's session-bus and runtime lookups inside the scratch directory.
mkdir -m 700 "$work/run"
export XDG_RUNTIME_DIR=$work/run DBUS_SESSION_BUS_ADDRESS=unix:path=$work/run/no-bus

# play NAME STATE: run the game with the given environment, quit with Escape,
# and check the generated world in STATE.
play() {
  name=$1 state=$2; shift 2
  env "$@" "$launcher" >"$work/$name.out" 2>&1 &
  pid=$!
  wid=
  for _ in $(seq 300); do
    wid=$(xdotool search --name '^FOR$' 2>/dev/null | head -n1) && [ -n "$wid" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  [ -n "$wid" ] || { cat "$work/$name.out" >&2; fail "$name: no FOR window"; }
  for _ in $(seq 50); do
    kill -0 "$pid" 2>/dev/null || break
    xdotool windowfocus "$wid" key Escape 2>/dev/null || true
    sleep 0.2
  done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; fail "$name: Escape did not quit"; fi
  status=0; wait "$pid" || status=$?
  cat "$work/$name.out"
  [ "$status" = 0 ] || fail "$name: exit status $status"
  ! grep -q 'Generated exception' "$work/$name.out" || fail "$name: game exception"
  grep -q "new structure type" "$work/$name.out" || fail "$name: items.cfg not parsed"

  [ -d "$state" ] || fail "$name: no state directory $state"
  [ "$(stat -c %a "$state")" = 700 ] || fail "$name: state mode $(stat -c %a "$state")"
  for f in leveldump.txt visdump.txt edgedump.txt pathdump.txt; do
    [ "$(wc -l <"$state/$f")" = 70 ] || fail "$name: $f is not 70 rows"
    [ "$(stat -c %a "$state/$f")" = 600 ] || fail "$name: $f mode"
  done
  # Each map row is 70 cells; the level must contain more than blank space.
  awk 'length($0) != 70 { bad = 1 } END { exit bad }' "$state/leveldump.txt" \
    || fail "$name: leveldump rows are not 70 cells"
  [ "$(tr -d ' \n' <"$state/leveldump.txt" | wc -c)" -gt 500 ] \
    || fail "$name: leveldump is nearly empty"
  grep -q x "$state/pathdump.txt" || fail "$name: no A* path in pathdump"
  echo "smoke: $name: world generated in $state"
  head -n 8 "$state/leveldump.txt"
}

play xdg "$work/state/for-roguelike" HOME="$work/home" XDG_STATE_HOME="$work/state"
play home "$work/home/.local/state/for-roguelike" -u XDG_STATE_HOME HOME="$work/home"

[ -z "$(ls -A "$work/cwd")" ] || fail "game wrote to the invoking directory"
echo "smoke: ok"
