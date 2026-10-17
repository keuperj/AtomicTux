# AtomicTux multiplayer

## Start the server

The server is a standalone Python application. It needs **Python 3.10+**, **OpenSSL**
on PATH, and the dependencies in `server/requirements.txt`. It does not need Godot.
From the project folder:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r server/requirements.txt
.venv/bin/python server/server.py --host  92.205.18.100 --port 8081
```

Use `--host 127.0.0.1` for access from the same machine only. `--ip` is an alias
for `--host`; IPv4 and IPv6 addresses are supported. Clients should enter the
server machine's reachable IP, **not** `0.0.0.0`. Allow the chosen TCP port through
your firewall. Access across the internet also requires a reachable public
address/port or an appropriate VPN/port-forwarding setup.

On first launch the server generates a self-signed RSA certificate and private
key in `server/certs/`. It reuses this pair on later launches, and prints its
SHA-256 fingerprint. Use `--cert-dir /path/to/private/directory` to choose a different
location. The key is created with owner-only permissions. Certificates are valid
for ten years; an expired or incomplete pair fails startup rather than silently
changing the server's identity. Back up the pair if you want clients to retain trust.
Certificate files, private keys, and Python environments are excluded from Git;
the whole server directory is excluded from Godot scanning and Android exports.

## Install on Linux with systemd

The following example targets **Ubuntu 22.04+ or Debian 12+** with systemd and
Python 3.10 or newer. Run it on the Linux machine that will host the server, with
an administrator account that can use `sudo`. Godot and a desktop environment
are not required. Other distributions need equivalent Python/venv/OpenSSL packages.

### Install dependencies and application files

Copy or clone this project onto the server and run these commands from its root
folder (replace `/path/to/AtomicTux` with your checkout path):

```sh
sudo apt update
sudo apt install python3 python3-venv python3-pip openssl ca-certificates
python3 --version
cd /path/to/AtomicTux

# Create the service account once; skip this command if it already exists.
sudo useradd --system --user-group --home-dir /var/lib/atomictux --no-create-home --shell /usr/sbin/nologin atomictux

sudo install -d -o root -g root -m 0755 /opt/atomictux/server
sudo install -o root -g root -m 0644 server/*.py server/requirements.txt /opt/atomictux/server/
sudo python3 -m venv /opt/atomictux/.venv
sudo /opt/atomictux/.venv/bin/python -m pip install -r /opt/atomictux/server/requirements.txt
```

Application files and the virtual environment belong to root. The service runs
as `atomictux` and stores its certificates separately under `/var/lib/atomictux`.
This avoids replacing the server identity when you update the application.

### Install and start the service

The ready-to-copy unit is [server/atomictux.service](../server/atomictux.service).
Install it as `/etc/systemd/system/atomictux.service`:

```sh
sudo install -o root -g root -m 0644 server/atomictux.service /etc/systemd/system/atomictux.service
sudo systemd-analyze verify /etc/systemd/system/atomictux.service
sudo systemctl daemon-reload
sudo systemctl enable --now atomictux.service
sudo systemctl status atomictux.service --no-pager
```

The unit contains:

```ini
[Unit]
Description=AtomicTux multiplayer server
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=atomictux
Group=atomictux
WorkingDirectory=/opt/atomictux
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/opt/atomictux/.venv/bin/python -u /opt/atomictux/server/server.py --host 0.0.0.0 --port 8081 --cert-dir /var/lib/atomictux/certs
Restart=on-failure
RestartSec=5
TimeoutStopSec=15
UMask=0077
StateDirectory=atomictux
StateDirectoryMode=0700
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

`StateDirectory=atomictux` creates `/var/lib/atomictux` with the service user's
ownership and keeps it writable under `ProtectSystem=strict`. The rest of the
application stays read-only. `Restart=on-failure` restarts a failed process,
subject to the start-rate limit. These settings follow the systemd
[execution environment](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html)
and [service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)
documentation.

On first start, the application automatically creates
`/var/lib/atomictux/certs/server.crt` and `server.key`. Find the fingerprint in the
journal and share it with players so they can verify their first connection:

```sh
sudo journalctl -u atomictux.service -n 80 --no-pager
sudo openssl x509 -in /var/lib/atomictux/certs/server.crt -noout -fingerprint -sha256
```

OpenSSL separates fingerprint bytes with colons; the client displays the same
hexadecimal bytes without colons. If moving an existing installation, stop the
old server and copy **both** certificate files to this directory before the first
service start. Set the directory owner to `atomictux:atomictux`, directory mode
`0700`, and both files to mode `0600` with the same owner. This preserves existing
client trust. Back up both files securely; never distribute the private key.

### Configure the bind address and firewall

The supplied unit listens on **all IPv4 interfaces, TCP 8081**. Clients use the
machine's reachable address; the current client default is **92.205.18.100:8081**.
Binding to `0.0.0.0` works even when a hosting provider maps a public address to a
private network interface. Bind directly to `92.205.18.100` only if that address
is actually assigned to the machine (`ip address` shows its local addresses).

To change the address or port, use a systemd override:

```sh
sudo systemctl edit atomictux.service
```

For example, this override explicitly selects the existing IPv4/8081 settings;
replace the `--host` or `--port` values as needed. The empty `ExecStart=` line is
required to clear the original command:

```ini
[Service]
ExecStart=
ExecStart=/opt/atomictux/.venv/bin/python -u /opt/atomictux/server/server.py --host 0.0.0.0 --port 8081 --cert-dir /var/lib/atomictux/certs
```

```sh
sudo systemctl daemon-reload
sudo systemctl restart atomictux.service
sudo ss -ltnp 'sport = :8081'
```

If using UFW, allow the selected port and check its status:

```sh
sudo ufw allow 8081/tcp
sudo ufw status
```

Also allow TCP 8081 in your hosting provider's firewall/security group, and forward
it through a router if applicable. These commands do not enable UFW; if enabling
it separately on a remote host, allow your SSH port first. The service provides
TLS itself: do not put a plain HTTP proxy in front of this port. A reverse proxy
that terminates TLS needs a matching certificate/trust setup and WebSocket upgrade
support; direct TLS access is the configuration described here.

### Operate, update, and troubleshoot

```sh
# Follow logs; Ctrl+C stops following, not the server.
sudo journalctl -u atomictux.service -f
# Stop, start, or disable automatic startup.
sudo systemctl stop atomictux.service
sudo systemctl start atomictux.service
sudo systemctl disable --now atomictux.service
```

To update, obtain the new project version and run the following from its root.
Stopping or restarting ends active matches because room state is held in memory.

```sh
sudo systemctl stop atomictux.service
sudo install -o root -g root -m 0644 server/*.py server/requirements.txt /opt/atomictux/server/
sudo /opt/atomictux/.venv/bin/python -m pip install -r /opt/atomictux/server/requirements.txt
sudo systemctl start atomictux.service
```

Leave `/var/lib/atomictux/certs` intact. If the unit file itself changes, reinstall
it and run `sudo systemctl daemon-reload` before starting. Existing overrides
continue to apply; inspect the effective configuration with
`sudo systemctl cat atomictux.service`.

If startup fails, inspect `systemctl status` and `journalctl` first:

- **Executable/module missing:** check `/opt/atomictux/.venv/bin/python` and install
  dependencies into that virtual environment, not the system Python.
- **Cannot assign requested address:** use `0.0.0.0` or an IP assigned to a local
  interface. Clients still use the reachable public/LAN address.
- **Address already in use:** check `ss`; stop a duplicate manually started server
  or choose a different port in both the unit and client.
- **Certificate errors or permission denied:** check the journal, system clock,
  and ownership of the certificate pair. Restore a valid pair from backup rather
  than deleting a key that clients already trust.
- **Start request repeated too quickly:** fix the underlying error, then run
  `sudo systemctl reset-failed atomictux.service` followed by
  `sudo systemctl start atomictux.service`.
- **Works locally but not remotely:** check the listening address, host/provider
  firewall rules, router forwarding, and the IP/port entered in the client.

## Connect and play

1. Launch `./godot.sh --game` and choose **Multiplayer**.
2. Enter your **name**, server **IP**, and **port**. New clients default to
   **92.205.18.100:8081**; saved addresses take precedence. These settings are saved.
   The client uses HTTPS for certificate discovery and WSS for gameplay on that port.
3. On first connection, compare the displayed certificate fingerprint with the
   one printed in the server terminal, then select **Trust & Connect**.
4. Select a waiting game, or enter a game name and choose **Create**. Names support
   1–20 printable characters; game names support 1–24. Player names are display
   names, not accounts, and duplicate display names are allowed.
5. The waiting room shows names, the owner, and the player count. The owner can
   start with 1–4 humans; remaining slots become AI at the chosen difficulty.
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
crates, all five upgrades, kicking/bouncing, shield grace, and difficulty settings.

Python's map RNG differs from Godot's; online clients receive the authoritative
map rather than independently generating it. The shared rules are implemented in
both runtimes, with regression tests for collisions, blasts, shields, kicking,
AI, and end conditions. Any future rules change needs updates on both sides.
Snapshots provide simple movement interpolation; client prediction/rollback is
not implemented, so high-latency connections will feel less responsive than LAN.
Room state is in memory and is lost if the server restarts.

## Tests

```sh
# Offline Python model, room lifecycle, validation, and certificate tests.
python3 -m unittest tests.test_server -v
# Real loopback TLS server + two headless Godot clients (needs local sockets).
python3 -m tests.test_network_integration
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
