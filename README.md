# AtomicTux

Little penguins. Big chain reactions.

An open-source, single-player and online multiplayer bomb arena game built with **Godot 4.6**, designed
for landscape Android phones and also playable on desktop. Inspired by classic
Bomberman gameplay, with original code, generated Tux-inspired artwork, and a
teal-and-copper arena. Released under the MIT license.

## Play

Godot 4.6 for Linux x86_64 is installed locally in `tools/godot/`.
Run `./godot.sh` to open this project in the editor, or `./godot.sh --game`
to play directly. The launcher also accepts Godot CLI options, such as
`./godot.sh --headless --script tests/test_arena.gd`. The binary is excluded
from Git and Godot's resource scan; fresh checkouts need their own engine installation.

1. Install [Godot 4.6](https://godotengine.org/download/archive/4.6-stable/) (standard edition; no .NET needed).
2. Import `project.godot` and press **F6** with `scenes/main.tscn` open, or **F5**.
3. Choose AI difficulty on the title screen and select **Play Solo**.

Command line: `godot --path .`

| Action | Desktop | Android |
| --- | --- | --- |
| Move | WASD / arrow keys | Right joystick: hold and slide |
| Plant bomb | Space | Left gold button |
| Pause | Escape / P | Pause button / Android Back |

Touch the right joystick, then keep your finger down and slide to steer. Movement
continues while held, even when your finger slides beyond the ring. Return to the
center to stop temporarily or lift to release. Movement follows the arena's four
grid directions. Another finger can drop bombs with the left button simultaneously.
The game pauses when backgrounded and clears held touches.

The landscape layout fills phone and tablet aspect ratios without stretching
the artwork. The arena scales to the available space, controls anchor near the
screen edges, and Android safe-area insets keep them clear of cutouts. Both
landscape orientations are supported.

Sound effects use cached variations of muted impacts, low explosion rumble,
glass-like pickups, and a soft shield impact. Effects overlap without cutting
each other off; rapid chain explosions are limited to avoid excessive loudness.
Difficulty, sound preference, and lifetime wins are saved in Godot's `user://` directory.

## Rules

- One human versus three bots; survive to be the last penguin standing.
- Bombs explode after **2.4 seconds**, with a visible fuse ring. Your own blast is lethal.
- Cross-shaped blasts stop at solid walls and the first crate. Bombs trigger chain reactions.
- Crates can reveal upgrades: a **bomb-plus** adds bomb capacity, a **flame** extends fire range, a **running boot** increases speed, a **boot kicking a bomb** grants Bomb Kick, and a **shield** absorbs one explosion hit.
- **Shield:** holds one charge (extra pickups do not stack). The first fire hit consumes it and gives **0.75 seconds** of protection from lingering flames and overlapping blasts. Afterward, another hit is lethal unless you collect a new shield. The bubble and HUD show protection; all upgrades reset each round.
- **Bomb Kick:** walk into a bomb to send it sliding at about 15 tiles/second. It bounces off walls, crates, other bombs, and contestants until its original fuse expires. Fire triggers it immediately. A kick needs a free tile beyond the bomb; the ability lasts for the round.
- Pickups become accessible after the fire clears. Fire lasts **0.65 seconds**.
- You may leave a bomb you just planted, but cannot walk back through it without Bomb Kick.
- On elimination, the lethal blast stays visible for a two-second Tux death animation before the next-game dialog appears.
- A round ends immediately on your elimination or when one survivor remains. The **2:30** timer ends unresolved rounds in a draw.
- Relaxed bots move every **0.42 seconds** and wait at least **4 seconds** between bomb placements. Normal and Fierce retain their **0.21 / 0.17 second** movement intervals. All bots use the same routing and escape logic.

## Android export

An `Android` export preset is included with landscape orientation, the Compatibility
renderer, immersive display, and Internet permission for multiplayer.

### Local Linux installation

On Linux x86_64, install `curl`, `unzip`, and `tar` with your package manager,
then run from the project directory (the local Godot 4.6 engine must already
be installed as described above):

```sh
./scripts/setup-android.sh
```

The script downloads Java 17, Android command-line tools, Platform Tools,
Build Tools **35.0.1**, Platform **35**, and Godot 4.6 Android export templates.
Read and accept the Android SDK licenses when prompted. Internet access is
required; completed downloads and installed tools are reused on subsequent runs.
No root access or Android Studio is needed. This setup uses the existing
non-Gradle APK preset; NDK and CMake are unnecessary for that workflow.
See [Godot's Android setup reference](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)
for other export workflows.

Everything is installed inside this checkout and excluded from Git and Godot's
resource scan:

| Component | Project-relative path |
| --- | --- |
| Java SDK | `tools/jdk-17` |
| Android SDK | `tools/android-sdk` |
| Android export templates | `tools/godot-data/godot/export_templates/4.6.stable` |
| Godot editor settings and debug keystore | `tools/config` |
| Download cache | `tools/downloads` |

The installer sets Godot's **Export → Android → Java SDK Path**, **Android SDK
Path**, and **Debug Keystore** automatically. The launcher also supplies debug
signing credentials to the export preset. Always open this installation with
`./godot.sh`: the launcher sets the local Java/Android environment and isolates
Godot's configuration and data from other projects. Game preferences and saved
server trust used through this launcher also live under `tools/godot-data`;
previous global preferences are not migrated. Close an already-open editor and
reopen it through the launcher after setup. If you move the checkout, rerun the
setup script to refresh its absolute paths.

For this checkout the SDK paths are:

```text
/home/keuper/Projekte/AtomicTux/tools/jdk-17
/home/keuper/Projekte/AtomicTux/tools/android-sdk
```

### Build and install on a phone

Choose **Project → Export → Android → Export Project** with **Export With Debug**
enabled, or run:

```sh
mkdir -p builds
./godot.sh --headless --editor --quit
./godot.sh --headless --export-debug Android builds/AtomicTux.apk
```

Copy `builds/AtomicTux.apk` to the phone and open it in its file manager; allow
installation from that file manager when Android prompts. Alternatively, enable
USB debugging in the phone's Developer options, connect it with a data-capable
USB cable, approve the debugging prompt, and run:

```sh
./tools/android-sdk/platform-tools/adb devices
./tools/android-sdk/platform-tools/adb install -r builds/AtomicTux.apk
```

A debug APK has been exported and its signature verified with this local toolchain.
Physical Android-device testing is still outstanding. Check touch sizing, safe
areas, performance, audio, networking, and lifecycle behavior before a release.
Keep `tools/config/debug.keystore` to install future debug builds as updates.

The included preset produces a debug APK after toolchain setup. Play Store
publishing needs a release keystore and an AAB/Gradle export configuration.
Keystores and credentials are excluded from version control.

## Development and tests

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
- `docs/ART.md`: generation prompt and asset provenance.

## Online multiplayer

Start the Python server, then choose **Multiplayer** in the game:

```sh
python3 -m pip install -r server/requirements.txt
python3 server/server.py --host 0.0.0.0 --port 8081
```

The default client address is **92.205.18.100:8081**; previously saved addresses
take precedence. Enter your name, server IP, and port. On first connection, verify the certificate
fingerprint shown in the server terminal. Browse or create a waiting game; the
owner can start with any number of players and AI fills the remaining slots.
After each round, stay for another round or return to the game list.

The server automatically generates and reuses self-signed TLS certificates.
See [multiplayer setup and protocol notes](docs/MULTIPLAYER.md) for installation,
certificate trust, disconnect behavior, testing, and deployment details.

Current scope: one arena theme, four contestants, single-player or server-hosted
online rooms, five power-ups, generated penguins with procedural animation, and
synthesized effects. Physical Android-device testing remains outstanding.
