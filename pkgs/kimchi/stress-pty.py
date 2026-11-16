#!/usr/bin/env python3
"""Run upstream bot fixtures, selecting Kimchi's native Artificer equipment.

Kimchi adds an equipment chooser before the upstream Lua ready() bot starts.
Select its first entry (the original bundle of wands) only when the real menu
is displayed.  Never create game state or send gameplay actions.
"""
import errno
import os
import pty
import re
import select
import signal
import sys
import time

PROMPT = b'You have a choice of starting condition.'
ANSI = re.compile(rb'\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[()][0-2A-Z]|[=>])')


def main():
    if len(sys.argv) < 2:
        raise SystemExit('usage: kimchi-stress-pty.py program [args]')
    pid, master = pty.fork()
    if pid == 0:
        import fcntl
        import struct
        import termios
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        os.execvp(sys.argv[1], sys.argv[1:])
    pending = b''
    started = last_output = time.monotonic()
    failure = None
    try:
        while True:
            now = time.monotonic()
            if now - started > 3600 or now - last_output > 60:
                failure = 'stress PTY deadline reached without fixture completion'
                break
            if not select.select([master], [], [], 1)[0]:
                continue
            try:
                data = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            last_output = time.monotonic()
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
            pending = (pending + data)[-16384:]
            plain = ANSI.sub(b'', pending)
            if PROMPT in plain:
                os.write(master, b'a')
                sys.stderr.write('\nKimchi stress adapter: selected native bundle of wands.\n')
                sys.stderr.flush()
                pending = b''
    finally:
        os.close(master)
        if failure:
            os.kill(pid, signal.SIGTERM)
        _, status = os.waitpid(pid, 0)
    if failure:
        raise SystemExit(failure)
    raise SystemExit(os.waitstatus_to_exitcode(status))


if __name__ == '__main__':
    main()
