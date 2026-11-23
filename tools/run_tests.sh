#!/usr/bin/env bash
# Ejecuta tests/test_*.lua desde la raiz del repo (compila build/app.lua si existe src/main.lua).
cd "$(dirname "$0")/.." || exit 1
LUA=/c/dev/tools/lua51/lua.exe
export LUA_PATH="./?.lua;./tests/?.lua;./src/?.lua"
if [ -f src/main.lua ]; then
  python -I tools/build.py --no-tns || { echo "FALLO: build"; exit 1; }
fi
pass=0; fail=0; failed=""
for t in tests/test_*.lua; do
  [ -e "$t" ] || continue
  if "$LUA" "$t"; then pass=$((pass+1)); echo "PASS $t"
  else fail=$((fail+1)); failed="$failed $t"; echo "FAIL $t"; fi
done
echo "== Resumen: $pass ok, $fail fallo(s)${failed:+ ->$failed}"
[ "$fail" -eq 0 ]
