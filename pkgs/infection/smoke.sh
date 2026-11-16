#!/bin/sh
# Installed-runtime check for infection.
# Usage: smoke.sh OUT   (needs Xvfb, xdotool, xwd and coreutils on PATH)
#
# The menu opens on "Play - Normal".  Return starts a game: gameData.js and
# an organ tileset are parsed, a map is generated and the characters are
# placed.  "Play - Easy" also adds three traits and four growth factors.
# Tab opens the trait screen, h the help screen, Escape closes either, and q
# makes main return.  libtcod reads the arrow keys and Escape from the live
# key state after the press event, so every key is held briefly.
set -eu
out=$1
launcher=$out/bin/infection
work=$(mktemp -d)
xpid=
pid=
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null || true
      [ -z "$xpid" ] || kill "$xpid" 2>/dev/null || true
      rm -rf "$work"' EXIT
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

# Hash the 1280x1024 32-bit pixel data only; the dump's colormap padding is
# uninitialized and differs between captures of the same screen.
frame() { xwd -root -silent | tail -c 5242880 | sha256sum | cut -d' ' -f1; }
alive() { [ -z "$pid" ] || kill -0 "$pid" 2>/dev/null; }

# settle: wait until two consecutive captures agree; that frame is $new.
settle() {
  new=$(frame)
  for _ in $(seq 50); do
    sleep 0.1
    prev=$new
    new=$(frame)
    [ "$new" != "$prev" ] || return 0
  done
  fail "$name: screen keeps changing"
}

# await OLD WHAT: wait for a settled screen that differs from OLD.
await() {
  for _ in $(seq 100); do
    settle
    [ "$new" = "$1" ] || return 0
    alive || { cat "$work/$name.out" >&2; fail "$name: game exited before $2"; }
  done
  fail "$name: screen did not change for $2"
}

hold() {
  xdotool windowfocus "$wid" keydown "$1"
  sleep 0.15
  xdotool keyup "$1"
  sleep 0.25
}

# step KEY WHAT: hold KEY once and wait for a different settled screen.  The
# key is never repeated: a second Escape would quit the game.
step() {
  old=$new
  hold "$1"
  await "$old" "$2"
}

name=setup
settle
blank=$new

# play NAME KEY...: start a game with the given menu keys, visit the trait
# and help screens, take four turns and quit.
play() {
  name=$1; shift
  "$launcher" >"$work/$name.out" 2>&1 &
  pid=$!
  wid=
  for _ in $(seq 300); do
    wid=$(xdotool search --name '^Infection$' 2>/dev/null | head -n1) && [ -n "$wid" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  [ -n "$wid" ] || { cat "$work/$name.out" >&2; fail "$name: no Infection window"; }
  await "$blank" "the menu"
  menu=$new

  for key in "$@"; do step "$key" "menu key $key"; done
  game=$new
  [ "$game" != "$menu" ] || fail "$name: still on the menu"

  step Tab "the trait screen"
  step Escape "leaving the trait screen"
  step h "the help screen"
  step Escape "leaving the help screen"
  for key in Right Down Left Up; do hold "$key"; done
  kill -0 "$pid" 2>/dev/null || { cat "$work/$name.out" >&2; fail "$name: game died while moving"; }

  for _ in $(seq 25); do
    kill -0 "$pid" 2>/dev/null || break
    hold q
  done
  if kill -0 "$pid" 2>/dev/null; then fail "$name: q did not quit"; fi
  status=0; wait "$pid" || status=$?
  pid=
  cat "$work/$name.out"
  [ "$status" = 0 ] || fail "$name: exit status $status"
  ! grep -q 'initMap exception\|initWorld exception' "$work/$name.out" \
    || fail "$name: game data did not load"
  await "$game" "the window closing"
  echo "smoke: $name: played and quit"
}

play normal Return
play easy Down Return

[ -z "$(ls -A "$work/cwd")" ] || fail "game wrote to the invoking directory"
[ -z "$(ls -A "$work/home")" ] || fail "game wrote to HOME"
echo "smoke: ok"
