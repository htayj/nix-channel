#!/bin/sh
# Installed-runtime check for gnollhack.
# Usage: smoke.sh OUT   (needs util-linux script, coreutils and grep)
#
# The tty port prints "Shall I pick a character for you? [ynaq]"
# (src/role.c) once it has loaded nhdat from the store and entered the
# playground; answering 'q' quits before any game is created.
set -eu
out=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "smoke: FAIL: $*" >&2; exit 1; }

mkdir "$work/cwd" "$work/home" "$work/xdg"
cd "$work/cwd"

# Relative, store and over-long playgrounds are rejected before the game runs.
for program in gnollhack gnollhack-recover; do
  if env -u XDG_DATA_HOME HOME=relative "$out/bin/$program" 2>"$work/err"; then
    fail "$program accepted a relative HOME"
  fi
  grep -q 'absolute HOME or XDG_DATA_HOME' "$work/err" || fail "no message for relative HOME"
  for bad in "$out" "$(dirname "$out")"; do
    if HOME=$work/home XDG_DATA_HOME=$bad "$out/bin/$program" 2>"$work/err"; then
      fail "$program accepted XDG_DATA_HOME=$bad"
    fi
    grep -q 'outside the store' "$work/err" || fail "no message for $bad"
  done
  long=$work/$(printf '%0130d' 0)
  if HOME=$work/home XDG_DATA_HOME=$long "$out/bin/$program" 2>"$work/err"; then
    fail "$program accepted an over-long playground"
  fi
  grep -q '128-byte limit' "$work/err" || fail "no message for long playground"
done
[ -z "$(find "$work/cwd" "$work/home" "$work/xdg" -mindepth 1)" ] \
  || fail "rejected launches wrote files"

# play NAME ENV...: start the tty game in a pseudo-terminal and quit at the
# character-selection prompt.
play() {
  name=$1; shift
  # script(1) starts its command with $SHELL; the build sandbox's passwd
  # entry names a nonexistent shell, so pass one explicitly.
  { sleep 4; printf q; sleep 2; printf q; sleep 1; } 2>/dev/null \
    | env -i PATH="$PATH" SHELL="$(command -v sh)" TERM=xterm-256color "$@" \
        script -qfec "$out/bin/gnollhack -u smoke" "$work/$name.log" \
        >/dev/null 2>&1 || true
  grep -q 'Shall I pick' "$work/$name.log" \
    || { cat "$work/$name.log" >&2; fail "$name: no character-selection prompt"; }
}

check_state() {
  state=$1
  [ -d "$state/save" ] && [ -d "$state/dumps" ] || fail "missing $state/save or dumps"
  for f in perm record logfile livelog xlogfile wishtracker paniclog; do
    [ -f "$state/$f" ] || fail "missing $state/$f"
  done
  [ "$(stat -c %a "$state")" = 700 ] || fail "$state is not private"
}

play xdg HOME="$work/home" XDG_DATA_HOME="$work/xdg"
check_state "$work/xdg/gnollhack"
[ ! -e "$work/home/.local" ] || fail "XDG run wrote under HOME/.local"

play home HOME="$work/home"
check_state "$work/home/.local/share/gnollhack"

[ -z "$(ls -A "$work/cwd")" ] || fail "game wrote into the caller's directory"
# recover with no saved game names prints its usage and touches nothing else.
HOME=$work/home XDG_DATA_HOME=$work/xdg "$out/bin/gnollhack-recover" >"$work/recover.out" 2>&1 || true
grep -qi 'usage' "$work/recover.out" || { cat "$work/recover.out" >&2; fail "recover printed no usage"; }
echo "smoke: OK"
