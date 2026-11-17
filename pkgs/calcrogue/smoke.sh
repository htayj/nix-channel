#!/bin/sh
# Installed-runtime check for calcrogue.
# Usage: smoke.sh OUT   (needs script from util-linux, coreutils and gzip on PATH)
#
# play: a new Fighter game on an 80x25 pseudo-terminal.  The title menu, the
# class menu and the introduction lead to the first dungeon level with its
# status line.  The digits 4, 6, 8 and 2 are movement keys; at least one of
# them must redraw the player.  5 waits one turn and S saves and quits.  The
# game must exit with status 0 and leave exactly one valid gzip save in the
# XDG state directory.
# restore: a second process must resume that save without showing the title
# menu, and save again.
# fallback: without XDG_STATE_HOME the launcher uses HOME; f quits from the
# title menu.
# store: the launcher must refuse a state directory inside the store.
# The package output must be byte-identical afterwards.
set -eu
out=$1
launcher=$out/bin/calcrogue
work=$(mktemp -d)
session=
trap '[ -z "$session" ] || kill "$session" 2>/dev/null || true
      rm -rf "$work"' EXIT
trap '' PIPE

mkdir "$work/home" "$work/state" "$work/cwd"
cd "$work/cwd"
export HOME=$work/home TERM=xterm LC_ALL=C
SHELL=$(command -v sh)
export SHELL
unset XDG_STATE_HOME TERMINFO TERMINFO_DIRS
exited='[smoke: game exited with status'

manifest() { (cd "$out" && find . -type f -exec sha256sum {} + | sort); }
manifest >"$work/manifest.before"

# text: the current session's terminal stream without NUL bytes.
text() { tr -d '\000' <"$raw"; }
contains() {
  case "$(text)" in
    *"$1"*) return 0 ;;
  esac
  return 1
}
size() { wc -c <"$raw"; }

fail() {
  echo "smoke: FAIL: $*" >&2
  if [ -n "${raw:-}" ] && [ -f "$raw" ]; then
    echo "smoke: last output of the session:" >&2
    text | tr -c '[:print:]\n' ' ' | tail -n 8 >&2
  fi
  exit 1
}

# start NAME: run the launcher on an 80x25 pseudo-terminal.  Keys are written
# to descriptor 3.
start() {
  name=$1
  raw=$work/$name.raw
  : >"$raw"
  mkfifo "$work/$name.in"
  timeout 120 script -qefc \
    "stty rows 25 cols 80 && \"$launcher\"; status=\$?; printf '\\n%s %s]\\n' '$exited' \"\$status\"" \
    /dev/null <"$work/$name.in" >"$raw" 2>"$work/$name.err" &
  session=$!
  exec 3>"$work/$name.in"
}

# finish STATUS: the session must end by itself within 30 seconds, with that
# exit status.
finish() {
  tries=0
  until contains "$exited"; do
    tries=$((tries + 1))
    [ "$tries" -le 300 ] || fail "$name: the game did not exit"
    sleep 0.1
  done
  exec 3>&-
  wait "$session" || true
  session=
  contains "$exited $1]" || fail "$name: expected exit status $1"
}

# wait_for TEXT: wait up to 30 seconds until the stream contains TEXT.  A game
# that exits first ends the wait at once.
wait_for() {
  tries=0
  until contains "$1"; do
    ! contains "$exited" || fail "$name: the game exited before '$1'"
    tries=$((tries + 1))
    [ "$tries" -le 300 ] || fail "$name: timed out waiting for '$1'"
    sleep 0.1
  done
}

# settle: wait until the terminal stream has stopped growing.
settle() {
  last=-1
  until [ "$(size)" = "$last" ]; do
    last=$(size)
    sleep 0.3
  done
}

key() { printf '%s' "$1" >&3; }

# redraws_player KEY: within two seconds of KEY the game draws '@' again.
redraws_player() {
  before=$(size)
  key "$1"
  tries=0
  while [ "$tries" -lt 20 ]; do
    case "$(tail -c +"$((before + 1))" "$raw" | tr -d '\000')" in
      *@*) return 0 ;;
    esac
    tries=$((tries + 1))
    sleep 0.1
  done
  return 1
}

# play
export XDG_STATE_HOME=$work/state
start play
wait_for 'Tutorial'
key a
wait_for 'Fighter'
key a
wait_for 'Creation'
printf '\n' >&3
wait_for 'LV1'
wait_for '@'
settle
moves=0
for digit in 4 6 8 2; do
  if redraws_player "$digit"; then
    moves=$((moves + 1))
  fi
done
[ "$moves" -ge 1 ] || fail 'play: no movement key redrew the player'
key 5
settle
key S
finish 0
[ "$(ls -A "$work/state")" = calcrogue ] || fail 'play: unexpected state directories'
[ "$(ls -A "$work/state/calcrogue")" = rgsave.gz ] ||
  fail 'play: the state directory does not hold exactly the compressed save'
gzip -t "$work/state/calcrogue/rgsave.gz" || fail 'play: the save is not valid gzip data'
first=$(sha256sum <"$work/state/calcrogue/rgsave.gz")
echo "smoke: play ok ($moves of 4 movement keys redrew the player)"

# restore
start restore
wait_for 'LV1'
wait_for '@'
settle
! contains 'Tutorial' || fail 'restore: the title menu was shown instead of the saved game'
key 5
settle
key S
finish 0
[ "$(ls -A "$work/state/calcrogue")" = rgsave.gz ] ||
  fail 'restore: the state directory does not hold exactly the compressed save'
gzip -t "$work/state/calcrogue/rgsave.gz" || fail 'restore: the save is not valid gzip data'
[ "$(sha256sum <"$work/state/calcrogue/rgsave.gz")" != "$first" ] ||
  fail 'restore: the extra turn did not change the save'
[ -z "$(ls -A "$work/home")" ] || fail 'restore: files were written to HOME'
echo 'smoke: restore ok'

# fallback
unset XDG_STATE_HOME
start fallback
wait_for 'Tutorial'
key f
finish 0
[ "$(ls -A "$work/home/.local/state")" = calcrogue ] ||
  fail 'fallback: the HOME fallback state directory was not used'
echo 'smoke: fallback ok'

# store
status=0
XDG_STATE_HOME=$out "$launcher" </dev/null >"$work/store.log" 2>&1 || status=$?
[ "$status" = 1 ] || fail "store: expected exit status 1, got $status"
grep -qF 'refusing state in the immutable store' "$work/store.log" ||
  fail 'store: no refusal message'
echo 'smoke: store ok'

[ -z "$(ls -A "$work/cwd")" ] || fail 'files were written to the working directory'
manifest >"$work/manifest.after"
cmp -s "$work/manifest.before" "$work/manifest.after" ||
  fail 'the package output changed during play'
echo 'smoke: ok'
