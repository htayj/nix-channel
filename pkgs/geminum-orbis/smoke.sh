#!/bin/sh
# Installed-runtime check for geminum-orbis.
# Usage: smoke.sh OUT   (needs script from util-linux and coreutils on PATH)
#
# play: one game on an 80x25 pseudo-terminal.  The name prompt, the character
# generator and its family summary lead to the first dungeon level with the
# status bar.  The digits 4, 6, 8 and 2 are the game's own movement keys; at
# least one of them must redraw the player.  Q, y and n leave through the
# unimplemented save prompt, and the game must exit with status 0 having
# created only its highscores file, in the XDG state directory.
# small: on 24 rows the game must refuse to start, through the HOME fallback.
# store: the launcher must refuse a state directory inside the store.
#
# Every key is sent only after the screen it answers was drawn.
set -eu
out=$1
launcher=$out/bin/geminum-orbis
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

# start NAME ROWS: run the launcher on an 80xROWS pseudo-terminal.  Keys are
# written to descriptor 3.
start() {
  name=$1
  raw=$work/$name.raw
  : >"$raw"
  mkfifo "$work/$name.in"
  timeout 120 script -qefc \
    "stty rows $2 cols 80 && \"$launcher\"; status=\$?; printf '\\n%s %s]\\n' '$exited' \"\$status\"" \
    /dev/null <"$work/$name.in" >"$raw" 2>"$work/$name.err" &
  session=$!
  exec 3>"$work/$name.in"
}

# finish STATUS: the session must have ended with that exit status.
finish() {
  wait_for "$exited"
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
start play 25
wait_for 'Geminum Orbis Copyright 2006-2008'
wait_for 'What is your name?'
printf 'Tester\n' >&3
wait_for 'Why, hello there, Tester!'
wait_for 'what gender will you be?'
key m
wait_for 'Your full name is Tester'
wait_for 'Norman, Oklahoma.'
wait_for 'Press any key to continue...'
key ' '
wait_for 'Dlvl:'
wait_for 'St:'
wait_for '@'
moves=0
for digit in 4 6 8 2; do
  if redraws_player "$digit"; then
    moves=$((moves + 1))
  fi
done
[ "$moves" -ge 1 ] || fail 'play: no movement key redrew the player'
key Q
wait_for 'Are you sure you want to leave?'
key y
wait_for 'Save game?'
key n
wait_for 'Goodbye Tester...'
wait_for 'Press any key to end...'
key ' '
finish 0
[ "$(ls -A "$work/state")" = geminum-orbis ] || fail 'play: unexpected state directories'
[ "$(ls -A "$work/state/geminum-orbis")" = highscores ] ||
  fail 'play: the state directory does not hold exactly the highscores file'
[ -z "$(ls -A "$work/home")" ] || fail 'play: files were written to HOME'
echo "smoke: play ok ($moves of 4 movement keys redrew the player)"

# small
unset XDG_STATE_HOME
start small 24
finish 1
contains 'a terminal of at least 80 columns by 25 rows is required.' ||
  fail 'small: no terminal size message'
[ "$(ls -A "$work/home/.local/state")" = geminum-orbis ] ||
  fail 'small: the HOME fallback state directory was not used'
echo 'smoke: small ok'

# store
status=0
XDG_STATE_HOME=$out "$launcher" </dev/null >"$work/store.log" 2>&1 || status=$?
[ "$status" = 1 ] || fail "store: expected exit status 1, got $status"
grep -qF 'refusing state in the immutable store' "$work/store.log" ||
  fail 'store: no refusal message'
echo 'smoke: store ok'

[ -z "$(ls -A "$work/cwd")" ] || fail 'files were written to the working directory'
echo 'smoke: ok'
