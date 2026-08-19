"""Compile every Lua file under a real Lua 5.1 runtime, and reject the one
class of bug that compiles cleanly and still breaks the addon."""
import sys, glob, os, re
import lupa

# Prefer the Lua 5.1 runtime: WoW is 5.1, and 5.4 would accept syntax the game
# rejects.
rt = None
for name in ("lua51", "luajit21", "luajit20"):
    mod = getattr(lupa, name, None)
    if mod:
        try:
            rt = mod.LuaRuntime(); print(f"[runtime] {name}"); break
        except Exception:
            pass
if rt is None:
    rt = lupa.LuaRuntime(); print("[runtime] default")

loadstring = rt.eval("function(s,n) return loadstring and loadstring(s,n) or load(s,n) end")

FILES = sorted(glob.glob("*.lua") + glob.glob("Modules/*.lua"))

# --- 1. compile ------------------------------------------------------------
fails = 0
for path in FILES:
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

# --- 2. escape audit -------------------------------------------------------
# Lua silently swallows a backslash that begins no valid escape, so the source
# "Interface\CharacterFrame\Foo" evaluates to "InterfaceCharacterFrameFoo".
# It compiles, it looks right in the editor, and the texture never loads. A
# mask texture that fails to load masks everything away rather than nothing,
# so a single mistyped path can erase every circular element in the UI. This
# has bitten this addon once; it does not get to happen twice.
VALID = set('abfnrtv\\"\'\n0123456789')
bad = 0
for path in FILES:
    for lineno, line in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        if line.lstrip().startswith("--"):
            continue
        for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', line):
            for m in re.finditer(r"\\(.)", lit):
                if m.group(1) not in VALID:
                    bad += 1
                    print(f"FAIL {path}:{lineno}: '\\{m.group(1)}' is not a Lua escape "
                          f"— the backslash will be swallowed. Double it. In: \"{lit}\"")

if bad:
    print(f"\n{bad} swallowed backslash(es)")
elif not fails:
    print("\nall files compile, all escapes intact")

sys.exit(1 if (fails or bad) else 0)
