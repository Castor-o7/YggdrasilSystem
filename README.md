Hello! You found my weird visualizer thing, good job. I am a recent graduate that got used to the customizability of linux during college.
I have to use an M2 series Macbook for work and I wanted something very minimalist to use as a vizualizer while I code. 
I'm a big fan of those coffee shop ASMR ambience videos, and I was craving some 90's anime space vibes. Essentially the software
is a Godot 4.7 scene that sits on top of your desktop pretending to be the cockpit of a space ship. The ship visualier has 5 'gears' of motion
and 7 scenes that can be triggered via the number keys and -,=. There is a help card that can be brought up that details more of the key 
bindings within the scene. The scene has a transparency layer that is built in to hide the outer boundaries of terminal windows, that I
call 'zen mode' which can be toggled off and on. Finally, my favorite feature is the Voyage function that can be toggles via the back tick key.
The Voyage will just randomly segue from one scene to the next over a lengthy period of time.

The design of the scene itself is done with modest intentionality. The central piece of the screen is a task monitor that is a synthesis
between 'astrolabe' and 'mobile', this central 'task tree' will shift and whirl as new apps are opened and closed, highlighting the currently
selected window in a subtle way. In the upper left hand corner is a widget that is referred to as a 'glyph core' this widget displays the time,
 date etc and some flavor animation that encircles it. This can be toggled into and out of sight. As an additional but not required 'glyph core'
 widget, I have a system analytics monitor that I have taken to calling the NERViewer, which can be docked into the system upon activation. 
 So if you would like to have a subtle CPU monitor that can be placed in the HUD, that is available. 

 This visualizer has information, and accessibility in mind while trying to achieve a feel of sleek nostalgia. If you are looking for a visualizer
 that has some bells and whistles, while striving to be lightweight. If you like the idea of zooming through a nostalgiac late 90's asteroid
 belt, please feel free to give it a try. Will post pictures from the visualizer itself soon. 

## Running on macOS

What you need: the Xcode command line tools (`xcode-select --install`, for swiftc and codesign) and Godot 4.7.2 with its macOS export templates (Editor > Manage Export Templates).

Build and run:

    tools/build_app.sh                # helper + export -> dist/YggdrasilSystem.app, yggapps inside
    open dist/YggdrasilSystem.app

Autostart: `tools/launch_agent.sh install` writes a LaunchAgent (`~/Library/LaunchAgents/edu.pdx.josh.yggdrasil.plist`) and starts it now; `tools/launch_agent.sh remove` undoes it.

The first time zen runs, macOS asks once to let the Yggdrasil System control System Events and Terminal; say yes, or zen can't do its tricks. Zen auto-hides the Dock and the menu bar and dissolves Terminal.app through a "Yggdrasil" profile (made by `tools/terminal_zen_profile.sh`; the cockpit runs it on first zen if it's missing, and a Terminal window may blink by while it does). Zen off, or quitting, gives the Dock, menu bar and your Terminal profile back.

NERViewer: clone it next to this repo (`../NERViewer`) and run its `tools/build_app.sh` (and, if you like, its `tools/launch_agent.sh install`); the cockpit is meant to dock it into the right block (on macOS the sigil cannot yet see that the cockpit is alive, so it stays a window of its own until that is tested on a Mac). Without its LaunchAgent the cockpit opens `../NERViewer/dist/NERViewer.app`, else `/Applications/NERViewer.app`; with neither, the block waits.

## Running on Linux (KDE Plasma)

The same cockpit also runs on Manjaro with KDE Plasma 6 on Wayland; the macOS build is untouched.

What you need: Godot 4.7.2 with its Linux export templates (Editor > Manage Export Templates); python3 with dbus-python and PyGObject for the `yggapps` helper, which asks KWin about your windows over D-Bus; qdbus6 (qt6-tools; `qdbus-qt6` on Fedora) and kreadconfig6/kwriteconfig6 (Plasma ships them) for zen's panel and Konsole work; and Konsole as the terminal zen dissolves. On Manjaro/Arch: `pacman -S python-dbus python-gobject qt6-tools`.

Build and run:

    tools/build_app.sh                # helper + export -> dist/linux/YggdrasilSystem.x86_64
    dist/linux/YggdrasilSystem.x86_64

For development, `godot --path game` works too (run `helper/build.sh` once first; outside a Plasma session it installs the helper and skips its smoke test). `dist/linux/` holds the single binary (the pck is embedded) with the `yggapps` helper beside it.

NERViewer: clone it next to this repo (`../NERViewer`) and run its `tools/build_app.sh` (and, if you like, its `tools/launch_agent.sh install`); the cockpit docks it into the right block. Without its unit the cockpit runs `../NERViewer/dist/linux/NERViewer.x86_64`, else the `../NERViewer/game` project with `godot` from your PATH, each as a transient systemd unit of its own so it outlives the cockpit and undocks.

A note on Wayland: the cockpit runs through XWayland on purpose. Godot's native Wayland backend can't keep a window always on top or let the mouse click through it, and the overlay needs both.

Zen on Plasma swaps the macOS tricks for native ones:
- Plasma panels slide to auto-hide, and go back to exactly how they were when zen ends.
- Konsole windows dissolve: every open session switches to a "Yggdrasil" profile (a copy of your default profile with a fully transparent background, made by `tools/konsole_zen_profile.sh`), and a small KWin script takes their borders off, new windows included. Zen off, or quitting, puts your profile and borders back. A Konsole reads its profiles only when it starts, so one already running when the profile is first made (the first cockpit run, or `tools/launch_agent.sh install`) must be restarted before it can dissolve.

Autostart: `tools/launch_agent.sh install` writes a systemd user unit (`~/.config/systemd/user/edu.pdx.josh.yggdrasil.service`) tied to the graphical session and starts it now; `tools/launch_agent.sh remove` undoes it. Stopping the unit, or logging out, closes the cockpit the way Q does, so zen gives your panels and Konsole back first (the unit is ordered after plasmashell and KWin, so both are still there to take them). NERViewer has the same pair.

## Platform notes

The cockpit does the same things on both; where the desktops differ, it uses each one's own way.

- Zen's terminal: Terminal.app on macOS, Konsole on Linux. The Mac paints the wallpaper over Terminal's title bar (only in desktop mode, as the cover can't take the bar away); Plasma takes Konsole's frame off outright, and hides its toolbars and its own menu bar, which a Mac window doesn't have.
- The desktop's chrome: the Dock and menu bar auto-hide on macOS; every Plasma panel auto-hides on Linux.
- The task tree: an app with no windows open keeps its branch on both while it still runs (Finder, a tray app). Linux learns about an app from its first window, so one started straight to the tray shows up only after it opens one, and a background service's dialog (the wallpaper settings, a password prompt) leaves with its window, since macOS never lists those at all.
