# Install AtomicTux

[Game overview](../README.md) · [Development](DEVELOPMENT.md) · [Host a server](MULTIPLAYER.md)

All shell commands run from the project root unless stated otherwise. Tool paths
are relative to your checkout; no particular username or checkout location is required.

## Install on an Android phone or tablet

1. Obtain `AtomicTux.apk` from your project build, or build it using the steps below.
   APKs are excluded from Git; cloning the source does not download a binary.
2. Copy the APK to your device and open it using its file manager.
3. When Android prompts, allow that file manager to install unknown apps, then
   select **Install**. You can turn that permission off again afterward.
4. Open **AtomicTux** and hold your device in landscape orientation.
5. Choose **Single Player** to configure a match, **Multi Player** to join a server,
   or **Demo** to watch four AI penguins compete.

Single Player offers **− / +** controls for each power-up (0–20). Defaults are
extra bomb **6**, blast range **4**, speed **2**, bomb kicking **2**, shield **4**,
and atomic bomb **2**. Amounts are relative drop frequencies: 6 is three times
as likely as 2 when a pickup appears. Zero disables a type. **Reset Power-up
Defaults** restores these values; your choices are saved between launches.

Keep the same signing key for updates. If Android reports a signing conflict,
use an APK signed with the original key. Uninstalling the old app also allows a
fresh install, but removes its saved settings and server trust.

## Run on desktop

Install the standard edition of **Godot 4.6** (no .NET required), obtain this
project, import `project.godot`, and press **F5**. Java and the Android SDK are
only needed when building Android packages.

On Linux x86_64, the project launcher expects the extracted Godot executable at
`tools/godot/Godot_v4.6-stable_linux.x86_64`. Download the matching Linux archive
from [Godot 4.6](https://godotengine.org/download/archive/4.6-stable/), place it in
`tools/downloads`, then run:

```sh
mkdir -p tools/godot
unzip tools/downloads/Godot_v4.6-stable_linux.x86_64.zip -d tools/godot
chmod +x tools/godot/Godot_v4.6-stable_linux.x86_64
./godot.sh --game
```

Run `./godot.sh` without arguments to open the editor. Other desktop platforms
can open `project.godot` directly in their matching Godot installation.

## Android toolchain and export

An `Android` export preset is included with landscape orientation, the Compatibility
renderer, immersive display, and Internet permission for multiplayer.

### Install the local toolchain

On Linux x86_64, install `curl`, `unzip`, and `tar` with your package manager,
then run from the project directory (the local Godot 4.6 engine must already
be installed as described in the desktop setup above):

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
setup script to refresh its configuration.

### Export the APK

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

## Play online

The game includes a preconfigured default server on port **8081**. Saved connection
settings take precedence. The same endpoint supports HTTPS certificate discovery and
secure WebSocket gameplay; you enter the IP and port separately in the game.

1. Select **Multi Player** and enter your name, server IP, and port.
2. On the first connection, compare the certificate fingerprint with the server
   operator's fingerprint, then choose **Trust & Connect**. Self-signed
   certificates are supported through this explicit trust step.
3. Join a waiting game or create one. The owner can start whenever ready;
   unused slots are filled with AI. Hosts can configure the same six power-up
   amounts on the waiting page; guests can view them. These room settings
   persist for rematches. Update the server if the controls are disabled.
4. After a round, choose **Another Round** or return to **Game List**.

Server availability depends on its operator. For your own server, see the
[Linux installation and systemd guide](MULTIPLAYER.md).

## If something goes wrong

- **Launcher says Godot is missing:** check the extracted filename and relative
  location in the desktop setup above.
- **Android export tools are missing:** run `./scripts/setup-android.sh`, accept
  the SDK licenses, then reopen Godot through `./godot.sh`.
- **USB device is unauthorized:** unlock the phone and approve its debugging prompt.
- **Cannot connect online:** check the IP, port, network access, and server status.
  A changed certificate needs verification with the operator before trusting it.
