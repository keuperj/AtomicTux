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
| Move | WASD / arrow keys | Right directional pad |
| Plant bomb | Space | Left gold button |
| Pause | Escape / P | Pause button / Android Back |

Movement and bomb touches work simultaneously. The game pauses when backgrounded.
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

An `Android` export preset is included for ARMv7 and ARM64, with landscape
orientation, the Compatibility renderer, immersive display, and Internet permission for multiplayer.

1. Install the **Godot 4.6 export templates** via Editor → Manage Export Templates.
2. Install **OpenJDK 17** and the Android SDK. Set Java SDK Path and Android SDK Path in Godot's editor settings.
3. For the Godot 4.6 toolchain, install Platform Tools, Build Tools **35.0.1**, and Android Platform **35**. See the [official setup instructions](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html) for the full SDK setup, including NDK/CMake if using Gradle.
4. Project → Export → Android → Export Project with debug enabled, or run:

```sh
godot --headless --path . --export-debug Android builds/AtomicTux.apk
adb install -r builds/AtomicTux.apk
```

The initial implementation was tested with Godot 4.6 on Linux. An APK has **not**
been built or tested on a physical Android device: the development environment
had Java 11 and no Android SDK/export templates. Check touch sizing, safe areas,
performance, audio, and lifecycle behavior on devices before a release.

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
synthesized effects. Android APK export/device testing remains outstanding.
