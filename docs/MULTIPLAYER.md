# AtomicTux multiplayer

[Game overview](../README.md) · [Installation](INSTALL.md) · [Development](DEVELOPMENT.md)

## Start the server

The server is a standalone Python application. It needs **Python 3.10+**, **OpenSSL**
on PATH, and the dependencies in `server/requirements.txt`. It does not need Godot.
From the project folder:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r server/requirements.txt
.venv/bin/python server/server.py --host 0.0.0.0 --port 8081
```

Use `--host 127.0.0.1` for access from the same machine only. `--ip` is an alias
for `--host`; IPv4 and IPv6 addresses are supported. Clients should enter the
server machine's reachable IP, **not** `0.0.0.0`. Allow the chosen TCP port through
your firewall. Access across the internet also requires a reachable public
address/port or an appropriate VPN/port-forwarding setup.

On first launch the server generates a self-signed RSA certificate and private
key in `server/certs/`. It reuses this pair on later launches, and prints its
SHA-256 fingerprint. Use `--cert-dir server/certs` to choose a different
location. The key is created with owner-only permissions. Certificates are valid
for ten years; an expired or incomplete pair fails startup rather than silently
changing the server's identity. Back up the pair if you want clients to retain trust.
Certificate files, private keys, and Python environments are excluded from Git;
the whole server directory is excluded from Godot scanning and Android exports.

## Install on Linux with systemd

These instructions use a **user service**, so the server runs as your Linux user
from its existing checkout. Examples target Ubuntu or Debian with Python 3.10+
and systemd. Run all project commands from the project root.

### Install dependencies

```sh
sudo apt update
sudo apt install python3 python3-venv python3-pip openssl ca-certificates
python3 -m venv .venv
.venv/bin/python -m pip install -r server/requirements.txt
```

### Generate the service configuration

The following command derives the service locations from the current checkout.
It writes `builds/atomictux.service`; no username or installation directory needs
to be edited. Keep this checkout in place while the service is installed.

```sh
mkdir -p builds
python3 - <<'PY'
from pathlib import Path

project = Path.cwd()
def unit_path(path):
    value = str(path).replace('%', '%%').replace('\\', '\\\\').replace('"', '\\"')
    return '"' + value + '"'

python = unit_path(project / '.venv/bin/python').replace('$', '$$')
(project / 'builds/atomictux.service').write_text(f'''[Unit]
Description=AtomicTux multiplayer server
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory={str(project).replace('%', '%%')}
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart={python} -u server/server.py --host 0.0.0.0 --port 8081 --cert-dir server/certs
Restart=on-failure
RestartSec=5
TimeoutStopSec=15
UMask=0077
NoNewPrivileges=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
''')
PY
systemd-analyze --user verify builds/atomictux.service
systemctl --user link "$PWD/builds/atomictux.service"
systemctl --user daemon-reload
systemctl --user enable --now atomictux.service
systemctl --user status atomictux.service --no-pager
```

For startup at boot and continued operation after logout, enable lingering for
the account that owns the service:

```sh
sudo loginctl enable-linger "$USER"
```

This account must have permission to read the checkout and write `server/certs`.
The service uses the `.venv` created above. It automatically generates its
self-signed certificate and key in `server/certs` on first launch, then reuses them.
The repository also includes `server/atomictux.service` for administrators who
manage a system-wide deployment; the generated user service above is the
portable checkout-based installation described here.

### Certificates and connection settings

Find the fingerprint in the logs, or inspect the certificate:

```sh
journalctl --user -u atomictux.service -n 80 --no-pager
openssl x509 -in server/certs/server.crt -noout -fingerprint -sha256
```

OpenSSL separates fingerprint bytes with colons; the game displays the same bytes
without colons. Share the fingerprint with players for first-connection verification.
Back up **both** `server/certs/server.crt` and `server/certs/server.key` securely.
When moving an installation, stop the service and restore both files before
starting it again. Keep the directory private to the service account and never
share the private key.

The service listens on all IPv4 interfaces, TCP **8081**. Players enter the server's reachable IP,
not the bind address `0.0.0.0`. To use another bind address or port, edit the
`--host` or `--port` value in `builds/atomictux.service`, then run:

```sh
systemd-analyze --user verify builds/atomictux.service
systemctl --user daemon-reload
systemctl --user restart atomictux.service
ss -ltnp 'sport = :8081'
```

If using UFW, allow the selected port:

```sh
sudo ufw allow 8081/tcp
sudo ufw status
```

Also allow the port in your hosting provider's firewall and configure router
forwarding if needed. These commands do not enable UFW. If enabling it separately
on a remote host, allow your SSH port first. The server provides TLS itself;
a reverse proxy needs matching TLS/certificate and WebSocket upgrade settings.

### Operate and update

```sh
# Follow logs; Ctrl+C stops following, not the server.
journalctl --user -u atomictux.service -f
# Stop or start.
systemctl --user stop atomictux.service
systemctl --user start atomictux.service
# Disable automatic startup and stop.
systemctl --user disable --now atomictux.service
```

To update, stop the service, update this checkout, then run:

```sh
.venv/bin/python -m pip install -r server/requirements.txt
systemctl --user start atomictux.service
```

Keep `server/certs` intact. Restarting ends active rooms because room state is
held in memory. If you move the checkout, stop and disable the service before
moving it, then regenerate and relink the unit using `systemctl --user link --force`
and enable it again. Reload the service manager whenever its unit changes.

If startup fails, inspect `systemctl --user status` and `journalctl --user`:

- **Missing executable/module:** check `.venv/bin/python` and install requirements.
- **Cannot assign address:** bind to `0.0.0.0` or an address assigned to the machine.
- **Port already in use:** stop a duplicate server or change both server and client ports.
- **Certificate errors:** check the system clock, file ownership, and certificate pair.
  Restore a valid backup rather than deleting a key that players already trust.
- **Start request repeated too quickly:** fix the error, run
  `systemctl --user reset-failed atomictux.service`, then start it again.
- **User service manager unavailable:** log in normally as the service account
  and enable lingering; avoid running the user-service commands under `sudo`.
- **Remote clients cannot connect:** check the listening address, firewall,
  router forwarding, and the IP/port entered in the game.


## Connect and play

1. Launch `./godot.sh --game` and choose **Multiplayer**.
2. Enter your **name**, server **IP**, and **port**. New clients use a preconfigured
   default server; saved addresses take precedence. These settings are saved.
   The client uses HTTPS for certificate discovery and WSS for gameplay on that port.
3. On first connection, compare the displayed certificate fingerprint with the
   one printed in the server terminal, then select **Trust & Connect**.
4. Select a waiting game, or enter a game name and choose **Create**. Names support
   1–20 printable characters; game names support 1–24. Player names are display
   names, not accounts, and duplicate display names are allowed.
5. The waiting room shows names, the owner, and the player count. The owner can
   start with 1–4 humans; remaining slots become AI at the chosen difficulty.
   Before starting, the owner can adjust the six power-up amounts using **− / +**
   (0–20) or **Reset Power-up Defaults**. Defaults are extra bomb 6, blast range 4,
   speed 2, kicking 2, shield 4, atomic 2. Zero disables a type; other values set
   relative frequency. Everyone sees the changes. Values persist for rematches
   and ownership transfers, but each new room starts with the defaults.
6. After the round, select **Another Round** to stay in the same room, or **Game List**
   to leave. The owner can start the rematch once remaining players have chosen
   another round; undecided players are shown in the waiting room.

Games already running are excluded from the waiting-game list. Full waiting rooms
remain visible with joining disabled. The list updates when rooms change and is
scrollable. Elimination shows the two-second death sequence and then spectates the
ongoing match. It does **not** end the match for everyone else. All players receive
results when one contestant remains or the timer expires.

Online pause only pauses your input: the server and other players keep playing.
Backgrounding sends a neutral movement command. A disconnected player's slot is
controlled by AI for the remainder of the round. Ownership transfers to the next
remaining player if the owner leaves. Empty rooms are removed. Disconnected clients
return to connection setup; reconnecting creates a new identity, without reclaiming
a slot in an ongoing match.

## Connection security

All gameplay uses **WSS (WebSocket over TLS)** with TLS 1.2 or newer. The client
uses the explicitly trusted self-signed certificate and verifies the `atomictux`
certificate identity. No player name or game input is sent before this verified
connection is established.

The first connection fetches only the public certificate over an unverified HTTPS
bootstrap request. Its SHA-256 fingerprint must be compared with the server's
terminal through a channel you trust. Trust is saved per IP and port in
`user://servers.cfg`. Later connections verify the saved certificate directly;
there is no automatic fallback if the key changes. If you intentionally replace
the certificate, use **Forget saved certificate** and verify the new fingerprint.

This provides encrypted, server-authenticated transport after fingerprint
verification. There are no user accounts, passwords, persistent identities, private
rooms, or anti-abuse services in this version. Anyone who can reach the server can
join its public rooms. The server validates names and commands, limits packet size
and command frequency, limits room capacity, and owns simulation state.

## Implementation

- `server/server.py`: TLS, certificate generation, connection lifecycle, rooms,
  owner permissions, rematch readiness, and input routing.
- `server/simulation.py`: authoritative 60 Hz multiplayer simulation and AI.
- `scripts/network_client.gd`: certificate discovery/trust, WSS polling, saved
  connection preferences, and protocol messages.
- `scripts/multiplayer_ui.gd`: connection, trust, room browser, and waiting screens.
- `scripts/main.gd`: snapshot presentation, local-player mapping, online input,
  spectating, death sequence, and results.
- `scripts/arena.gd`: snapshot decoding plus the original local single-player rules.

Clients send movement/bomb intents at 20 Hz; the server applies them at 60 Hz and
sends snapshots at 20 Hz. Input older than 350 ms becomes neutral. Player identity
and slot come from the connection, not client-supplied actor IDs. No client can
submit authoritative positions, health, wins, power-ups, or board changes. The
server simulates all bots. Online rules retain bombs, chain reactions, destructible
crates, all six upgrades, kicking/bouncing, shield grace, and difficulty settings.

Python's map RNG differs from Godot's; online clients receive the authoritative
map rather than independently generating it. The shared rules are implemented in
both runtimes, with regression tests for collisions, blasts, shields, kicking,
AI, and end conditions. Any future rules change needs updates on both sides.
Players and bots have continuous, fractional positions; tiles remain the basis
for bombs, crates, pickups, and AI routes. Collision checks sweep the player's
body through its movement, including contact with flames and other contestants.
Snapshots include each actor's `position` as two floating-point coordinates in
tile units (integer coordinates are tile centers), alongside its nearest `cell`.
Players stay on grid center lines and turn at tile centers. Walls and crates
block movement from the previous center, rather than allowing an approach to
their edges. The client interpolates positions across the 50 ms snapshot interval
along those center lines, including corner turns.
Update and restart the Python server along with updated clients to use these
movement rules online; restarting ends active rooms.

Movement intents now carry two finite numeric components in `direction`, each
between -1 and 1. The server normalizes vectors longer than one to enforce a
single speed budget. Fractional and diagonal inputs select the preferred lane
by their stronger component, with the other requested lane used if blocked.
Invalid numbers, booleans, and out-of-range components are rejected. Update the
server before using analog steering in new clients. Nearby explosion events also
trigger distance-scaled handheld vibration on supported clients; the server does
not control device vibration directly.

Client prediction/rollback is
not implemented, so high-latency connections will feel less responsive than LAN.
Room state is in memory and is lost if the server restarts.

## Tests

```sh
# Offline Python model, room lifecycle, validation, and certificate tests.
.venv/bin/python -m unittest tests.test_server -v
# Real loopback TLS server + two headless Godot clients (needs local sockets).
.venv/bin/python -m tests.test_network_integration
# Multiplayer screen interactions (add --display-driver x11 without --headless for previews).
./godot.sh --headless --script tests/test_multiplayer_ui.gd
# Existing single-player and UI regressions.
./godot.sh --headless --script tests/test_arena.gd
./godot.sh --headless --script tests/test_kick.gd
./godot.sh --headless --script tests/test_shield.gd
./godot.sh --headless --script tests/test_ui.gd
```

The integration harness uses temporary certificates and settings, rejects an
untrusted TLS certificate, verifies saved trust and rejection of changed certificates, and exercises named Godot clients, room creation,
joining, owner-only start, AI filling, authoritative movement, round completion,
spectating, rematches, and leaving. It removes its temporary server afterward.

The Android preset enables Internet permission. Physical Android-device and
public-internet testing are still required; desktop loopback tests cannot verify
mobile lifecycle/network conditions or WAN latency.

Reference APIs: [Godot TLSOptions](https://docs.godotengine.org/en/4.6/classes/class_tlsoptions.html),
[Godot HTTPRequest](https://docs.godotengine.org/en/4.6/classes/class_httprequest.html), and
[websockets 14.1 asyncio server](https://websockets.readthedocs.io/en/14.1/reference/asyncio/server.html).

The client and server must both be updated for atomic bombs and the slower pace.
The server uses the room owner’s configured drop amounts (defaults: bomb 6, fire 4,
speed 2, kick 2, shield 4, atomic 2). All-zero settings disable pickup drops.
Atomic pickups arm the next successful placement once; its blast crosses the full
row and column through obstacles, without destroying permanent walls. Restart
the server after deploying `server/simulation.py`; existing rooms are not preserved.

Room messages include `powerup_amounts`. The owner can send `powerup_amount`
with a known `powerup` key and an integer `change` of -1 or 1, or `reset_powerups`.
The server validates ownership, disallows changes during play, clamps amounts to
0–20, and broadcasts the resulting room. Each match copies its room’s amounts
into simulation state, which is also included in snapshots. Update and restart
the server to enable host controls; clients disable these controls on older servers.

## Random mazes and replenishing crates

The server generates a new connected random wall layout for each round. Every
spawn and crate lies in the same non-wall region, reachable by clearing crates.
When fewer than 20% of the original crates remain, it regenerates one every two
seconds on a safe cleared crate site until the rounded-up 20% target is met.
It avoids players, pickups, bombs, fire, and predicted blasts; if no safe site is
available, it retries later. Clients receive regenerated crates in grid snapshots.

Update and restart the server with the client to use these rules and the improved
buffered turns. A disconnected player's replacement AI also uses the current
slower difficulty speeds. Restarting the server ends its active rooms.
