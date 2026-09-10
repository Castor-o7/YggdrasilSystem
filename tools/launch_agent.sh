#!/bin/sh
# Start the Yggdrasil System at login, or stop doing so.
#   tools/launch_agent.sh install
#   tools/launch_agent.sh remove
# Uses dist/YggdrasilSystem.app; run tools/build_app.sh first. Installing
# also starts it now. NERViewer has its own agent (../NERViewer/tools);
# with both installed the cockpit finds NERViewer already up and docks it,
# and with only this one it launches NERViewer itself.
set -e
cd "$(dirname "$0")/.."
LABEL=edu.pdx.josh.yggdrasil
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$(pwd)/dist/YggdrasilSystem.app/Contents/MacOS/Yggdrasil System"

case "$1" in
  install)
    [ -x "$APP" ] || { echo "build the app first: tools/build_app.sh"; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
PL
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "installed: the Yggdrasil System will start at login ($PLIST)"
    ;;
  remove)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "removed"
    ;;
  *)
    echo "usage: $0 install|remove"; exit 2
    ;;
esac
