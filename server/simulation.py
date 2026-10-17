"""Authoritative multiplayer rules matching scripts/arena.gd; no client state is trusted."""
import random
from collections import deque

DIRS = ((0, -1), (1, 0), (0, 1), (-1, 0))
POWER_UPS = ("bomb", "fire", "speed", "kick", "shield")
FUSE, FIRE_TIME, KICK_STEP, SHIELD_GRACE = 2.4, .65, .065, .75

def add(a, b, n=1):
    return (a[0] + b[0] * n, a[1] + b[1] * n)

class Match:
    def __init__(self, seed, players, difficulty=1, duration=150):
        self.rng = random.Random(seed)
        self.difficulty = difficulty
        self.humans = set(players)
        self.remaining, self.elapsed = float(duration), 0.
        self.finished, self.winner = False, -2
        self.bombs, self.flames, self.pickups, self.events = [], {}, {}, []
        spawns = [(1, 1), (11, 9), (11, 1), (1, 9)]
        self.grid = []
        for y in range(11):
            row = []
            for x in range(13):
                wall = x in (0, 12) or y in (0, 10) or (x % 2 == 0 and y % 2 == 0)
                tile = 1 if wall else (2 if self.rng.random() < .72 else 0)
                if not wall and any(abs(x-s[0])+abs(y-s[1]) <= 2 for s in spawns):
                    tile = 0
                row.append(tile)
            self.grid.append(row)
        self.actors = [dict(id=i, name=players.get(i, ("TUX", "EMBER", "BYTE", "NOVA")[i]),
                            cell=c, previous=c, alive=True, cooldown=0.,
                            move_time=.17 if i in players else (.42, .21, .17)[difficulty],
                            capacity=1, power=2, bombs=0, kick=False, shield=False,
                            invulnerable=0., bomb_cooldown=0., facing=(0, 1))
                       for i, c in enumerate(spawns)]

    def tile(self, c):
        return self.grid[c[1]][c[0]] if 0 <= c[0] < 13 and 0 <= c[1] < 11 else 1

    def bomb_at(self, c):
        return next((b for b in self.bombs if b['cell'] == c), None)

    def walkable(self, c, actor_id=-1):
        return self.tile(c) == 0 and self.bomb_at(c) is None and not any(
            a['alive'] and a['id'] != actor_id and a['cell'] == c for a in self.actors)

    def move(self, actor_id, direction):
        a = self.actors[actor_id]
        if self.finished or not a['alive'] or a['cooldown'] > 0 or direction not in DIRS:
            return False
        target = add(a['cell'], direction)
        a['facing'] = direction
        bomb = self.bomb_at(target)
        if bomb and a['kick'] and not any(o['alive'] and o['cell'] == target for o in self.actors):
            dest = add(target, direction)
            if self.walkable(dest):
                bomb.update(cell=dest, direction=direction, motion_time=0.)
                if dest in self.flames:
                    bomb['fuse'] = 0.
        if not self.walkable(target, actor_id):
            return False
        a.update(previous=a['cell'], cell=target, cooldown=a['move_time'])
        if target in self.flames:
            self.hit(a)
        elif target in self.pickups:
            kind = self.pickups.pop(target)
            if kind == 'bomb': a['capacity'] = min(5, a['capacity']+1)
            elif kind == 'fire': a['power'] = min(7, a['power']+1)
            elif kind == 'speed': a['move_time'] = max(.105, a['move_time']-.025)
            else: a[kind] = True
            self.events.append(dict(type='pickup', actor=actor_id, kind=kind))
        return True

    def place(self, actor_id):
        a = self.actors[actor_id]
        if self.finished or not a['alive'] or a['bomb_cooldown'] > 0 or a['bombs'] >= a['capacity'] or self.bomb_at(a['cell']):
            return False
        self.bombs.append(dict(cell=a['cell'], owner=actor_id, power=a['power'], fuse=FUSE,
                               direction=(0, 0), motion_time=0.))
        a['bombs'] += 1
        a['bomb_cooldown'] = 4. if actor_id not in self.humans and self.difficulty == 0 else 0.
        return True

    def blast(self, cell, power):
        result = [cell]
        for d in DIRS:
            for n in range(1, power+1):
                c = add(cell, d, n)
                if self.tile(c) == 1: break
                result.append(c)
                if self.tile(c) == 2 or self.bomb_at(c): break
        return result

    def hit(self, a):
        if not a['alive'] or a['invulnerable'] > 0: return
        if a['shield']:
            a.update(shield=False, invulnerable=SHIELD_GRACE)
            self.events.append(dict(type='shield', actor=a['id']))
        else:
            a['alive'] = False
            self.events.append(dict(type='death', actor=a['id']))

    def tick(self, dt):
        if self.finished: return
        self.elapsed += dt
        self.remaining = max(0., self.remaining-dt)
        for a in self.actors:
            for key in ('cooldown', 'invulnerable', 'bomb_cooldown'):
                a[key] = max(0., a[key]-dt)
        self.flames = {c: t-dt for c, t in self.flames.items() if t > dt}
        for b in self.bombs:
            if b['cell'] in self.flames: b['fuse'] = 0.
            if b['direction'] != (0, 0) and b['fuse'] > 0:
                b['motion_time'] += min(dt, b['fuse'])
                while b['motion_time'] >= KICK_STEP:
                    b['motion_time'] -= KICK_STEP
                    dest = add(b['cell'], b['direction'])
                    if not self.walkable(dest):
                        b['direction'] = tuple(-v for v in b['direction'])
                        dest = add(b['cell'], b['direction'])
                    if self.walkable(dest): b['cell'] = dest
                    if b['cell'] in self.flames:
                        b['fuse'] = 0.
                        break
            b['fuse'] -= dt
        while True:
            bomb = next((b for b in self.bombs if b['fuse'] <= 0 or b['cell'] in self.flames), None)
            if bomb is None: break
            cells = self.blast(bomb['cell'], bomb['power'])
            self.bombs.remove(bomb)
            self.actors[bomb['owner']]['bombs'] -= 1
            for c in cells:
                chain = self.bomb_at(c)
                if chain: chain['fuse'] = 0.
                self.flames[c] = FIRE_TIME
                self.pickups.pop(c, None)
                if self.tile(c) == 2:
                    self.grid[c[1]][c[0]] = 0
                    if self.rng.random() < .38: self.pickups[c] = self.rng.choice(POWER_UPS)
            self.events.append(dict(type='explosion', cells=cells))
        for a in self.actors:
            if a['cell'] in self.flames: self.hit(a)
        self.check_end()

    def check_end(self):
        alive = [a for a in self.actors if a['alive']]
        if len(alive) <= 1 or self.remaining <= 0:
            self.finished = True
            self.winner = alive[0]['id'] if len(alive) == 1 else -1

    def danger(self):
        danger = dict.fromkeys(self.flames, 0.)
        times = [b['fuse'] for b in self.bombs]
        for _ in self.bombs:
            for i, b in enumerate(self.bombs):
                cells = self.blast(b['cell'], b['power'])
                for j, other in enumerate(self.bombs):
                    if other['cell'] in cells: times[j] = min(times[j], times[i])
        for i, b in enumerate(self.bombs):
            origins = {b['cell']}
            if b['direction'] != (0, 0):
                for sign in (-1, 1):
                    for n in range(1, 14):
                        c = add(b['cell'], b['direction'], n*sign)
                        if self.tile(c): break
                        origins.add(c)
            for origin in origins:
                for c in self.blast(origin, b['power']): danger[c] = min(danger.get(c, 99.), times[i])
        return danger

    def route(self, actor_id, danger, escape):
        a = self.actors[actor_id]
        origin = a['cell']
        queue, visited = deque([(origin, [])]), {origin}
        while queue:
            c, path = queue.popleft()
            target = c in self.pickups or any(self.tile(add(c,d)) == 2 for d in DIRS) or any(
                o['alive'] and o['id'] != actor_id and sum((o['cell'][i]-c[i])**2 for i in (0,1)) <= 4 for o in self.actors)
            if c != origin and c not in danger and (escape or target): return path
            for i in range(4):
                nxt = add(c, DIRS[(i+actor_id)%4])
                if nxt in visited or not self.walkable(nxt, actor_id): continue
                arrival = (len(path)+1)*a['move_time']
                if nxt in danger and (not escape or danger[nxt] <= arrival+a['move_time']+.15): continue
                visited.add(nxt)
                queue.append((nxt, path+[nxt]))
        return []

    def bot(self, actor_id):
        a = self.actors[actor_id]
        if not a['alive'] or a['cooldown'] > 0 or self.finished: return
        danger, origin = self.danger(), a['cell']
        if origin in danger:
            path = self.route(actor_id, danger, True)
        else:
            cells = self.blast(origin, a['power'])
            useful = any(self.tile(c) == 2 for c in cells) or any(
                o['alive'] and o['id'] != actor_id and o['cell'] in cells for o in self.actors)
            if useful and a['bombs'] < a['capacity'] and a['bomb_cooldown'] <= 0:
                hypothetical = danger.copy()
                for c in cells: hypothetical[c] = min(hypothetical.get(c, 99.), FUSE)
                path = self.route(actor_id, hypothetical, True)
                if path:
                    self.place(actor_id)
                    self.move(actor_id, tuple(path[0][i]-origin[i] for i in (0,1)))
                    return
            path = self.route(actor_id, danger, False)
        if path: self.move(actor_id, tuple(path[0][i]-origin[i] for i in (0,1)))

    def snapshot(self):
        return dict(grid=self.grid, actors=self.actors, bombs=self.bombs,
                    flames=[dict(cell=c, time=t) for c,t in self.flames.items()],
                    pickups=[dict(cell=c, kind=k) for c,k in self.pickups.items()],
                    remaining=self.remaining, elapsed=self.elapsed, finished=self.finished,
                    winner=self.winner, difficulty=self.difficulty, humans=sorted(self.humans))
