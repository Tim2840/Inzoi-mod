"""Runs the Lua test suite with lupa (embedded Lua 5.4).

    python3 -I tests/run.py          # needs: pip install lupa

Any plain Lua 5.1-5.4 works too:  lua -e 'package.path="mod/lua/?.lua;tests/?.lua;"..package.path' tests/run.lua
"""
import sys
from pathlib import Path

try:
    import lupa.lua54 as lupa
except ImportError:
    sys.exit("lupa is not installed: pip install lupa")

root = Path(__file__).resolve().parent.parent
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(
    'package.path = "%s/mod/lua/?.lua;%s/tests/?.lua;" .. package.path'
    % (root.as_posix(), root.as_posix())
)
failed = lua.execute('return dofile("%s")' % (root / "tests" / "run.lua").as_posix())
sys.exit(1 if failed else 0)
