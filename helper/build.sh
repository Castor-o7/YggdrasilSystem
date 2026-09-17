#!/bin/sh
# Build yggapps and zenprof into game/bin; smoke-test yggapps with a
# single sample.
set -e
cd "$(dirname "$0")"
mkdir -p ../game/bin
# Without a target swiftc builds for this Mac's OS and newer only; the
# apps run on macOS 13 (the export preset's minimum), so the helpers must.
TARGET="-target arm64-apple-macos13.0"
swiftc -O $TARGET -o ../game/bin/yggapps main.swift
swiftc -O $TARGET -o ../game/bin/zenprof zenprof.swift
line=$(../game/bin/yggapps --once)
echo "$line" | python3 -c 'import json,sys; d=json.load(sys.stdin); a=d["apps"]; assert a; print("yggapps ok:", len(a), "apps;", ", ".join("%s(%d w, %.2f cpu%s)" % (x["name"], x["windows"], x["cpu"], ", front" if x["active"] else "") for x in a))'
