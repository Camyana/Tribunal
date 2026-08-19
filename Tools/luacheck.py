import sys, glob, os
import lupa
# Prefer the Lua 5.1 runtime: WoW is 5.1, and 5.4 would accept syntax the game rejects.
rt = None
for name in ("lua51", "luajit21", "luajit20"):
    mod = getattr(lupa, name, None)
    if mod:
        try:
            rt = mod.LuaRuntime(); print(f"[runtime] {name}"); break
        except Exception:
            pass
if rt is None:
    rt = lupa.LuaRuntime(); print(f"[runtime] default {lupa.LuaRuntime().lua_implementation}")

loadstring = rt.eval("function(s,n) return loadstring and loadstring(s,n) or load(s,n) end")
fails = 0
for path in sorted(glob.glob("*.lua") + glob.glob("Modules/*.lua")):
    src = open(path, encoding="utf-8").read()
    try:
        fn, err = loadstring(src, "@" + path), None
    except Exception as e:
        fn, err = None, str(e)
    if fn is None:
        fails += 1
        print(f"FAIL {path}: {err}")
    else:
        print(f"  ok {path}  ({len(src.splitlines())} lines)")
print("\nall files compile" if not fails else f"\n{fails} file(s) failed")
sys.exit(1 if fails else 0)
