#!@shell@
set -eu
qemu=@qemu@/bin/qemu-system-x86_64
image=@image@
coreutils=@coreutils@/bin

if test "$#" -eq 0; then
  exec "$qemu" -no-user-config -nic none -snapshot \
    -drive "file=$image,format=raw,if=floppy,readonly=on"
fi
if test "$1" != --smoke || test "$#" -ne 1; then
  echo 'usage: bootrogue [--smoke]' >&2
  exit 64
fi

# Drive a few arrow keys through the QEMU monitor, then check that the VGA
# screendump is a PPM image with more than one distinct byte value.
scratch=$("$coreutils/mktemp" -d "${TMPDIR:-/tmp}/bootrogue-smoke.XXXXXXXX")
trap '"$coreutils/rm" -rf "$scratch"' EXIT HUP INT TERM
screenshot="${BOOTROGUE_SMOKE_SCREENSHOT:-$scratch/rogue.ppm}"
case "$screenshot" in
  *[!A-Za-z0-9_./-]*)
    echo 'bootrogue: unsafe screenshot path' >&2
    exit 2;;
esac
"$coreutils/rm" -f "$screenshot"

report_failure () {
  "$coreutils/head" -c 4096 "$scratch/monitor.log" >&2
  exit 1
}

if ! {
  "$coreutils/sleep" 2
  "$coreutils/printf" '%s\n' 'sendkey right' 'sendkey down' 'sendkey left' 'sendkey up'
  "$coreutils/sleep" 1
  "$coreutils/printf" '%s\n' "screendump $screenshot"
  "$coreutils/sleep" 1
  "$coreutils/printf" '%s\n' 'quit'
} | "$qemu" -display none -monitor stdio -serial none \
    -nic none -snapshot -no-user-config \
    -drive "file=$image,format=raw,if=floppy,readonly=on" \
    >"$scratch/monitor.log" 2>&1; then
  report_failure
fi
test -s "$screenshot" || report_failure
test "$("$coreutils/head" -c 2 "$screenshot")" = P6 || report_failure
# Numeric sorting collapses od's empty field with zero, so a uniformly black
# frame has one unique value.
pixel_values=$("$coreutils/od" -An -v -tu1 -j 15 "$screenshot" |
  "$coreutils/tr" -s ' ' '\n' | "$coreutils/sort" -nu | "$coreutils/wc" -l)
test "$pixel_values" -gt 1 || report_failure
echo BOOTROGUE_RUNTIME_OK
