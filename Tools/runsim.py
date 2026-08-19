import sys, os, lupa
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
rt = lupa.lua51.LuaRuntime(unpack_returned_tuples=True)
try:
    rt.execute(open("Tools/simulate.lua", encoding="utf-8").read())
except lupa.LuaError as e:
    print("LUA ERROR:", e); sys.exit(1)
