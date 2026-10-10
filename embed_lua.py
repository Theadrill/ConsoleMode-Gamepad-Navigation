"""Embute gluepad.lua como string C (ASCII puro, regra do projeto)."""
import sys

src, dst = sys.argv[1], sys.argv[2]
raw = open(src, "rb").read()
try:
    text = raw.decode("ascii")
except UnicodeDecodeError as e:
    print("ERRO: gluepad.lua nao e ASCII puro: %s" % e)
    sys.exit(1)
if "\0" in text:
    print("ERRO: NUL no fonte lua")
    sys.exit(1)
esc = text.replace("\\", "\\\\").replace('"', '\\"')
lines = esc.split("\n")
with open(dst, "w", newline="\n") as f:
    f.write("/* Gerado por embed_lua.py - nao editar. */\n")
    f.write("static const char GLUEPAD_LUA_NAV[] =\n")
    for ln in lines:
        f.write('"%s\\n"\n' % ln)
    f.write(";\n")
print("OK: %s (%d bytes lua)" % (dst, len(raw)))
