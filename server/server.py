#!/usr/bin/env python3
"""Run: python3 -m server.server --host 0.0.0.0 --port 8081."""
import argparse
import asyncio
import contextlib
import hashlib
import http
import ipaddress
import json
import logging
import os
from pathlib import Path
import secrets
import ssl
import subprocess
import time
import tempfile

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed
try:
    from .simulation import Match, DIRS
except ImportError:
    from simulation import Match, DIRS

LOG = logging.getLogger('atomictux')

def certificates(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    cert, key = directory/'server.crt', directory/'server.key'
    if cert.exists() != key.exists():
        raise RuntimeError('Incomplete certificate pair; restore it or choose a new --cert-dir.')
    if not cert.exists():
        # No shell interpolation, private output permissions from the start.
        old_mask = os.umask(0o077)
        try:
            with tempfile.TemporaryDirectory(dir=directory) as temp:
                config = Path(temp)/'openssl.cnf'
                config.write_text("[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n"
                                  "[dn]\nCN=atomictux\n[ext]\nsubjectAltName=DNS:atomictux\n"
                                  "basicConstraints=critical,CA:TRUE\n"
                                  "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\n"
                                  "extendedKeyUsage=serverAuth\nsubjectKeyIdentifier=hash\n"
                                  "authorityKeyIdentifier=keyid:always\n",encoding='ascii')
                subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes',
                                '-keyout', str(Path(temp)/'key'), '-out', str(Path(temp)/'cert'),
                                '-days', '3650', '-sha256', '-config', str(config)],
                               check=True, capture_output=True)
                (Path(temp)/'key').replace(key)
                (Path(temp)/'cert').replace(cert)
        finally:
            os.umask(old_mask)
    key.chmod(0o600)
    subprocess.run(['openssl','x509','-in',str(cert),'-checkend','0','-noout'], check=True, capture_output=True)
    subprocess.run(['openssl','verify','-CAfile',str(cert),str(cert)], check=True, capture_output=True)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    pem = cert.read_text(encoding='ascii').replace('\r\n','\n')
    return context, pem

class Client:
    def __init__(self, ws):
        self.ws, self.id, self.name, self.room = ws, secrets.token_hex(8), '', None
        self.queue = asyncio.Queue(maxsize=64)
        self.tokens, self.token_time = 120., time.monotonic()
        self.direction, self.bomb, self.input_time = (0,0), False, 0.

    def send(self, message):
        try: self.queue.put_nowait(json.dumps(message, separators=(',',':'), ensure_ascii=False))
        except asyncio.QueueFull:
            # A slow peer must never stall a room or another peer.
            asyncio.create_task(self.ws.close(1008, 'Client too slow'))

    async def writer(self):
        try:
            while True:
                await asyncio.wait_for(self.ws.send(await self.queue.get()), timeout=5)
        except (ConnectionClosed, TimeoutError):
            await self.ws.close(1008, 'Connection stalled')

class Room:
    def __init__(self, owner, name, difficulty):
        self.id, self.name, self.owner = secrets.token_hex(4), name, owner.id
        self.members, self.ready, self.slots = {owner.id: owner}, {owner.id: True}, {}
        self.state, self.difficulty, self.match = 'waiting', difficulty, None
        self.task, self.round = None, 0

    def public(self):
        return dict(id=self.id, name=self.name, owner=self.owner, state=self.state,
                    difficulty=self.difficulty, round=self.round,
                    players=[dict(id=c.id, name=c.name, ready=self.ready[c.id]) for c in self.members.values()])

class GameServer:
    def __init__(self, pem='', round_seconds=150):
        self.pem, self.round_seconds = pem, round_seconds
        self.clients, self.rooms = {}, {}

    def rooms_message(self):
        return dict(type='rooms', rooms=[r.public() for r in self.rooms.values() if r.state == 'waiting'])

    def broadcast_rooms(self):
        msg = self.rooms_message()
        for c in self.clients.values():
            if c.name and c.room is None: c.send(msg)

    def broadcast_room(self, room):
        for c in room.members.values(): c.send(dict(type='room', room=room.public()))
        self.broadcast_rooms()

    def leave(self, client, notify=True):
        room = client.room
        client.room, client.direction, client.bomb = None, (0,0), False
        if room:
            room.members.pop(client.id, None)
            room.ready.pop(client.id, None)
            slot = room.slots.pop(client.id, None)
            if room.match and slot is not None:
                room.match.humans.discard(slot)
                room.match.actors[slot]['name'] += ' (AI)'
                room.match.actors[slot]['move_time'] = (.42,.21,.17)[room.difficulty]
            if not room.members:
                if room.task and room.task is not asyncio.current_task(): room.task.cancel()
                self.rooms.pop(room.id, None)
            else:
                if room.owner == client.id: room.owner = next(iter(room.members))
                self.broadcast_room(room)
        if notify:
            client.send(dict(type='left'))
            client.send(self.rooms_message())
        self.broadcast_rooms()

    @staticmethod
    def text(value, limit):
        if not isinstance(value, str): raise ValueError('Enter a valid name.')
        value = value.strip()
        if not value or len(value) > limit or not all(c.isprintable() for c in value):
            raise ValueError(f'Names must contain 1–{limit} printable characters.')
        return value

    def command(self, c, msg):
        if not isinstance(msg, dict): raise ValueError('Expected a message object.')
        kind = msg.get('type')
        if kind == 'hello':
            if c.room: raise ValueError('Leave your room before changing your name.')
            if msg.get('version') != 1: raise ValueError('Client/server version mismatch.')
            c.name = self.text(msg.get('name'), 20)
            c.send(dict(type='welcome', id=c.id, name=c.name))
            c.send(self.rooms_message())
            return
        if not c.name: raise ValueError('Introduce yourself first.')
        if kind == 'list': c.send(self.rooms_message())
        elif kind == 'create':
            if c.room: raise ValueError('You are already in a game.')
            if len(self.rooms) >= 64: raise ValueError('Server room limit reached.')
            difficulty = msg.get('difficulty',1)
            if type(difficulty) is not int or difficulty not in (0,1,2): raise ValueError('Invalid difficulty.')
            room = Room(c, self.text(msg.get('name'), 24), difficulty)
            self.rooms[room.id], c.room = room, room
            self.broadcast_room(room)
        elif kind == 'join':
            if c.room: raise ValueError('Leave your current game first.')
            room_id = msg.get('room')
            if not isinstance(room_id,str): raise ValueError('Invalid room.')
            room = self.rooms.get(room_id)
            if not room or room.state != 'waiting': raise ValueError('This game is no longer waiting.')
            if len(room.members) >= 4: raise ValueError('This game is full.')
            room.members[c.id], room.ready[c.id], c.room = c, True, room
            self.broadcast_room(room)
        elif kind == 'leave': self.leave(c)
        elif kind == 'ready':
            room = c.room
            if not room or room.state == 'playing': raise ValueError('The round is still running.')
            room.ready[c.id], room.state = True, 'waiting'
            self.broadcast_room(room)
        elif kind == 'start':
            room = c.room
            if not room or room.owner != c.id: raise ValueError('Only the game owner can start.')
            if room.state == 'playing': raise ValueError('A round is already running.')
            if not all(room.ready.values()): raise ValueError('Waiting for players to choose another round or leave.')
            room.slots = {client_id: i for i,client_id in enumerate(room.members)}
            room.match = Match(secrets.randbits(32), {room.slots[p.id]: p.name for p in room.members.values()},
                               room.difficulty, self.round_seconds)
            room.state, room.round = 'playing', room.round+1
            for p in room.members.values():
                p.direction, p.bomb = (0,0), False
                p.send(dict(type='started', slot=room.slots[p.id], round=room.round, state=room.match.snapshot(), countdown=3.))
            self.broadcast_room(room)
            room.task = asyncio.create_task(self.run_room(room))
        elif kind == 'input':
            if not c.room or c.room.state != 'playing': return
            direction = msg.get('direction')
            if not isinstance(direction,list) or len(direction)!=2 or any(type(v) is not int for v in direction):
                raise ValueError('Invalid movement input.')
            direction = tuple(direction)
            if direction not in DIRS and direction != (0,0): raise ValueError('Invalid movement input.')
            if type(msg.get('bomb',False)) is not bool: raise ValueError('Invalid bomb input.')
            c.direction, c.input_time = direction, time.monotonic()
            c.bomb = c.bomb or msg.get('bomb',False)
        else: raise ValueError('Unknown command.')

    async def run_room(self, room):
        try:
            tick, countdown, due = 0, 3., time.monotonic()
            match = room.match
            while room.members and not match.finished:
                due += 1/60
                await asyncio.sleep(max(0,due-time.monotonic()))
                if time.monotonic()-due > .1: due = time.monotonic()
                if countdown > 0:
                    countdown = max(0.,countdown-1/60)
                    for c in room.members.values(): c.bomb = False
                else:
                    match.tick(1/60)
                    if not match.finished:
                        for c in tuple(room.members.values()):
                            slot = room.slots[c.id]
                            if time.monotonic()-c.input_time < .35: match.move(slot,c.direction)
                            if c.bomb: match.place(slot)
                            c.bomb = False
                        for slot in range(4):
                            if slot not in match.humans: match.bot(slot)
                        match.check_end()
                tick += 1
                if tick % 3 == 0 or match.finished:
                    msg = dict(type='snapshot', state=match.snapshot(), countdown=countdown, events=match.events[:])
                    for c in room.members.values(): c.send(msg)
                    match.events.clear()
            if room.members:
                room.state = 'finished'
                room.ready = dict.fromkeys(room.members, False)
                self.broadcast_room(room)
        except asyncio.CancelledError:
            raise
        except Exception:
            LOG.exception('Room failed: %s', room.id)
            for c in list(room.members.values()):
                c.send(dict(type='error', message='Round stopped because of a server error.'))
                self.leave(c)

    async def handler(self, ws):
        if len(self.clients) >= 256:
            await ws.close(1013,'Server full')
            return
        c = Client(ws)
        self.clients[c.id] = c
        writer = asyncio.create_task(c.writer())
        try:
            async for raw in ws:
                now = time.monotonic()
                c.tokens = min(120.,c.tokens+(now-c.token_time)*60.)
                c.token_time = now
                c.tokens -= 1
                if c.tokens < 0:
                    await ws.close(1008,'Too many messages')
                    break
                try:
                    self.command(c,json.loads(raw))
                except (ValueError, TypeError, KeyError) as exc:
                    c.send(dict(type='error', message=str(exc)))
                if writer.done(): break
        except ConnectionClosed:
            pass
        finally:
            self.leave(c,notify=False)
            self.clients.pop(c.id,None)
            writer.cancel()
            with contextlib.suppress(asyncio.CancelledError, ConnectionClosed, TimeoutError): await writer

    def http_request(self, connection, request):
        if request.path == '/certificate':
            return connection.respond(http.HTTPStatus.OK, self.pem)
        if request.path != '/':
            return connection.respond(http.HTTPStatus.NOT_FOUND,'Not found\n')
        return None

async def main_async(args):
    context, pem = certificates(args.cert_dir)
    fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest().upper()
    print(f'AtomicTux TLS server: {args.host}:{args.port}\nCertificate SHA-256:\n{fingerprint}', flush=True)
    game = GameServer(pem)
    async with serve(game.handler,args.host,args.port,ssl=context,process_request=game.http_request,
                     max_size=4096,max_queue=16,compression=None,ping_interval=15,ping_timeout=15,close_timeout=3):
        await asyncio.Future()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host','--ip',default='127.0.0.1',help='IP address to bind; use 0.0.0.0 for LAN access')
    parser.add_argument('--port',type=int,default=8081)
    parser.add_argument('--cert-dir',type=Path,default=Path(__file__).parent/'certs')
    args = parser.parse_args()
    try: ipaddress.ip_address(args.host)
    except ValueError: parser.error('--host must be an IPv4 or IPv6 address')
    if not 1 <= args.port <= 65535: parser.error('--port must be between 1 and 65535')
    logging.basicConfig(level=logging.INFO)
    try: asyncio.run(main_async(args))
    except KeyboardInterrupt: pass
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        parser.exit(1,f'Server startup failed: {exc}\n')

if __name__ == '__main__': main()
