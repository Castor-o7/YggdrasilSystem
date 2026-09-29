#!/bin/sh
# Build the Yggdrasil System for this machine, helper included.
#
# macOS: dist/YggdrasilSystem.app, a self-contained app with the yggapps
# helper inside it. Needs Godot 4.7.2 export templates (Editor > Manage
# Export Templates) and the command line tools for swiftc and codesign.
# Zen drives System Events and Terminal through osascript, so the bundle
# carries an Apple Events usage description (export preset) and the
# automation entitlement (tools/entitlements.plist); macOS asks once.
#
# Linux: dist/linux/YggdrasilSystem.x86_64 (the pck embedded, one file)
# with the yggapps helper (a python3 script, which writes its own KWin
# script at run time) beside it, where Workspace.helper_path() looks
# first. Needs the 4.7.2 Linux export templates in
# ~/.local/share/godot/export_templates.
set -e
cd "$(dirname "$0")/.."

if [ "$(uname)" = "Linux" ]; then
  GODOT=${GODOT:-godot}
  OUT=dist/linux
  BIN=$OUT/YggdrasilSystem.x86_64
  # The editor finds its templates here; say so plainly rather than let
  # the export die with a terse "template not found".
  TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates"
  VER=$("$GODOT" --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z0-9]+)\..*/\1.\3/')
  if [ ! -f "$TPL/$VER/linux_release.x86_64" ]; then
    echo "no Linux export template at $TPL/$VER/linux_release.x86_64"
    echo "install the $VER templates (Godot: Editor > Manage Export Templates)"
    exit 1
  fi

  echo "-- helper"
  helper/build.sh

  echo "-- export"
  rm -rf "$OUT"
  mkdir -p "$OUT"
  # A failed export can still leave the bare template at $BIN; drop it
  # so launch_agent.sh never installs a binary with no game in it.
  if ! "$GODOT" --path game --headless --export-release "Linux" "../$BIN" || [ ! -x "$BIN" ]; then
    rm -f "$BIN"
    echo "export failed: no $BIN"
    exit 1
  fi

  echo "-- helper beside the binary"
  cp game/bin/yggapps "$OUT/yggapps"
  chmod +x "$OUT/yggapps"

  echo "-- done: $BIN"
  exit 0
fi

# An explicit GODOT=... wins; else godot on PATH, else the app.
[ -n "$GODOT" ] || { command -v godot >/dev/null 2>&1 && GODOT=godot || GODOT=/Applications/Godot.app/Contents/MacOS/Godot; }
APP=dist/YggdrasilSystem.app
TPL="$HOME/Library/Application Support/Godot/export_templates"
VER=$("$GODOT" --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z0-9]+)\..*/\1.\3/')
if [ ! -f "$TPL/$VER/macos.zip" ]; then
  echo "no macOS export template at $TPL/$VER/macos.zip"
  echo "install the $VER templates (Godot: Editor > Manage Export Templates)"
  exit 1
fi

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
