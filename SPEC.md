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
                             + drive.gd (the gearbox of movements) and its
                             set pieces gate.gd, ether.gd, ruins.gd
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
Q quit, number keys the drive's gears (see Movement).

## Movement

Decided 2026-09-10. The Suite is a game whose loop is using the computer,
and what the void lacked was travel: three layers crawling along one
diagonal at nearly the same rate, so no parallax, a periodic lattice the
eye cannot track, and no heading or cause. The 90s cockpits (Bebop's
gates, Outlaw Star's ether, Tenchi's tree-ships, Panzer Dragoon's ruins,
Homeworld's streaks) all keep the hull still and move a mid-ground past
it at a speed the background does not share.

Movement is an interactive cutscene the pilot shifts into: `Drive`
(scenes/void/drive.gd, a child of Void) is a gearbox on the number keys.
Boot is always gear 1; the gear is never saved. Nothing cuts: speed opens
like a throttle (half a second's worth per second; hyperspace and the
warp's stop harder) and the bow swings with inertia.

**Forward flight** (2026-09-10, on Josh's note that stars sliding
diagonally made no sense for a ship moving ahead; reference: the
Starfield screensaver). The drive's heading is the bow's bearing: it
places the vanishing point on an arc 120 px around the frame's center.
`Void` turns speed into depth per second (`SPEED_SCALE` 900: at cruise a
star crosses far to near in about 25 s, in hyperspace in two) and hands
the shader the vanishing point, depth travelled and a streak length in
depth. The shader's stars are six depth slices cycling from far to near,
each a jittered grid on the far plane projected through the vanishing
point: stars are born dim near the bow and run outward, near ones fast
and far ones slow, each trailing a streak toward where it was 0.4 s ago.
Parallax lives inside the field. The lattice is the far fabric: still at
constant heading, and it slides only when the bow swings (near layer
half the lean, far layer 0.15 in its rotated space). The set pieces share
the vanishing point: the gate and tunnel converge on it, ether ribbons
run from it outward in depth, ruins fly out in depth and grow.

Two kinds of gear. A state holds until the next shift; a sequence runs
its phases and settles into cruise by itself. Any shift leaves a
sequence at once and its set piece dissolves over a second. Set pieces
are drawn, in the tree's perspective, beneath the tree.

| Gear | Movement | Built |
|---|---|---|
| 1 | Idle (state): a starry vista, very slow drift, the engine off. | 2026-09-10 |
| 2 | Cruise (state): clear parallax; opens up to 35% faster under a full core of workspace CPU. | 2026-09-10 |
| 3 | Gate (sequence, gate.gd): Bebop's astral gate far ahead grows for 9 s at constant depth speed (slow, then a rush). The ring holds the portal: a disc of deep blue (frame toward ground) with a luminous rim inside the ring and a soft halo outside, translucent far off and opaque well before the pass, so at the pass the whole frame is its blue; the tree and hull stay drawn over it. Hyperspace 12 s at 420 px/s is washed in the same blue, easing from full to a 0.35 tint over 1.5 s: rings cycling from far to near with gold beacons and the walls' rays converging on the far end, rings fading in only once wider than the clear middle; 5 s of thinning, the wash fading with it; cruise. The pace governor is asked for 60 fps throughout. | 2026-09-10 |
| 4 | Ether (state, ether.gd): Outlaw Star's currents. Ten seeded hairline ribbons running the length of the flight from near the bow out past the rim, each a slow wave (constant sway on screen) streaming past with the void, pale (one in three gold) packets running inward along them: the current carrying the ship. | 2026-09-10 |
| 5 | Ruins (state, ruins.gd): Panzer Dragoon's ancient age. Eight wireframe fragments (arch, broken ring, lattice shard, obelisk, sigil shard) appear far ahead off the bow and fly out past the rim as the ship closes on them, growing as they come, tumbling slowly, a gold node where something still burns. | 2026-09-10 |
| 6 | Warp (sequence, shader seam): Homeworld's plane of light. The drive stops over 4 s, a seam of pale light sweeps the frame along the heading over 3 s and the stars behind it are a new field (the shader hashes motes with a seed per side of the seam), the course is new (up to 45 degrees off), and the ship opens up to cruise over 3 s. The one movement that crosses the middle. | 2026-09-10 |

A change of frontmost app is a course correction: the bow leans up to
22 degrees off the default course by an angle that is the app's own, so
the same app always means the same course.

All six built 2026-09-10 under Josh's authorization of the full spec,
then rebuilt as forward flight the same evening, checked by stills from a
gear-walking probe; judged by eye in the running cockpit next. Idle-cost
bench not yet re-run: the starfield is six slices of nine hashes per
pixel where the motes were one of nine.

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
3c. Movement: the drive and its six gears (see Movement). Built
   2026-09-10; awaiting Josh's judgment by eye and a re-bench.
4. Bugs (rabbits on the failing block), garage mode (drag blocks
   between slots), warp transition.
