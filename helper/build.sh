#!/bin/sh
# Build yggapps into game/bin and smoke-test it with a single sample.
# macOS compiles the Swift helper; Linux installs the Python one (it talks
# to KWin, so the smoke test needs a running KDE Plasma session).
set -e
cd "$(dirname "$0")"
mkdir -p ../game/bin
if [ "$(uname)" = "Darwin" ]; then
	swiftc -O -o ../game/bin/yggapps main.swift
else
	cp yggapps.py ../game/bin/yggapps
	chmod +x ../game/bin/yggapps
fi
line=$(../game/bin/yggapps --once)
echo "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); a=d["apps"]; assert a; print("yggapps ok:", len(a), "apps;", ", ".join("%s(%d w, %.2f cpu%s)" % (x["name"], x["windows"], x["cpu"], ", front" if x["active"] else "") for x in a))'
