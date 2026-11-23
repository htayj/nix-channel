"""Immutable resources and the game's single writable XDG data directory."""
import os

DATA_DIR = os.path.dirname(os.path.realpath(__file__))
_data_home = os.environ.get("XDG_DATA_HOME", "")
if not os.path.isabs(_data_home):
    _home = os.path.expanduser("~")
    if not os.path.isabs(_home):
        raise RuntimeError("Enemy Trench needs an absolute HOME or XDG_DATA_HOME")
    _data_home = os.path.join(_home, ".local", "share")
STATE_DIR = os.path.join(_data_home, "enemy-trench")
os.makedirs(STATE_DIR, exist_ok=True)
