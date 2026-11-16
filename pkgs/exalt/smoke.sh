#!/bin/sh
# Installed-runtime check for exalt.
# Usage: smoke.sh OUT   (needs Xvfb, xdotool, xwd, ImageMagick and coreutils)
#
# Each step sends keys to the main window and waits for its pixels to
# change; the text on screen is not read.
set -eu
out=$1
launcher=$out/bin/exalt
work=$(mktemp -d)
xpid=
pid=
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  [ -z "$xpid" ] || kill "$xpid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
fail() { echo "smoke: FAIL: $*" >&2; exit 1; }

mkdir "$work/cwd" "$work/home"
cd "$work/cwd"

# Arguments, relative homes and store locations are rejected before the
# game starts.
if HOME=$work/home "$launcher" --help 2>"$work/err"; then fail "accepted an argument"; fi
grep -q '^usage: exalt' "$work/err" || fail "no usage message"
if XDG_DATA_HOME=relative HOME=relative "$launcher" 2>"$work/err"; then
  fail "accepted a relative HOME"
fi
grep -q '^exalt: state directory must be absolute' "$work/err" || fail "no message for relative HOME"
for bad in "$out/state" "${out%/*}"; do
  if HOME=$work/home XDG_DATA_HOME=$bad "$launcher" 2>"$work/err"; then
    fail "accepted XDG_DATA_HOME=$bad"
  fi
  grep -q '^exalt: refusing state in the immutable store' "$work/err" || fail "no message for $bad"
done
[ -z "$(ls -A "$work/cwd")$(ls -A "$work/home")" ] || fail "rejected launches wrote files"

Xvfb -displayfd 3 -nolisten tcp -screen 0 1280x800x24 3>"$work/display" \
  >"$work/xvfb.log" 2>&1 &
xpid=$!
for _ in $(seq 100); do [ -s "$work/display" ] && break; sleep 0.1; done
[ -s "$work/display" ] || fail "Xvfb did not start"
export DISPLAY=:$(cat "$work/display")
export SDL_AUDIODRIVER=dummy
mkdir -m 700 "$work/run"
export XDG_RUNTIME_DIR=$work/run DBUS_SESSION_BUS_ADDRESS=unix:path=$work/run/no-bus

# visible TITLE: print the mapped windows with exactly that title.
visible() { xdotool search --onlyvisible --name "^$1\$" 2>/dev/null || true; }

# snap: print a hash of the main window's pixels.
snap() { xwd -silent -id "$wid" | sha256sum | cut -d' ' -f1; }

# settle: wait until two snapshots 0.3 s apart agree and print their hash.
settle() {
  previous=$(snap)
  for _ in $(seq 30); do
    sleep 0.3
    current=$(snap)
    if [ "$current" = "$previous" ]; then echo "$current"; return 0; fi
    previous=$current
  done
  return 1
}

# start NAME ENV...: run the launcher and wait for the main window.  SDL
# first maps a short-lived window with the same title, so the window has to
# be seen twice.
start() {
  name=$1; shift
  env "$@" "$launcher" >"$work/$name.out" 2>&1 &
  pid=$!
  wid=
  seen=
  for _ in $(seq 150); do
    candidate=$(visible Exalt | tail -n 1)
    if [ -n "$candidate" ] && [ "$candidate" = "$seen" ]; then wid=$candidate; break; fi
    seen=$candidate
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  [ -n "$wid" ] || { cat "$work/$name.out" >&2; fail "$name: no main window"; }
  settle >/dev/null || fail "$name: main menu never settled"
  xwd -silent -id "$wid" >"$work/$name.xwd"
  colours=$(magick "xwd:$work/$name.xwd" -format '%k' info:)
  echo "smoke: $name: main menu window has $colours colours"
  [ "$colours" -gt 2 ] || fail "$name: main window is blank"
}

# step TICKS LABEL XDOTOOL-ARGS...: once the main window is still, send it
# input and wait up to TICKS/5 seconds for its pixels to change.
step() {
  ticks=$1 label=$2; shift 2
  before=$(settle) || fail "$label: screen never settled"
  xdotool windowfocus "$wid" "$@"
  for _ in $(seq "$ticks"); do
    sleep 0.2
    kill -0 "$pid" 2>/dev/null || { cat "$work/$name.out" >&2; fail "$label: game exited"; }
    if [ "$(snap)" != "$before" ]; then
      echo "smoke: $label: screen changed"
      return 0
    fi
  done
  return 1
}

# finish STATE: wait for the game to exit and check what it left in STATE.
finish() {
  state=$1
  for _ in $(seq 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  if kill -0 "$pid" 2>/dev/null; then fail "$name: game did not exit"; fi
  status=0; wait "$pid" || status=$?
  pid=
  cat "$work/$name.out"
  [ "$status" = 0 ] || fail "$name: exit status $status"
  if grep -Eiq 'error|failed|fatal|assert|segmentation|exception|could not|cannot|warning' "$work/$name.out"; then
    fail "$name: game printed diagnostics"
  fi
  [ "$(stat -c %a "$state")" = 700 ] || fail "$name: state mode $(stat -c %a "$state")"
  { [ -f "$state/data/db" ] && [ ! -L "$state/data/db" ]; } || fail "$name: no SQLite file"
  { [ -d "$state/data/save" ] && [ ! -L "$state/data/save" ]; } || fail "$name: no save directory"
  for asset in display fonts help templates worlds log.xsl; do
    [ "$(readlink "$state/data/$asset")" = "$out/share/exalt/data/$asset" ] \
      || fail "$name: data/$asset does not link to the store"
  done
  # The release build logs warnings (2) and critical errors (1) only.
  grep -q '</Log>' "$state/log.xml" || fail "$name: log.xml is not closed"
  if grep -Eq '<Level>[[:space:]]*[12][[:space:]]*</Level>' "$state/log.xml"; then
    cat "$state/log.xml" >&2
    fail "$name: warnings or errors in log.xml"
  fi
  echo "smoke: $name: exit 0, state in $state"
}

# A new game: New Character, first race, a name, first world.
start xdg HOME="$work/home" XDG_DATA_HOME="$work/xdg"
[ -z "$(visible Inventory)$(visible Equipment)$(visible Messages)$(visible Minimap)" ] \
  || fail "auxiliary windows visible at start"
step 50 "new character" key --delay 70 a || fail "main menu ignored 'a'"
step 50 "race chosen" key --delay 70 a || fail "race menu ignored 'a'"
step 50 "name typed" type --delay 100 Smoke || fail "name prompt ignored typing"
step 50 "name entered" key --delay 70 Return || fail "name prompt ignored Return"
step 50 "world chosen" key --delay 70 a || fail "world menu ignored 'a'"
# Starting a game replaces the character's save directory.
[ -d "$work/xdg/exalt/data/save/Smoke" ] || fail "no save directory for the new character"
moved=
for k in 6 4 8 2; do
  if step 15 "movement key $k" key --delay 70 "$k"; then moved=$k; break; fi
done
[ -n "$moved" ] || fail "no movement key changed the screen"

# F1 shows the Inventory window and hides it again.
xdotool windowfocus "$wid" key --delay 70 F1
sleep 1
[ -n "$(visible Inventory)" ] || fail "F1 did not show the Inventory window"
xdotool windowfocus "$wid" key --delay 70 F1
sleep 1
[ -z "$(visible Inventory)" ] || fail "F1 did not hide the Inventory window"
kill -0 "$pid" 2>/dev/null || fail "game exited after F1"
echo "smoke: xdg: Inventory window toggled"

# There is no quit key in a running game.  SDL turns SIGTERM into the same
# quit event as closing the main window.
kill -TERM "$pid"
finish "$work/xdg/exalt"
[ ! -e "$work/home/.local" ] || fail "XDG_DATA_HOME run wrote under HOME"

# HOME fallback; Escape in the main menu quits.
start home -u XDG_DATA_HOME HOME="$work/home"
xdotool windowfocus "$wid" key --delay 70 Escape
finish "$work/home/.local/share/exalt"

[ -z "$(ls -A "$work/cwd")" ] || fail "game wrote to the invoking directory"
echo "smoke: ok"
