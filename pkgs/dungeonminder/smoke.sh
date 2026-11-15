#!/bin/sh
# Installed-runtime check for dungeonminder.
# Usage: smoke.sh OUT   (needs Xvfb, xdotool and coreutils on PATH)
#
# main() loads the font, opens the 80 by 60 cell "DungeonMinder" window,
# generates level 1 with the hero's A* path and waits for a key.  Space passes
# a turn, so the hero walks that path.  Escape closes an open menu and, in the
# main loop, calls exit(0).  libtcod exits 1 on a font or video failure.
set -eu
out=$1
work=$(mktemp -d)
xpid=
trap '[ -z "$xpid" ] || kill "$xpid" 2>/dev/null || true; rm -rf "$work"' EXIT
fail() { echo "smoke: FAIL: $*" >&2; exit 1; }

mkdir "$work/cwd" "$work/home"
mkdir -m 700 "$work/run"
cd "$work/cwd"

Xvfb -displayfd 3 -nolisten tcp -screen 0 1280x1024x24 3>"$work/display" \
  >"$work/xvfb.log" 2>&1 &
xpid=$!
for _ in $(seq 100); do [ -s "$work/display" ] && break; sleep 0.1; done
[ -s "$work/display" ] || fail "Xvfb did not start"
export DISPLAY=:$(cat "$work/display")
unset SDL_VIDEODRIVER
export SDL_AUDIODRIVER=dummy HOME=$work/home
# Keep SDL's session-bus and runtime lookups inside the scratch directory.
export XDG_RUNTIME_DIR=$work/run DBUS_SESSION_BUS_ADDRESS=unix:path=$work/run/no-bus

"$out/bin/dungeonminder" >"$work/game.out" 2>&1 &
pid=$!
wid=
for _ in $(seq 300); do
  wid=$(xdotool search --name '^DungeonMinder$' 2>/dev/null | head -n1) && [ -n "$wid" ] && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.1
done
[ -n "$wid" ] || { cat "$work/game.out" >&2; fail "no DungeonMinder window"; }

# 80 by 60 cells of the 8 by 8 pixel font.
eval "$(xdotool getwindowgeometry --shell "$wid")"
[ "$WIDTH" = 640 ] && [ "$HEIGHT" = 480 ] || fail "window is ${WIDTH}x$HEIGHT"

# The game discards keys queued before it waits, so pace the input.
sleep 1
for _ in 1 2 3 4 5; do
  xdotool windowfocus "$wid" key space 2>/dev/null || true
  sleep 0.3
done
for _ in $(seq 50); do
  kill -0 "$pid" 2>/dev/null || break
  xdotool windowfocus "$wid" key Escape 2>/dev/null || true
  sleep 0.2
done
if kill -0 "$pid" 2>/dev/null; then kill "$pid"; fail "Escape did not quit"; fi
status=0; wait "$pid" || status=$?
cat "$work/game.out"
[ "$status" = 0 ] || fail "exit status $status"
! grep -qE 'SDL : cannot|size is not a multiple|terminate called' "$work/game.out" \
  || fail "runtime error output"
[ -z "$(ls -A "$work/cwd")" ] || fail "game wrote to the working directory"
echo "smoke: ok"
