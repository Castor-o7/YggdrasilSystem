#!/bin/sh
# Create and import the "Yggdrasil" Terminal profile (see the .swift file).
# Terminal imports a .terminal file by opening it, which also opens a
# window in that profile; that window is closed again.
set -e
cd "$(dirname "$0")/.."
mkdir -p terminal
swiftc -O -o terminal/.zenprof tools/terminal_zen_profile.swift 2>/dev/null
terminal/.zenprof terminal/Yggdrasil.terminal
open terminal/Yggdrasil.terminal
sleep 1.5
osascript -e 'tell application "Terminal"
  repeat with w in windows
    if name of current settings of selected tab of w is "Yggdrasil" then
      close w saving no
      exit repeat
    end if
  end repeat
  exists settings set "Yggdrasil"
end tell'
