#!/bin/sh
# Build dist/YggdrasilSystem.app: a self-contained app with the yggapps
# helper inside it. Needs Godot 4.7.2 export templates (Editor > Manage
# Export Templates) and the command line tools for swiftc and codesign.
# Zen drives System Events and Terminal through osascript, so the bundle
# carries an Apple Events usage description (export preset) and the
# automation entitlement (tools/entitlements.plist); macOS asks once.
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
command -v godot >/dev/null 2>&1 && GODOT=godot
APP=dist/YggdrasilSystem.app

echo "-- helper"
helper/build.sh

echo "-- export"
rm -rf "$APP"
mkdir -p dist
"$GODOT" --path game --headless --export-release "macOS" "../$APP"

echo "-- bundle helper"
cp game/bin/yggapps "$APP/Contents/MacOS/yggapps"
# Adding a binary invalidates the ad-hoc signature; sign again, keeping
# the automation entitlement.
codesign --force --deep --sign - --entitlements tools/entitlements.plist "$APP"

echo "-- done: $APP"
