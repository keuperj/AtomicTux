# Developing AtomicTux

[Game overview](../README.md) · [Installation](INSTALL.md) · [Multiplayer internals](MULTIPLAYER.md)

## Set up the project

Use **Godot 4.6**, standard edition, with the Compatibility renderer. See the
[installation guide](INSTALL.md) for the local engine, Java 17, Android SDK,
export templates, signing, and phone installation. All commands here run from
the project root. Installed tools and generated builds are excluded from Git.

The project currently has one arena theme with random connected mazes, up to four contestants, local solo
play, an AI-only demo, and server-hosted online rooms. The game has been tested
on real Android hardware.

## Controls and presentation

| Action | Desktop | Android |
| --- | --- | --- |
| Move | WASD / arrow keys | Right joystick: hold and slide |
| Plant bomb | Space | Left gold button |
| Pause | Escape / P | Pause button / Android Back |

Touch the right joystick, then keep your finger down and slide to steer. Movement
continues while held, even when your finger slides beyond the ring. Return to the
center to stop temporarily or lift to release. The joystick accepts every clock
angle: 12 o'clock requests up, 3 requests right, and intermediate angles prefer
the stronger component. If that lane is blocked, the other requested direction
is tried. Keyboard directions can also be combined. Another finger can drop
bombs with the left button simultaneously.

All contestants move smoothly along grid center lines, including AI and online
players. Tux stays centered across each corridor, turns only at tile centers,
and stops at the center of the last clear tile before a wall or crate. A turn
requested between centers is buffered until the next center; reversing along
the current lane responds immediately. Releasing the joystick stops along the
center line. Diagonal input never cuts corners or increases the speed budget.
Bombs occupy the nearest tile, and body collisions still apply to bombs, other
players, and flames. Online animation follows the same centered corner paths.
The joystick has a larger ring and touch area for small phone screens.
The game pauses when backgrounded and clears held touches.

Nearby explosions trigger a short vibration on supported phones and tablets.
Feedback scales with distance to the nearest blast tile (within three tiles),
with stronger pulses for closer blasts. Chain reactions are rate limited;
backgrounded games and spectators do not vibrate. Android exports include the
VIBRATE permission. Unsupported devices simply play without haptic feedback.

The landscape layout fills phone and tablet aspect ratios without stretching
the artwork. The arena scales to the available space, controls anchor near the
screen edges, and Android safe-area insets keep them clear of cutouts. Both
landscape orientations are supported.

Sound effects use cached variations of muted impacts, low explosion rumble,
glass-like pickups, and a soft shield impact. Effects overlap without cutting
each other off; rapid chain explosions are limited to avoid excessive loudness.
Difficulty, sound preference, and lifetime wins are saved in Godot's `user://` directory.

## Rules

- One human versus one to three bots; survive to be the last penguin standing.
- Bombs explode after **3.2 seconds**, with a visible fuse ring. Your own blast is lethal.
- Ordinary cross-shaped blasts stop at solid walls and the first crate. Bombs trigger chain reactions.
- Crates can reveal upgrades: a **bomb-plus** adds bomb capacity, a **flame** extends fire range, a **running boot** increases speed, a **boot kicking a bomb** grants Bomb Kick, a **shield** absorbs one explosion hit, and a gold **atom** arms one full-row-and-column bomb.
- **Shield:** holds one charge (extra pickups do not stack). The first fire hit consumes it and gives **0.75 seconds** of protection from lingering flames and overlapping blasts. Afterward, another hit is lethal unless you collect a new shield. The bubble and HUD show protection; all upgrades reset each round.
- **Bomb Kick:** walk into a bomb to send it sliding at about 11 tiles/second. It bounces off walls, crates, other bombs, and contestants until its original fuse expires. Fire triggers it immediately. A kick needs a free tile beyond the bomb; the ability lasts for the round.
- Pickups become accessible after the fire clears. Fire lasts **0.65 seconds**.
- You may leave a bomb you just planted, but cannot walk back through it without Bomb Kick.
- On elimination, the lethal blast stays visible for a two-second Tux death animation before the next-game dialog appears.
- A round ends immediately on your elimination or when one survivor remains. The **2:30** timer ends unresolved rounds in a draw.
- Relaxed bots take **0.57 seconds per tile** and wait at least **5.4 seconds** between bomb placements. Normal and Fierce take **0.28 / 0.23 seconds per tile**. Movement is continuous at every difficulty; all bots use the same routing and escape logic.

## Tests and source layout


```sh
# Import resources and register script classes on a clean checkout.
godot --headless --editor --path . --quit
# Simulation rules, AI escape behavior, and seeded full-match tests.
godot --headless --path . --script tests/test_arena.gd
# Shield pickup, single-use protection, lingering flames, and reset.
godot --headless --path . --script tests/test_shield.gd
# Bomb kicking, bouncing, fuse behavior, and Relaxed AI pacing.
godot --headless --path . --script tests/test_kick.gd
# Menu, touch, pause, backgrounding, and replay integration tests.
godot --headless --path . --script tests/test_ui.gd
# Continuous touch input, responsive layout, and cached audio effects.
./godot.sh --headless --script tests/test_mobile.gd
# Fractional movement, stopping, turns, swept collisions, and AI waypoints.
./godot.sh --headless --script tests/test_motion.gd
# Clock-angle steering, diagonal speed/collisions, and explosion haptic requests.
./godot.sh --headless --script tests/test_analog.gd
# Capture desktop-rendered phone/tablet previews and WAV sound samples in builds/.
./godot.sh --script tests/test_mobile.gd
# Run UI tests with rendering; saves builds/menu.png and builds/arena.png.
godot --path . --script tests/test_ui.gd
```

- `scripts/arena.gd`: seeded match state, collision, bombs, fire, upgrades, win conditions.
- `scripts/bot.gd`: breadth-first routing, blast forecasts including chains, and escape checks before bombing.
- `scripts/main.gd`: fixed-step game loop, presentation, input, menus, settings, and particles.
- `scripts/sound.gd`: synthesized bomb and pickup effects.
- `assets/art/tux.png`: generated transparent mascot used in the title and arena.
- [Artwork provenance](ART.md): generation prompt and asset provenance.

Additional checks for the setup page, atomic bombs, and multiplayer:

```sh
./godot.sh --headless --script tests/test_setup.gd
./godot.sh --headless --script tests/test_atomic.gd
./godot.sh --headless --script tests/test_multiplayer_ui.gd
.venv/bin/python -m unittest tests.test_server -v
.venv/bin/python -m tests.test_network_integration
```

Install the Python dependencies using the [server guide](MULTIPLAYER.md) before
running Python tests. The integration test needs local sockets and the local Godot
binary. It uses temporary certificates and settings rather than your saved identity.

Local gameplay rules live in `scripts/arena.gd`; online gameplay rules live in
`server/simulation.py`. Keep both implementations and their regression tests in
sync when changing movement, power-ups, bomb behavior, or AI. See the
[multiplayer implementation notes](MULTIPLAYER.md#implementation) for the protocol,
authority model, certificate handling, and network testing.

## Refresh README screenshots

The committed screenshots show the actual desktop-rendered game at 1280 × 800.
The arena image uses a seeded match with AI driving the player slot; it is not a mockup.
Run with a graphical display:

```sh
./godot.sh --script scripts/capture-screenshots.gd
```

This writes `landing.png`, `arena.png`, and `single-player.png` into
`docs/screenshots`. Review the images before committing. The screenshot folder
is excluded from Godot imports and `docs` is excluded from Android exports.

## Balance and atomic bombs


Human movement takes 0.23 seconds per tile (about 26% slower), with a 0.15-second
minimum after speed upgrades. Bomb fuses last 3.2 seconds; kicked bombs advance
every 0.09 seconds. AI movement and Relaxed bomb delays are slower too.

Crates retain a 38% pickup chance. With all types enabled, drop weights are
extra bomb 10, blast range 3, speed 1, kick 3, shield 3, atomic 2: about 45%
extra bombs and 5% speed in demo play. Solo and multiplayer hosts use configurable amounts
from 0–20, with defaults bomb 6, fire 4, speed 2, kick 2, shield 4, atomic 2.
These are relative weights, not guaranteed counts per round. Zero-weight types
are excluded; all zero disables drops. The 38% per-crate chance stays unchanged.
Solo amounts are saved separately. Multiplayer rooms keep their own amounts
across rematches and ownership changes; the server enforces host-only edits.
Existing enabled/disabled settings migrate to default amounts or zero.

The gold atom-and-cross pickup arms **one atomic bomb**. Your next successful
bomb placement consumes it; failed placements do not. Multiple pickups do not
stack. Its explosion reaches every playable tile in its row and column, passing
through crates, bombs, and permanent walls. Crates break and bombs chain-react;
permanent walls stay intact. Shields still absorb a hit. AI escape planning
accounts for the full blast. The gold icon identifies an armed atomic bomb and
the HUD indicates when one is ready. Demo includes this sixth pickup.

Update and restart the Python multiplayer server alongside this client version
to apply the same balance and atomic-bomb rules online.

## Joystick calibration, maze generation, and crate regeneration

The joystick uses a 14-unit radial dead zone in the logical 1280 × 800 layout.
Within roughly 14 degrees of a cardinal direction, the smaller component is
filtered out to tolerate thumb drift. Other angles retain proportional input.
All directions use the same sensitivity. Between tile centers, a dominant
perpendicular turn continues toward the next center rather than reversing due
to a small opposing component; deliberate reversal along the current lane is
still immediate. Safe-area and viewport scaling apply before input calibration.

Both simulations build a seeded random wall layout, accepting an interior wall
only if all remaining non-wall cells stay connected. Borders remain solid and
all four spawn areas retain open escape space. Crates occupy a subset of that
connected floor: opponents and every crate can be reached by clearing crates;
permanent walls never isolate a pocket. Godot and Python use their own RNGs;
multiplayer clients receive the server's map through snapshots.

Each round records its starting crate count and original crate sites. Below
20% of that count, one crate returns every two seconds until the rounded-up
20% target is reached. Candidates must be cleared original sites, outside active
fire and forecast bomb danger, without bombs or pickups, and more than two tiles
from every living actor. If no safe site exists, regeneration waits and retries.
It never runs after a round ends. Regenerated crates use the same configured
pickup amounts as other crates. Online snapshots distribute the new grid.

```sh
./godot.sh --headless --script tests/test_maze.gd
.venv/bin/python -m unittest tests.test_server -v
```

These checks cover connectivity and layout variation across 50 seeds, crate
thresholds and protected sites, all four noisy turn directions, and touch
coordinate conversion across phone/tablet aspect ratios.
