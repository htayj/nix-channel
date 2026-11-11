#!/bin/sh
# Hardware-free check for image-tape.
# Usage: smoke.sh PATH-TO-image-tape   (needs coreutils and grep)
#
# open_tape (tape.c) rejects a path that cannot be opened and any file that
# does not accept the MTIOCTOP ioctl, so /dev/null and regular files stop
# before a record is read.  The safe-output patch opens the output file
# (O_CREAT | O_TRUNC) before the device and reports open failures.
set -eu
prog=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "smoke: FAIL: $*" >&2; exit 1; }

# expect STATUS PATTERN ARGS...: run with a clean environment and check
# the exit status and a stderr line.
expect() {
  want=$1 pattern=$2
  shift 2
  set +e
  env -i "$prog" "$@" >"$work/out" 2>"$work/err" </dev/null
  got=$?
  set -e
  [ "$got" -eq "$want" ] || fail "$* exited $got, expected $want"
  grep -q "$pattern" "$work/err" || fail "$*: no '$pattern' on stderr"
}

expect 1 '^Usage: .* device \[output\]$'
expect 1 "^Couldn't open $work/missing: No such file or directory$" "$work/missing"
expect 1 "^Couldn't set variable block size: " /dev/null

printf 'not a tape' > "$work/regular"
expect 1 "^Couldn't set variable block size: " "$work/regular"
[ ! -s "$work/out" ] || fail "image data written to stdout without a tape"

# A named output file is created and truncated before the device is opened.
printf 'stale' > "$work/image"
expect 1 "^Couldn't set variable block size: " /dev/null "$work/image"
[ -f "$work/image" ] && [ ! -s "$work/image" ] || fail "output not truncated"
expect 1 "^Couldn't set variable block size: " /dev/null "$work/new.tap"
[ -f "$work/new.tap" ] || fail "output file not created"

# An output path that cannot be opened is reported before the device.
expect 1 "^Couldn't open $work/nodir/image: No such file or directory$" \
  /dev/null "$work/nodir/image"

echo "smoke: ok"
