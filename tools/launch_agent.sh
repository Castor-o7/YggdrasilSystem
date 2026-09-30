#!/bin/sh
# Start the Yggdrasil System at login, or stop doing so.
#   tools/launch_agent.sh install
#   tools/launch_agent.sh remove
#   tools/launch_agent.sh unzen      (Linux: hand back a zen left behind)
# Uses the built app; run tools/build_app.sh first. Installing also
# starts it now. NERViewer has its own agent (../NERViewer/tools); with
# both installed the cockpit finds NERViewer already up and docks it,
# and with only this one it launches NERViewer itself.
#
# macOS: a LaunchAgent running dist/YggdrasilSystem.app.
# Linux: a systemd user unit running dist/linux/YggdrasilSystem.x86_64,
# tied to graphical-session.target so it starts once Plasma is up (with
# DISPLAY and WAYLAND_DISPLAY imported) and stops when the session ends.
# Godot dies on SIGTERM without a word, so zen would never be released
# (panels left auto-hidden, Konsole left clear and borderless); the unit
# instead stops it the way the Q key or a window close does, through
# `close` below, and systemd's SIGTERM only follows if that hangs. When
# the cockpit is killed instead (a logout where Xwayland goes first, a
# closed terminal), the helper's watchdog hands zen back from prefs
# (`unzen` below does it by hand: a SIGKILL of the whole unit, a power
# cut).
set -e
cd "$(dirname "$0")/.."
LABEL=edu.pdx.josh.yggdrasil

if [ "$(uname)" = "Linux" ]; then
  UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  UNIT="$UNIT_DIR/$LABEL.service"
  BIN="$(pwd)/dist/linux/YggdrasilSystem.x86_64"
  SELF="$(pwd)/tools/launch_agent.sh"
  case "$1" in
    install)
      [ -x "$BIN" ] || { echo "build the app first: tools/build_app.sh"; exit 1; }
      mkdir -p "$UNIT_DIR"
      # Restart=no mirrors KeepAlive false: Q quits for the session.
      # After= plasmashell and KWin: systemd stops in reverse order, so
      # when systemd stops it before them, the cockpit closes (and hands
      # the panels and Konsole frames back through them) while both are
      # still up.
      cat > "$UNIT" <<UN
[Unit]
Description=Yggdrasil System (desktop cockpit)
PartOf=graphical-session.target
After=graphical-session.target plasma-plasmashell.service plasma-kwin_wayland.service plasma-kwin_x11.service

[Service]
Type=exec
ExecStart="$BIN"
ExecStop=/bin/sh "$SELF" close \$MAINPID
Restart=no

[Install]
WantedBy=graphical-session.target
UN
      # A Konsole reads its profiles only when it starts, so make the zen
      # profile now: every Konsole opened from here on can dissolve.
      [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/konsole/Yggdrasil.profile" ] \
        || sh tools/konsole_zen_profile.sh || true
      systemctl --user daemon-reload
      systemctl --user enable --now "$LABEL.service"
      echo "installed: the Yggdrasil System will start at login ($UNIT)"
      ;;
    remove)
      systemctl --user disable --now "$LABEL.service" 2>/dev/null || true
      rm -f "$UNIT"
      systemctl --user daemon-reload
      echo "removed"
      ;;
    close)
      # The unit's ExecStop: ask KWin to close the cockpit's window, which
      # Godot hears as NOTIFICATION_WM_CLOSE_REQUEST, so main.gd saves
      # prefs and releases zen before quitting. A throwaway KWin script
      # does the closing (no xdotool/wmctrl here) and is unloaded after.
      PID=$2
      case "$PID" in ''|*[!0-9]*) exit 0 ;; esac
      Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || echo qdbus6)
      NAME="ygg_close_$PID"
      JS=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/$NAME.XXXXXX.js")
      printf 'for (const w of workspace.windowList())\n\tif (w.pid === %s && w.normalWindow && !w.transient) w.closeWindow();\n' "$PID" > "$JS"
      ID=$("$Q" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$JS" "$NAME" 2>/dev/null || echo -1)
      case "$ID" in ''|-*|*[!0-9]*) ;; *)
        "$Q" org.kde.KWin "/Scripting/Script$ID" org.kde.kwin.Script.run >/dev/null 2>&1 || true ;;
      esac
      # Give zen a few seconds to unwind; systemd sends SIGTERM after.
      i=0
      while kill -0 "$PID" 2>/dev/null && [ $i -lt 80 ]; do
        sleep 0.1; i=$((i + 1))
      done
      "$Q" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$NAME" >/dev/null 2>&1 || true
      rm -f "$JS"
      ;;
    unzen)
      # Zen handed back from prefs, as the watchdog does after a kill:
      # the panels, Konsole's profile and bars, the window frames. Refuses
      # while a cockpit is flying (its Z or Q does it).
      if [ -x "$BIN" ]; then
        exec "$BIN" --headless -- --unzen
      fi
      exec godot --path game --headless -- --unzen
      ;;
    *)
      echo "usage: $0 install|remove|unzen"; exit 2
      ;;
  esac
  exit 0
fi

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
