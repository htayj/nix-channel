#!@shell@
# letter-hunt-smoke: play and reload a real Letter Hunt game in PTYs.
#
# Upstream shows its welcome text in the message panel of the first game
# screen; it is not a modal prompt, and 'Q' is always "Quit and Save".  The
# first session therefore waits for that screen, takes a turn with 'h',
# inspects the character sheet with 'i', and saves with 'Q' plus a key.  The
# second session must load that save (the game unlinks letterhunt.sav only
# after load_stuff() opened it, before drawing the first screen), shows the
# character sheet again, and saves again; both saves must record the same
# avatar, score, words, and map.  The first session finds its state through
# XDG_STATE_HOME and the second through the HOME fallback, which name the same
# directory.  Every key is sent only after the screen it answers was drawn,
# and a session that exits early fails at once with its own output.
#
# All mutable files live below a disposable HOME/XDG tree that is removed on
# exit; the caller's own save is never touched.  The only line written to
# stdout is the success marker.  LETTER_HUNT_SMOKE_RAW_CAPTURE, when set,
# receives the second session's PTY stream up to the restored game's
# character sheet, before quitting leaves the alternate screen.
set -eu

cat=@coreutils@/bin/cat
cksum=@coreutils@/bin/cksum
cmp=@diffutils@/bin/cmp
cp=@coreutils@/bin/cp
dirname=@coreutils@/bin/dirname
head=@coreutils@/bin/head
ls=@coreutils@/bin/ls
mkdir=@coreutils@/bin/mkdir
mkfifo=@coreutils@/bin/mkfifo
mktemp=@coreutils@/bin/mktemp
od=@coreutils@/bin/od
rm=@coreutils@/bin/rm
sleep=@coreutils@/bin/sleep
stty=@coreutils@/bin/stty
tail=@coreutils@/bin/tail
timeout=@coreutils@/bin/timeout
tr=@coreutils@/bin/tr
wc=@coreutils@/bin/wc
script=@utillinux@/bin/script
output=@out@
launcher=@out@/bin/letter-hunt

if test "$#" -ne 0; then
    echo 'usage: letter-hunt-smoke' >&2
    exit 64
fi

fail ()
{
    printf 'letter-hunt smoke: %s\n' "$1" >&2
    exit 1
}

tmp=${TMPDIR:-/tmp}
case "$tmp" in
    /*) ;;
    *) fail 'TMPDIR must be an absolute directory' ;;
esac
scratch=$("$mktemp" -d "$tmp/letter-hunt-smoke.XXXXXXXX")
trap '"$rm" -rf "$scratch"' EXIT HUP INT TERM
"$mkdir" "$scratch/home" "$scratch/config" "$scratch/data" "$scratch/cache" \
    "$scratch/runtime" "$scratch/tmp" "$scratch/work"
export HOME="$scratch/home"
export XDG_CONFIG_HOME="$scratch/config"
export XDG_DATA_HOME="$scratch/data"
export XDG_CACHE_HOME="$scratch/cache"
export XDG_RUNTIME_DIR="$scratch/runtime"
export TMPDIR="$scratch/tmp"
unset XDG_STATE_HOME
# The curses port refuses anything but an 80-column terminal of at least 30
# lines; script's PTY is resized to exactly that before the launcher runs.
export TERM=xterm LC_ALL=C SHELL=@shell@
work=$scratch/work
state=$HOME/.local/state/letter-hunt
save=$state/letterhunt.sav
exited='[letter-hunt smoke: game exited with status'

# text FILE: FILE's PTY stream without NUL bytes.
text ()
{
    "$tr" -d '\000' <"$1"
}

# contains FILE TEXT: FILE exists and its stream contains TEXT.
contains ()
{
    test -f "$1" || return 1
    case "$(text "$1")" in
        *"$2"*) return 0 ;;
    esac
    return 1
}

# size FILE: the number of bytes the session has written so far.
size ()
{
    "$wc" -c <"$1"
}

# wait_until FILE CONDITION ARG: wait up to 30 seconds for CONDITION FILE ARG.
# A game that exits first ends the wait at once.
wait_until ()
{
    tries=0
    until "$2" "$1" "$3"; do
        if contains "$1" "$exited"; then
            printf 'letter-hunt smoke: the game exited early\n' >"$1.why"
            return 1
        fi
        tries=$((tries + 1))
        if test "$tries" -gt 300; then
            printf 'letter-hunt smoke: timed out waiting for %s\n' "$3" \
                >"$1.why"
            return 1
        fi
        "$sleep" 0.1
    done
}

wait_for ()
{
    wait_until "$1" contains "$2"
}

# grown FILE SIZE: FILE is now longer than SIZE bytes.
grown ()
{
    test "$(size "$1")" -gt "$2"
}

# feed RAW SESSION: type each key once the game has drawn the screen it
# answers.
feed ()
{
    # The first game screen: the map, the status line, and the welcome text.
    wait_for "$1" 'Wordlist built!' || return 1
    wait_for "$1" 'Welcome to Letter Hunt!' || return 1
    wait_for "$1" 'Shields:' || return 1
    if test "$2" = first; then
        # Take a turn: step west.  Walking, bumping into a wall, or meeting
        # a letter all redraw part of the screen.
        before=$(size "$1")
        printf h
        wait_until "$1" grown "$before" || return 1
    else
        # The status line is drawn only after load_stuff() succeeded and the
        # game unlinked the save it restored.
        if test -e "$save"; then
            printf 'letter-hunt smoke: the save was not loaded\n' >"$1.why"
            return 1
        fi
    fi
    printf i
    wait_for "$1" 'Your character sheet:' || return 1
    wait_for "$1" 'Ranged Weapon:' || return 1
    if test "$2" = second; then
        # Let curses finish this refresh, then keep the stream as written so
        # far: the restored game's map, status line, and character sheet.
        "$sleep" 1
        "$cp" "$1" "$work/second.frame.raw"
    fi
    printf Q
    wait_for "$1" 'Saving...' || return 1
    wait_for "$1" 'Done.  Hit a key to quit.' || return 1
    # The game discards keys typed before it clears its key buffer, so keep
    # offering one until it exits.
    tries=0
    until contains "$1" "$exited"; do
        tries=$((tries + 1))
        if test "$tries" -gt 150; then
            printf 'letter-hunt smoke: the game did not quit\n' >"$1.why"
            return 1
        fi
        printf ' '
        "$sleep" 0.2
    done
}

# play SESSION: run one complete PTY session of the installed launcher.  The
# keys go through a FIFO so that a session whose screen never appears is
# stopped at once instead of waiting for the timeout.
play ()
{
    raw=$work/$1.raw
    input=$work/$1.input
    : >"$raw"
    "$mkfifo" "$input"
    "$timeout" 120 "$script" -qefc \
        "\"$stty\" rows 30 cols 80 && \"$launcher\"; status=\$?; printf '\\n%s %s]\\n' '$exited' \"\$status\"; exit \"\$status\"" \
        /dev/null <"$input" >"$raw" 2>"$work/$1.err" &
    session=$!
    exec 3>"$input"
    # A key written after the game exited must not kill this shell.
    if ( trap '' PIPE; feed "$raw" "$1" ) >&3; then
        exec 3>&-
        status=0
        wait "$session" || status=$?
    else
        exec 3>&-
        kill "$session" 2>/dev/null || :
        wait "$session" || :
        status=failed
    fi
    if test "$status" != 0; then
        test ! -s "$raw.why" || "$cat" "$raw.why" >&2
        printf 'letter-hunt smoke: last output of the %s session:\n' "$1" >&2
        text "$raw" | "$tr" -c '[:print:]\n' ' ' | "$tail" -n 5 >&2
        "$cat" "$work/$1.err" >&2
        fail "$1 session did not complete (status $status)"
    fi
    contains "$raw" "$exited 0]" || fail "$1 session did not exit cleanly"
}

# before_first FILE FIRST SECOND: FIRST occurs in FILE before SECOND.
before_first ()
{
    stream=$(text "$1")
    prefix=${stream%%"$3"*}
    test "$prefix" != "$stream" || return 1
    case "$prefix" in
        *"$2"*) return 0 ;;
    esac
    return 1
}

# First session: no save exists, so a new game starts.  XDG_STATE_HOME names
# the state directory explicitly.
export XDG_STATE_HOME="$HOME/.local/state"
play first
unset XDG_STATE_HOME
test -s "$save" || fail 'first session did not create letterhunt.sav'
before_first "$work/first.raw" 'Welcome to Letter Hunt!' \
    'Your character sheet:' || fail 'first session showed no welcome screen'
before_first "$work/first.raw" 'Your character sheet:' 'Saving...' || \
    fail 'first session did not show the character sheet before saving'
"$cp" "$save" "$work/first.sav"

# Second session: XDG_STATE_HOME is unset, so the launcher falls back to the
# same directory below HOME, loads the save, and saves again.
play second
test -s "$save" || fail 'second session did not save again'
before_first "$work/second.raw" 'Your character sheet:' 'Saving...' || \
    fail 'second session did not show the character sheet before saving'

# header_size FILE: the length of the save up to the first map's creature
# list: the avatar and score (8 bytes), the NUL-terminated captured words and
# their empty terminator, the NUL-terminated letter buffer, the map marker
# (1), the map size (8), its 35x25 tile and flag arrays (1750), and its room
# count (4).
header_size ()
{
    pos=0
    phase=words
    word_start=1
    for byte in $("$od" -An -v -tu1 "$1"); do
        pos=$((pos + 1))
        test "$pos" -gt 8 || continue
        if test "$phase" = words; then
            if test "$byte" = 0; then
                test "$word_start" = 0 || phase=buffer
                word_start=1
            else
                word_start=0
            fi
        elif test "$byte" = 0; then
            printf '%s\n' $((pos + 1 + 8 + 1750 + 4))
            return 0
        fi
    done
    return 1
}

# No turn passed in the second session, so the re-saved game has the same
# size and begins with the same avatar, score, captured words, letter buffer,
# and dungeon map.  Only the order of the map's creature and item lists,
# which loading reverses, may differ.
header=$(header_size "$work/first.sav") || fail 'the first save is truncated'
test "$(header_size "$save")" = "$header" || \
    fail 'the reloaded game saved different words'
test "$(size "$work/first.sav")" = "$(size "$save")" || \
    fail 'the reloaded game saved a different game'
"$cmp" -s -n "$header" "$work/first.sav" "$save" || \
    fail 'the reloaded game saved a different avatar, score, or map'

# The only mutable file is the save in the launcher's state directory; the
# game wrote no high score because nobody died.
test "$("$ls" -A "$state")" = letterhunt.sav || fail 'unexpected state files'
test "$("$ls" -A "$HOME")" = .local || fail 'unexpected files in HOME'
for dir in "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" \
           "$XDG_RUNTIME_DIR" "$TMPDIR"; do
    test -z "$("$ls" -A "$dir")" || fail "unexpected files in $dir"
done
test ! -w "$output" || fail 'package output is writable'
for dir in "$output/bin" "$output/libexec/letter-hunt" \
           "$output/share/letter-hunt"; do
    test ! -e "$dir/letterhunt.sav" || fail "save escaped into $dir"
    test ! -e "$dir/hiscore.txt" || fail "high scores escaped into $dir"
done

# The evidence frame is an unmodified leading part of the second session's
# PTY stream: the loaded game with its character sheet, before 'Q' saved it
# and the exit left curses' alternate screen.
frame=$work/second.frame.raw
test -s "$frame" || fail 'no post-load gameplay frame was captured'
frame_size=$(size "$frame")
test "$("$head" -c "$frame_size" "$work/second.raw" | "$cksum")" = \
    "$("$cksum" <"$frame")" || fail 'gameplay frame is not a stream prefix'
for want in 'Welcome to Letter Hunt!' 'Pts:' 'Shields:' \
            'Your character sheet:' 'Melee Weapon:'; do
    contains "$frame" "$want" || fail "gameplay frame lacks '$want'"
done
! contains "$frame" 'Saving...' || fail 'gameplay frame includes the quit'

if test -n "${LETTER_HUNT_SMOKE_RAW_CAPTURE:-}"; then
    "$mkdir" -p "$("$dirname" "$LETTER_HUNT_SMOKE_RAW_CAPTURE")"
    "$cp" "$frame" "$LETTER_HUNT_SMOKE_RAW_CAPTURE"
fi

printf '%s\n' LETTER_HUNT_RUNTIME_OK
