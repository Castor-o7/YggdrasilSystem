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
The window stretches in canvas_items/expand, so a screen wider than
16:10 (the Dock and menu bar showing, zen off) widens the frame past
1440. Main is a Node2D, so the void's anchors bind to nothing; it
follows the viewport by hand (void.gd `_fit`), as the hull does. Until
2026-09-11 it stayed 1440 wide and stopped 136 design px short of the
right edge over the desktop; Josh caught it.

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
mouse passthrough polygon is only each instrument's disc and a 16 px
strip under the rail's hairline, somewhere to click so the keys reach
the cockpit. Clicks anywhere else go straight to the desktop. The void
is a canopy you look through, not a wall. Tightened twice: 2026-09-09
from the full columns to the columns as far down as their instruments,
and 2026-09-11 to the discs and the strip, after Josh found the
top-left column sitting over the traffic lights of most windows and the
rail band over their bottom edges, so he could not minimize them and
kept leaving zen. The polygon is one even-odd shape (macOS tests it by
ray cast): every disc is reached from the strip along a retraced,
zero-width bridge.

The HUD can be stowed (H): the hull, its instruments, and NERViewer
(hidden as an app through System Events, shown again when the HUD
returns or the cockpit quits) fade out over 0.8 s while the void and
Voyage fly on, and the click area shrinks to the strip. The tree has its
own key (T). Both persist. Josh's ask, 2026-09-11: still floating
through the void while reading email, the cockpit put away until
wanted.

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
    project.godot            4.7, Forward+, transparent, canvas_items/expand,
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
                             set pieces gate.gd, warp.gd, ether.gd, limb.gd,
                             debris.gd, station.gd, ship.gd; voyage.gd,
                             the autopilot
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

Keys: B desktop mode, Z zen, H stow the HUD, T stow the tree, W fake
wallpaper (windowed), S screenshot, Q quit, number keys the drive's gears: 1-5 states, 6-0 and -, = sequences (see
Movement), backtick Voyage on or off, tilde its next movement.

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
and far ones slow, each trailing a streak toward where it was 0.8 s ago,
the head a round bead and the tail thinning to a point, keeping its
light until near the tip (0.4 s and a fading trail until Trev's playtest,
2026-09-10: cruise did not read as faster than
idle; the frame-change measure was 0.38 idle against 0.40 cruise, and is
0.38 against 0.50 now; Josh's note after: not uniform lines, so the
bead and the taper).
Parallax lives inside the field. The lattice is the far fabric: still at
constant heading, and it slides only when the bow swings (near layer
half the lean, far layer 0.15 in its rotated space). The set pieces share
the vanishing point: the gate and tunnel converge on it, ether ribbons
run from it outward in depth, ruins fly out in depth and grow.

Two kinds of gear, and the keyboard says which (layout decided
2026-09-10 when the project was greenlit in full; fold and slingshot
retired the same night on review, replaced, and two keys added): keys 1
to 5 are states, which hold until the next shift; keys 6 to 0, then
minus and equals, are sequences, which run their phases and settle by
themselves, into cruise unless the row says otherwise (0 is gear 10,
minus 11, equals 12). Any shift leaves a sequence at once and its set
piece dissolves over a second. Set pieces are drawn, in the tree's
perspective, beneath the tree.

| Gear | Movement | Built |
|---|---|---|
| 1 | Idle (state): a starry vista, very slow drift, the engine off. | 2026-09-10 |
| 2 | Cruise (state): clear parallax, speed 48 (36 until 2026-09-10), the stars trailing; opens up to 35% faster under a full core of workspace CPU. Opening from idle the engine catches: the drive lurches to 1.8 times cruise for 1.5 s, hard, then settles (1.4 for 2 s at first; Josh wanted a proper lurch), so pressing 2 is a moment. | 2026-09-10 |
| 3 | Ether (state, ether.gd): Outlaw Star's currents. Ten seeded hairline ribbons in the palette's cool color running the length of the flight from near the bow out past the rim. The current is continuous, never an object: a slow swell of light and the ribbon's own sway run inward toward the bow at one steady pace on screen (in 1/z, so nothing whips at the rim), the stream carrying the ship. Packets (dashes, some gold) were tried first and replaced the same day: a dash is a thing, a current is not, and gold is for what is live. | 2026-09-10 |
| 4 | Nebula (state, in the shader): the pale clouds every 90s series flew through, Outlaw Star's Grave of the Dragon among them. Cloud density from three octaves of value noise on three depth slices flown through like the stars, drawn as a faint haze in the cool color with hairline contours where the density steps (a weather chart of the void), the densest cores warmed toward alarm, the stars dimmed inside the cloud; a slow drift at 22. Eases in and out over 1.5 s. Ruins (Panzer Dragoon fragments flying out in depth) held this slot earlier on 2026-09-10 and were retired the same day: Josh liked the idea but not the state. | 2026-09-10 |
| 5 | Ring passage (state, in the shader + limb.gd): Cowboy Bebop's opening through Saturn's rings, Planetes' debris belts. The ship flies just above a flat plane of particles: a hairline horizon at the bow's height with a band of haze under it, and below it a jittered world grid (3-unit cells, a quarter filled) projected with a 900 px focal length from 12 units up, each particle streaking 0.15 s of motion toward the horizon; the plane runs 250 world units per unit of depth travelled, so it rushes under the ship at cruise. Thinner across the lower middle so the tree stays legible. The planet's limb, off the bow's high side: a dark disc that dims the stars, a hairline limb with bands of atmosphere inside and a haze line outside, still as a planet is. Speed 44. Eases in and out over 1.5 s. | 2026-09-10 |
| 6 | Gate (sequence, gate.gd): Bebop's astral gate far ahead grows for 9 s at constant depth speed (slow, then a rush). The ring holds the portal: a disc of deep blue (frame toward ground) with a luminous rim inside the ring and a soft halo outside, translucent far off and opaque well before the pass, so at the pass the whole frame is its blue; the tree and hull stay drawn over it. Hyperspace 12 s at 420 px/s is washed in the same blue, easing from full to a 0.35 tint over 1.5 s: rings cycling from far to near with gold beacons and the walls' rays converging on the far end, rings fading in only once wider than the clear middle; 5 s of thinning, the wash fading with it; cruise. The pace governor is asked for 60 fps throughout. | 2026-09-10 |
| 7 | Warp (sequence, shader seam + warp.gd): Homeworld's hyperspace, seen from the bow. The drive stops over 4 s while a point ahead is opened: a gold point brightens at the vanishing point and five hairline rings converge on it from the frame's edge, each starting a little after the last and closing tighter (warp.gd). Then the jump, 3 s: new space blooms out of the point, the seam a ring of pale light growing from the vanishing point past the farthest corner with the new star field inside it (the shader hashes motes with a seed per side of the seam, measured from the point), while the drive spikes to 2400 for 1.2 s so the stars stretch into radial streaks toward the point, then falls dead still in the new field. The course is new (up to 45 degrees off) and the ship opens up to cruise over 3 s. The one movement that crosses the middle. Reworked 2026-09-10 on review: the first cut's plane of light wiping across the frame read as a scan, with no visible cause and nothing that jumped. | 2026-09-10 |
| 8 | Debris passage (sequence, debris.gd): Star Wars' asteroid field, Star Fox 64's Meteo, Outlaw Star's wrecks. Fragments come out of the vanishing point and stream past on every side: dark hairline polygons that hide the stars behind them, tumbling slowly, one lit facet each, a pool of 40 respawning far ahead as the phase's density allows, the middle kept clear. Over 5 s the first appear and the drive eases to 24; for 14 s the field is full and the bow weaves to thread it, a new lean of up to 25 degrees every 3 s or so, alternating sides, turning hard; over 5 s the field thins and the drive opens to cruise. Replaced the fold 2026-09-10 (the gate already had the portal). | 2026-09-10 |
| 9 | Ether squall (sequence, in ether.gd): Outlaw Star's currents turned rough. The ribbons come in and over 6 s darken, thicken and sway three and a half times as far with a faster shiver riding the sway, the flow quickening; for 12 s they thrash, hairline discharges arc between neighboring ribbons (dim, a third of a second each, never a flash), the bow is shoved up to 20 degrees off course every 2 s or so and fights back, and the drive surges and sags around ether's 60; over 6 s it clears. Settles into ether (gear 3), not cruise: the squall passes and the ship is in calm current. Replaced the slingshot 2026-09-10 (retired on review: nobody could tell what it was). | 2026-09-10 |
| 0 | Arrival (sequence, station.gd; key 0 is gear 10): Bebop's port approaches, the Nautilus coming home. A gold light on its own bearing, a little off course, resolves into a station over 7 s of sighting as the drive eases to 30; over 24 s of approach the bow bends onto the port's bearing and the drive eases to a crawl as the docking arm comes down to the bow; over 6 s of berth the ship stops dead and the port answers: the arm's five guide lights come up one by one, hub to cradle, then the cradle's pair. Structure: a hub with spokes, a turning dashed ring, an outer ring with dashes and four gold running lights, two long spars with windows, the arm and its cradle around the bow, kin to the hull's own instruments. Then the drive settles into idle, berthed: speed zero, the stars holding, no course corrections, the station ahead until the next shift. The only sequence that ends a voyage. Reworked 2026-09-10 on review: the first cut parked the station overhead with the stars still sliding. | 2026-09-10 |
| - | Departure (sequence, station.gd; the minus key is gear 11): the mirror of arrival, and the only sequence with a condition: it fires from a berth only (idle, berthed) and the key does nothing otherwise, since anything else would invent a port we were never at. Over 6 s of cast-off the port's lights go down, the cradle's pair first, then the guides cradle to hub; over 8 s under way the drive opens to a crawl and the station grows and slides up out of the frame, passed beneath (Bebop's leaving-port shot); over 6 s the stars streak up to cruise. | 2026-09-10 |
| = | The great ship (sequence, ship.gd; the equals key is gear 12): Bebop's colony liners, Yamato, Macross. A hull far bigger than ours overtakes from behind on a parallel course, below and to one side (chosen at random), so it enters from the corner close and huge, converging on the vanishing point as any parallel course must. Over 8 s its forward hull slides in; for 14 s it passes, gaining 0.3 depth a second, six deep, its stern clearing the frame's edge at the end; over 8 s it pulls ahead and dwindles into the point. A hairline silhouette in the tree's perspective: spine, keel and deck lines with ribs, a bridge tower, fins at the stern, windows on the breath, gold running lights bow and stern and on the tower, the engines' glow. Our course and speed never change; the middle is dimmed for it, not cut. The scale is the show. | 2026-09-10 |

### Voyage

Voyage is the autopilot (scenes/void/voyage.gd, a child of Void):
with it on, the ship works the gearbox itself in the grammar the
movements were built in, so the void travels all day with the keys
untouched. Proposed by Josh 2026-09-10, built the same night.

Backtick toggles it. Tilde ends the current movement now and lets Voyage
choose the next. Any gear key takes the helm: Voyage ends and the gear
runs; backtick resumes. Voyage does not survive a restart: boot is idle,
drifting, whatever was on before.

The grammar, with cruise as the spine:

- A leg is a state held for 6, 9 or 12 minutes, chosen per leg: cruise
  (weight 4), ether (3), nebula (2), ring (2), an idle drift (1). Never
  the same state twice running.
- Leaving a leg there is a 60 percent chance of a passage first: the
  gate (3), warp (2), debris (3), the great ship (2), never the same one
  twice running. Every passage lands in cruise, then the next leg.
- An ether leg has a 50 percent chance of a squall, decided when the leg
  begins and placed in its middle third. It clears back into ether and
  the leg carries on.
- After 45 to 90 minutes under way the next leg is a port call: arrival,
  2 to 3 minutes berthed, departure, then the clock resets.
- Course corrections from the frontmost app work as ever: Voyage steers
  the gearbox, not the bow.

Nothing is drawn for it. Every choice is printed with its reason
(`voyage: leg, ether for 9 min, squall at 4:12`), so the log shows it
think. If Voyage is switched on mid-sequence it waits for the settle;
otherwise the first leg begins two seconds in.

A change of frontmost app is a course correction: the bow leans up to
22 degrees off the default course by an angle that is the app's own, so
the same app always means the same course.

Nothing in the shader may run on an accumulator it does not wrap
exactly. Found 2026-09-10 as a frame cut in the nebula: the clouds ran
on the stars' travel at 0.7 of its rate, so its wrap at 1.0 was not
theirs, and every cloud slice jumped 0.3 in depth at once (the frame
across the wrap differed 23 times more than an ordinary pair; after the
fix, the same). The clouds now have their own travel. The same fix
covered the engine's TIME, which rolls over hourly: every rhythm (the
stars' twinkle, the nebula's drift) now runs on a clock Void wraps on a
period they all divide (PULSE_BASE), and the ring plane wraps on a
multiple of its cell.

All six built 2026-09-10 under Josh's authorization of the full spec,
then rebuilt as forward flight the same evening, checked by stills from a
gear-walking probe, then judged by eye by Josh and reviewed; the review
rework (arrival, warp, the retired gears, the added keys) and Voyage
followed the same night. Idle-cost re-bench 2026-09-10 with the full
void (starfield, nebula, ring plane, seam): 24.6% windowed, 24.7% over
the desktop, both holding 30 fps; the same as before the starfield, so
the desktop app was rebuilt that night.

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

Re-measured 2026-09-10 with the full void (starfield, nebula, ring
plane, warp seam) at 30: 24.6% windowed, 24.7% over the desktop.

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
3d. Living with it: the click area cut to the discs and the rail strip,
   the HUD and the tree stowable (H, T). Built 2026-09-11 on Josh's
   brain dump of the day's obstacles.
3c. Movement: the drive, its twelve gears and Voyage (see Movement).
   Built, reviewed, re-benched and shipped to the desktop 2026-09-10.
4. Bugs (rabbits on the failing block), garage mode (drag blocks
   between slots), warp transition.
