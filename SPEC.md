# Yggdrasil System — Spec

The Mac desktop as the cockpit of a magic spaceship, in the register of
early-90s anime and games. Two references, with distinct jobs:

- **Yggdrasil** (Ah! My Goddess) is the world: the abstract space the
  cockpit looks out onto. Pale, severe, thin light on a deep ground; a
  lattice that drifts; a tree that is secretly a diagram; bugs that are
  literally rabbits. Spells are system calls. Errors hop.
- **The Gummi ship** (Kingdom Hearts) survives as structure only: the
  hull is built from instruments snapped into slots, and one day a garage
  mode rearranges them. Its jelly look was tried on 2026-09-09 and
  abandoned the same day (Josh: "it looks bad" against the void). The
  instruments are now **magic circles**: concentric rings of glyphs
  turning around each instrument, each ring at its own speed, every
  other ring the other way, in the void's own hairline register.

Decided 2026-09-09. Sibling of NERViewer (`../NERViewer`), which becomes
the first instrument block. Named the Yggdrasil System the same night;
the working title MagitechDesk is retired (project name, bundle id
`edu.pdx.josh.yggdrasil`, the dock file's `by`).

## Frame

1440x900 design space, scaled to cover the usable screen in desktop mode.

```
┌──────────────────────────────────────────────────────────────┐
│ ·   ·    the void: lattice, motes, slow drift         ·    ·  │
│   ( sigil )                                      ( sigil )   │
│   ( sigil )  side columns: docked sigil blocks   ( sigil )   │
│                          Yggdrasil, live, rooted on the rail │
│──┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───│
│  hull rail: a hairline with ruler ticks; the tree's root     │
└──────────────────────────────────────────────────────────────┘
```

The middle stays nearly clear: that is where real windows live. In
desktop mode the window is always on top and covers the screen, but the
mouse passthrough polygon is the hull: the rail, and each side column
only as far down as its instruments reach (tightened 2026-09-09; the
full columns had been swallowing clicks meant for windows under them).
Clicks anywhere else go straight to the desktop. The void is a canopy
you look through, not a wall.

## Principles

1. **Beautiful at idle.** Same rule as NERViewer.
2. **Real alpha, no glow pass.** Godot's glow writes no alpha and macOS
   drops it. Every halo in this project is drawn by hand, with alpha.
3. **One register.** Void, tree, rail and instruments are all hairlines
   and pale light on the same palette. Gold is reserved for what is live
   or frontmost. Nothing is chunky, nothing is saturated.
4. **The tree is the workspace.** Decided 2026-09-09: the trunk is the
   machine, one luminous node above the rail is the operating system
   (one node, never the litany of services), each branch is a running
   application with a Dock presence, each twig one of its windows. The
   frontmost app carries a gold bud; branches warm with the CPU they and
   their child processes burn; a branch grows in at launch and withers
   to a ghost at quit, so by evening the tree remembers the day. Branch
   length grows with how long the app has been open. Drawn in GDScript,
   never shaded, so every branch is addressable.

## Layout

```
YggdrasilSystem/
  SPEC.md
  screenshots/               rendered by tools/shots.tscn; judged by eye
  helper/
    main.swift               yggapps: the workspace daemon (one file, no deps)
    build.sh                 swiftc -O -o ../game/bin/yggapps main.swift
  tools/
    build_app.sh             helper + export + bundle + re-sign -> dist/YggdrasilSystem.app
    launch_agent.sh          install|remove a LaunchAgent that starts it at login
    entitlements.plist       Apple Events automation, kept through the re-sign
    terminal_zen_profile.*   builds and imports the "Yggdrasil" Terminal profile
  dist/                      built app (gitignored)
  game/
    project.godot            4.3, Forward+, transparent, canvas_items/expand,
                             theme font fonts/ui.tres
    export_presets.cfg       macOS preset for tools/build_app.sh; carries the
                             NSAppleEventsUsageDescription zen needs
    fonts/the_one_ring.ttf   dingbat font: s,t,u,v are the Ring verse in Tengwar
                             (freeware, non-commercial; see the .txt beside it)
    fonts/ui.tres            Avenir Next Condensed (system), letterspaced: every
                             label in both apps, via the theme and Palette.FONT
    fonts/display.tres       its Ultra Light cut, for the clock's numerals
    bin/yggapps              built helper (build.sh makes it)
    autoload/palette.gd      "Palette": VOID colors, breath
    autoload/pace.gd         "Pace": the frame rate governor (see Cost at idle)
    autoload/workspace.gd    "Workspace": spawns yggapps, one App record per
                             application, alive or withered; scripted day
                             as the fallback
    scripts/osa.gd           Osa: AppleScript via files in user://
    scripts/paths.gd         Paths: files outside the pck (the sibling
                             NERViewer app, tools/) found from the editor
                             or an exported app alike
    shaders/void.gdshader    lattice x2, nodes, motes, radial/bottom mask
    scenes/main.tscn/.gd     window modes, prefs, passthrough, keys
    scenes/void/             void.tscn: the shader quad + tree.gd (live)
    scenes/hull/             hull.tscn: drawn rail (hairline + ruler ticks)
                             and column slots, dock(); sigil_block.tscn:
                             SigilBlock, a magic circle (no drawn name) with a
                             Content container in the middle
    scenes/blocks/           instruments that go inside blocks: clock
    scenes/hull/nerviewer_dock.gd  measures the NERViewer sigil, writes the
                             dock file, launches NERViewer, cleans up
    scenes/hull/inscription.gd  Inscription: the verse strips rasterized near
                             display size and laid along the middle ring as
                             textured quads (replaced the text ring 2026-09-09)
    tools/shots.tscn/.gd     headless render: void_live (real apps, if the
                             helper runs), void_ground, void_overlay
    tools/bench.tscn/.gd     idle-cost bench: windowed, prefs untouched,
                             prints % of one core at a chosen frame rate
```

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path game`
Shots: `... --path game res://tools/shots.tscn`
Build: `tools/build_app.sh` (then `tools/launch_agent.sh install` to start
it at login; NERViewer has the same pair). The exported app finds the
helper beside its executable and NERViewer through `Paths.find_up`, so
the two repos only have to stay siblings.

Keys: B desktop mode, Z zen, W fake wallpaper (windowed), S screenshot,
Q quit.

## Zen

Z. Three things happen, all undone by Z again or by quitting:

1. The Dock and the menu bar auto-hide (System Events, dock preferences;
   the prior values are kept in prefs and handed back).
2. Terminal dissolves: every tab, and the default and startup profile,
   switch to the "Yggdrasil" settings set — the user's default profile
   with a fully transparent background and no blur — so the text sits on
   the void. `tools/terminal_zen_profile.sh` builds and imports that
   profile (Swift patches the archived NSColor's alpha; `open` imports
   the .terminal file); the cockpit runs it if the profile is missing.
   Terminal's title bar cannot be scripted away, so the cockpit covers
   it: scenes/void/cover.gd, drawn under the void, paints the wallpaper
   (read via System Events, aspect-fill mapped; sips converts formats
   Godot cannot load) back over the top 28 points of every Terminal
   window and a thin band (4pt outside, 3pt inside) down both sides and
   along the bottom, which hides the window's hairline border. The strips
   are still Terminal's to click and drag.
3. Over the desktop, every other on-screen window gets a hairline frame
   with corner brackets and its app's name, gold for the frontmost app
   (scenes/void/frames.gd, from the `rects` the helper reports in screen
   points; Terminal and NERViewer are exempt).

One Space, one screen, for now.

The profile handed back when zen ends is never "Yggdrasil" itself: if
that is what Terminal reports when zen begins (a restart with zen on),
the earlier answer stands, or failing that "Basic". Found 2026-09-09
after a restart had saved "Yggdrasil" as the profile to restore.

## Cost at idle

Measured 2026-09-09 on the M2, windowed 1440x900 with the live
workspace (`tools/bench.tscn`, the % of one core the cockpit's process
used over 20 s):

| frame rate | Forward+ | Mobile | Compatibility |
|---|---|---|---|
| 12 | 11% | | |
| 30 | 21% | 22% | 22% |
| 60 | 37% | | |

Linear in the frame rate, indifferent to the renderer, so Forward+ stays. Over the desktop (the screen-sized,
always-on-top window) the same frame costs about the same: 24% desktop,
21% desktop without per-pixel alpha, 23% windowed, in one later run at
12 fps. The absolute numbers drift with the machine's power state (that
later run was on a low battery and read twice the first one for the
same work), so compare within one session, never across the table. Before this the cockpit held 60 fps
whenever zen was on and 30 otherwise, and over the desktop it and the
docked NERViewer each took about 40% of a core with WindowServer
another 16% behind them, on battery.

`Pace` (autoload) owns `Engine.max_fps`. At rest it is 30, and 30 is
the floor: a 12 fps rest was tried on 2026-09-10 and read as harsh, so
below 30 the rate is not a lever for cost. What Pace manages is the
excursion above it: the zen paint asks for 60 with `Pace.stir(seconds)`
whenever the helper reports a window rect changed, for 0.75 s, so a
drag stays locked and a still desktop never pays for 60. Minimized
drops to 3. The saving against the first build is that 60 is no longer
held for as long as zen is on.

## The workspace helper

`yggapps` prints one JSON line per interval (2 s): `{"t", "interval",
"apps": [{"id", "name", "pid", "launched", "windows", "visible", "cpu",
"active", "hidden", "self"}]}`. Apps are `NSWorkspace.runningApplications`
with activation policy regular, so background services never appear.
Windows come from `CGWindowListCopyWindowInfo` with option-all (every
Space, minimized included), normal layer, at least 40px, alpha above
zero; `visible` counts the on-screen ones. No permission is needed for
counts; titles would need Screen Recording and are not read. `cpu` is a
fraction of one core over the last interval for the app and every
process descended from it (Chrome's renderers, Godot's games), from
`proc_pid_rusage` with the mach timebase applied (rusage clocks are not
nanoseconds on Apple silicon). `self` marks the app that spawned the
helper; the art layer hides it. A second timer polls on-screen window
rects at 60 Hz and prints `{"win": {"<pid>": [[x,y,w,h]]}}` only when
something moved, so the zen paint stays locked to a dragged window; the
cockpit runs at 60 fps in zen for the same reason.

## Plan

1. Void layer — done 2026-09-09, first frames in screenshots/.
1b. Live tree — done 2026-09-09: helper, Workspace autoload, tree rewired.
2. First instrument — done 2026-09-09. A Gummi jelly block was built,
   judged, and replaced by the sigil block the same day. Blocks dock by
   (side, index) in columns 18% of the frame wide; the rail is a drawn
   hairline with ticks. The clock is the first instrument.
3. NERViewer docked — done 2026-09-09. Josh's call: NERViewer stays a
   standalone app. The cockpit reserves a sigil on the right column and
   writes NERViewer's `user://dock.cfg` (`[dock] rect=Rect2i, pid`) from
   the sigil's inner disc measured in screen pixels; NERViewer polls that
   file once a second and, while it exists and the pid is alive, shows
   its core ring alone filling the rect, borderless and on top. While
   NERViewer runs, the sigil paints nothing inside its inner ring: both
   apps float at the same window level and the system may put either on
   top, so the cockpit must never smoke over the guest. The file
   is removed on exit; a dead pid counts as removed. If NERViewer is not
   running when the workspace first reports, the cockpit launches
   `../NERViewer/dist/NERViewer.app` once. Godot on macOS measures
   windows in pixels, so both apps share one coordinate system.
3b. More instruments.
4. Bugs (rabbits on the failing block), garage mode (drag blocks
   between slots), warp transition.
