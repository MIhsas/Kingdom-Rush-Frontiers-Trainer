"""Run validation in Frontiers' own LuaJIT DLL (development only)."""
import ctypes
import os
from pathlib import Path

GAME = Path(r"D:\Steam\steamapps\common\Kingdom Rush Frontiers")
os.environ['KR_TRAINER_ROOT'] = Path(__file__).resolve().parent.as_posix()
DLL_DIRECTORY = os.add_dll_directory(str(GAME))
lib = ctypes.CDLL(str(GAME / "lua51.dll"))
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
lib.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
lib.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]

def run(code):
    state = lib.luaL_newstate()
    lib.luaL_openlibs(state)
    data = code.encode("utf-8")
    try:
        status = lib.luaL_loadbuffer(state, data, len(data), b"@validation")
        if not status:
            status = lib.lua_pcall(state, 0, 0, 0)
        if status:
            raise RuntimeError(lib.lua_tolstring(state, -1, None).decode("utf-8", errors="replace"))
    finally:
        lib.lua_close(state)

if __name__ == "__main__":
    import sys
    run(Path(sys.argv[1]).read_text(encoding="utf-8"))
