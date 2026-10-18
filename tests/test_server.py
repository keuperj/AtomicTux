"""Offline server rules/lobby tests: python3 -m unittest tests.test_server -v"""
import asyncio
import copy
import json
import math
from pathlib import Path
import tempfile
import subprocess
import unittest
from server.server import Client, GameServer, certificates
from server.simulation import Match, FIRE_TIME, SHIELD_GRACE, KICK_STEP

class FakeSocket:
    async def close(self, *args): pass

class SimulationTests(unittest.TestCase):
    def fresh(self):
        m = Match(42,{0:'Alice',1:'Bob'})
        for y in range(1,10):
            for x in range(1,12): m.grid[y][x] = 0
        return m

    def put(self, m, actor_id, cell):
        m.actors[actor_id].update(cell=cell, position=tuple(float(v) for v in cell), goal=None)

    def test_seed_and_spawns(self):
        self.assertEqual(Match(7,{}).grid,Match(7,{}).grid)
        m = Match(8,{0:'Alice',2:'Bob'},0)
        self.assertEqual(m.actors[2]['move_time'],.23)
        self.assertEqual(m.actors[1]['move_time'],.57)
        self.assertEqual(len(m.actors),4)
        for a in m.actors: self.assertEqual(m.tile(a['cell']),0)

    def test_atomic_and_weighted_drops(self):
        from server.simulation import ATOMIC_POWER, POWER_UPS, DROP_WEIGHTS
        m = self.fresh()
        m.pickups[(1,1)] = 'atomic'
        m.touch_actor(m.actors[0])
        a = m.actors[0]
        self.assertTrue(a['atomic'])
        a['capacity'] = 0
        self.assertFalse(m.place(0))
        self.assertTrue(a['atomic'])
        a['capacity'] = 2
        m.grid[1][3], m.grid[1][4], m.grid[1][7] = 2, 1, 2
        m.grid[3][1], m.grid[7][1] = 1, 2
        self.assertTrue(m.place(0))
        self.assertFalse(a['atomic'])
        self.assertEqual(m.bombs[0]['power'], ATOMIC_POWER)
        self.assertIn((11,1), m.danger())
        self.put(m, 0, (5,5))
        m.place(0)
        self.assertEqual(m.bombs[1]['power'], 2)
        self.put(m, 1, (9,1))
        m.place(1)
        m.actors[1]['shield'] = True
        m.bombs[0]['fuse'] = 0
        m.tick(.01)
        self.assertIn((11,1), m.flames)
        self.assertIn((1,9), m.flames)
        self.assertNotIn((5,5), m.flames)
        self.assertEqual(m.grid[1][7], 0)
        self.assertEqual(m.grid[7][1], 0)
        self.assertEqual(m.grid[1][4], 1)
        self.assertIsNone(m.bomb_at((9,1)))
        self.assertTrue(m.actors[1]['alive'])
        self.assertFalse(m.actors[1]['shield'])
        drops = m.rng.choices(POWER_UPS, weights=DROP_WEIGHTS, k=10000)
        self.assertTrue(4000 < drops.count('bomb') < 5000)
        self.assertTrue(300 < drops.count('speed') < 600)
        self.assertIn('atomic', m.snapshot()['actors'][0])

    def test_configurable_drop_pool(self):
        from server.simulation import POWER_UPS
        for enabled in (None, 'shield'):
            amounts = {k: (4 if k == enabled else 0) for k in POWER_UPS}
            found = []
            for seed in range(100):
                m = Match(seed, {0:'Alice'}, powerup_amounts=amounts)
                m.grid[1][2] = 2
                m.place(0)
                m.bombs[0]['fuse'] = 0
                m.tick(.01)
                found.extend(m.pickups.values())
                self.assertTrue(all(k == enabled for k in m.pickups.values()))
            if enabled: self.assertTrue(found)
            else: self.assertFalse(found)

    def test_connected_random_mazes_and_regeneration(self):
        from collections import deque
        from server.simulation import DIRS, add
        layouts = set()
        for seed in range(50):
            m = Match(seed, {0:'Alice'})
            seen, pending = {(1,1)}, deque([(1,1)])
            while pending:
                for d in DIRS:
                    c = add(pending[0], d)
                    if m.tile(c) != 1 and c not in seen:
                        seen.add(c)
                        pending.append(c)
                pending.popleft()
            self.assertTrue(all((x,y) in seen for y in range(11) for x in range(13) if m.tile((x,y)) != 1))
            self.assertTrue(all(a['cell'] in seen and m.tile(a['cell']) == 0 for a in m.actors))
            layouts.add(tuple(tuple(c == 1 for c in row) for row in m.grid))
            self.assertEqual(m.initial_crates, sum(row.count(2) for row in m.grid))
        self.assertEqual(len(layouts), 50)
        m = Match(42, {0:'Alice'})
        for x,y in m.crate_sites: m.grid[y][x] = 0
        count = lambda: sum(row.count(2) for row in m.grid)
        m.regenerate_crates(1.99)
        self.assertEqual(count(), 0)
        m.regenerate_crates(.02)
        self.assertEqual(count(), 1)
        for _ in range(30): m.regenerate_crates(2)
        self.assertEqual(count(), math.ceil(m.initial_crates*.2))
        for x,y in m.crate_sites: m.grid[y][x] = 0
        c = m.crate_sites[0]
        m.crate_sites, m.initial_crates = [c], 5
        m.pickups[c] = 'shield'
        m.regenerate_crates(2)
        self.assertEqual(m.tile(c),0)
        m.pickups.clear()
        m.flames[c] = .5
        m.regenerate_crates(2)
        self.assertEqual(m.tile(c),0)
        m.flames.clear()
        self.put(m,0,c)
        m.regenerate_crates(2)
        self.assertEqual(m.tile(c),0)

        m.actors[0]['cell'] = c
        m.place(0)
        self.put(m,0,(1,1))
        m.regenerate_crates(2)
        self.assertEqual(m.tile(c),0)
        m = Match(42, {0:'Alice'})
        for x,y in m.crate_sites: m.grid[y][x] = 0
        m.tick(2.01)
        self.assertEqual(sum(row.count(2) for row in m.grid),1)
        self.assertEqual(m.snapshot()['grid'], m.grid)
        m.finished = True
        m.tick(10)
        self.assertEqual(sum(row.count(2) for row in m.grid),1)

    def test_noisy_turns_all_directions(self):
        from server.simulation import DIRS
        for direction in DIRS:
            for turn_sign in (-1,1):
                m = self.fresh()
                self.put(m,0,(6,5))
                m.move(0,direction,m.actors[0]['move_time']*.4)
                turn = (-direction[1]*turn_sign, direction[0]*turn_sign)
                inp = tuple(turn[i]-direction[i]*.3 for i in (0,1))
                m.move(0,inp,m.actors[0]['move_time'])
                expected = tuple((6,5)[i]+direction[i]+turn[i]*.4 for i in (0,1))
                self.assertLess(math.dist(m.actors[0]['position'],expected),.001)

    def test_collision_and_capacity(self):
        m=self.fresh()
        m.move(0,(-1,0),.23)
        self.assertFalse(m.move(0,(-1,0)))
        self.assertFalse(m.move(0,(float("inf"),0)))
        self.assertTrue(m.place(0))
        self.assertFalse(m.place(0))
        self.assertTrue(m.move(0,(1,0),m.actors[0]['move_time']))
        self.assertTrue(m.move(0,(1,0)))
        m.tick(.2)
        m.move(0,(-1,0),.3)
        self.assertFalse(m.move(0,(-1,0)))

    def test_chain_and_walls(self):
        m=self.fresh()
        m.grid[1][4]=2
        m.place(0)
        self.put(m, 0, (8,5))
        self.put(m, 1, (3,1))
        m.place(1)
        self.put(m, 1, (8,7))
        m.bombs[0]['fuse']=0
        m.tick(.01)
        self.assertFalse(m.bombs)
        self.assertIn((4,1),m.flames)
        self.assertNotIn((5,1),m.flames)
        self.assertEqual(m.grid[1][4],0)

    def test_powerups_and_shield(self):
        m=self.fresh()
        for kind in ('bomb','fire','speed','kick','shield'):
            self.put(m, 0, (1,1))
            m.actors[0]['cooldown']=0
            m.pickups[(2,1)]=kind
            m.move(0,(1,0),m.actors[0]['move_time'])
        a=m.actors[0]
        self.assertEqual((a['capacity'],a['power']),(2,3))
        self.assertLess(a['move_time'],.23)
        self.assertTrue(a['kick'] and a['shield'])
        m.place(0)
        m.bombs[0]['fuse']=0
        m.tick(.01)
        self.assertTrue(a['alive'])
        self.assertFalse(a['shield'])
        m.tick(SHIELD_GRACE+.01)
        m.flames[a['cell']]=FIRE_TIME
        m.tick(.01)
        self.assertFalse(a['alive'])
        self.assertFalse(m.finished, 'Death of slot 0 must not end multiplayer')

    def test_kick_bounce_and_fuse(self):
        m=self.fresh()
        a=m.actors[0]
        self.put(m, 0, (3,5))
        a['kick']=True
        m.place(0)
        self.put(m, 0, (2,5))
        m.move(0,(1,0),m.actors[0]['move_time'])
        self.assertEqual(m.bombs[0]['cell'],(4,5))
        self.put(m, 0, (2,3))
        m.grid[5][5]=1
        m.tick(KICK_STEP)
        self.assertEqual(m.bombs[0]['cell'],(3,5))
        self.assertEqual(m.bombs[0]['direction'],(-1,0))
        m.bombs[0]['fuse']=.01
        m.tick(.02)
        self.assertFalse(m.bombs)
        self.assertIn((3,5),m.flames)

    def test_bot_escape(self):
        m=self.fresh()
        self.put(m, 2, (5,5))
        m.grid[5][6]=2
        m.bot(2)
        self.assertEqual(len(m.bombs),1)
        for _ in range(160):
            m.tick(1/60)
            m.bot(2)
        self.assertTrue(m.actors[2]['alive'])

    def test_win_and_timeout(self):
        m=self.fresh()
        for i in (0,1,2): m.actors[i]['alive']=False
        m.tick(.01)
        self.assertEqual(m.winner,3)
        m=self.fresh()
        m.remaining=.01
        m.tick(.02)
        self.assertEqual(m.winner,-1)
        self.assertTrue(m.finished)

    def test_snapshot_json(self):
        m=self.fresh()
        m.pickups[(3,3)]='shield'
        m.flames[(1,1)]=.5
        snapshot=json.loads(json.dumps(m.snapshot()))
        self.assertEqual(snapshot['pickups'][0]['cell'],[3,3])
        self.assertEqual(snapshot['actors'][1]['name'],'Bob')

    def test_continuous_movement_and_turns(self):
        for rate in (30,60,120):
            m=self.fresh()
            for _ in range(rate): m.move(0,(1,0),1/rate)
            self.assertAlmostEqual(m.actors[0]['position'][0],1+1/.23,places=5)
        m=self.fresh()
        m.move(0,(1,0))
        point=m.actors[0]['position']
        self.assertTrue(1 < point[0] < 1.2)
        self.assertEqual(m.actors[0]['cell'],(1,1))
        m.tick(.1)
        self.assertEqual(m.actors[0]['position'],point)
        m.move(0,(-1,0))
        self.assertAlmostEqual(m.actors[0]['position'][0],1)
        m.move(0,(1,0),.04)
        point=m.actors[0]['position']
        m.move(0,(0,1))
        self.assertLessEqual(math.dist(point,m.actors[0]['position']),1/60/.23+.00001)
        for _ in range(20): m.move(0,(0,1))
        self.assertAlmostEqual(m.actors[0]['position'][0],2.)
        self.assertGreater(m.actors[0]['position'][1],1.5)

    def test_continuous_collisions_and_fire(self):
        for obstacle in (1,2):
            m=self.fresh()
            m.grid[1][3]=obstacle
            m.move(0,(1,0),1.)
            self.assertAlmostEqual(m.actors[0]['position'][0],2.,places=3)
            self.assertFalse(m.move(0,(1,0)))
        m=self.fresh()
        m.actors[1].update(cell=(3,1),position=(2.5,1.))
        m.move(0,(1,0),.5)
        self.assertAlmostEqual(m.actors[0]['position'][0],1.,places=3)
        m=self.fresh()
        m.place(0)
        m.move(0,(1,0),.23)
        m.move(0,(-1,0),.23)
        self.assertAlmostEqual(m.actors[0]['position'][0],2.,places=3)
        m=self.fresh()
        m.flames[(2,1)]=.5
        m.move(0,(1,0),.23)
        self.assertFalse(m.actors[0]['alive'])
        self.assertLess(m.actors[0]['position'][0],1.5)

    def test_analog_angles_sliding_and_corners(self):
        for hour in range(12):
            m=self.fresh()
            self.put(m,0,(6,5))
            angle=hour*math.tau/12
            direction=(math.sin(angle),-math.cos(angle))
            m.move(0,direction,.23)
            displacement=tuple(m.actors[0]['position'][i]-(6,5)[i] for i in (0,1))
            self.assertAlmostEqual(math.hypot(*displacement),1,places=5)
            axis = 0 if abs(direction[0]) > abs(direction[1]) else 1
            self.assertAlmostEqual(displacement[axis],math.copysign(1,direction[axis]),places=5)
            self.assertAlmostEqual(displacement[1-axis],0,places=5)
        m=self.fresh()
        self.put(m,0,(6,5))
        m.move(0,(1,1),.23)
        self.assertAlmostEqual(math.dist(m.actors[0]['position'],(6,5)),1,places=5)
        m=self.fresh()
        self.put(m,0,(6,5))
        for y in range(1,10): m.grid[y][7]=1
        m.move(0,(.6,.8),.46)
        self.assertAlmostEqual(m.actors[0]['position'][0],6.,places=3)
        self.assertAlmostEqual(m.actors[0]['position'][1],7.,places=3)
        m=self.fresh()
        self.put(m,0,(6,5))
        m.grid[5][7]=m.grid[6][6]=1
        m.move(0,(1,1),1.)
        self.assertAlmostEqual(m.actors[0]['position'][0],6.)
        self.assertAlmostEqual(m.actors[0]['position'][1],5.)

    def test_grid_centerline_invariant(self):
        for direction in ((1,0),(-1,0),(0,1),(0,-1)):
            for obstacle in (1,2):
                m=self.fresh()
                self.put(m,0,(6,5))
                m.grid[5+direction[1]][6+direction[0]]=obstacle
                m.move(0,direction,1.)
                self.assertEqual(m.actors[0]['position'],(6.,5.))
        m=self.fresh()
        self.put(m,0,(6,5))
        for frame in range(180):
            angle=(frame//15)*math.tau/12
            m.move(0,(math.sin(angle),-math.cos(angle)))
            self.assertTrue(any(abs(v-round(v)) < .00001 for v in m.actors[0]['position']))

    def test_continuous_ai_and_snapshot(self):
        m=self.fresh()
        self.put(m,2,(5,5))
        m.grid[5][6]=2
        before=m.actors[2]['position']
        m.bot(2)
        self.assertGreater(math.dist(before,m.actors[2]['position']),0)
        self.assertLess(math.dist(before,m.actors[2]['position']),.1)
        for _ in range(30):
            before=m.actors[2]['position']
            m.tick(1/60)
            m.bot(2)
            self.assertLessEqual(math.dist(before,m.actors[2]['position']),1/60/m.actors[2]['move_time']+.00001)
        snapshot=json.loads(json.dumps(m.snapshot()))
        self.assertEqual(snapshot['actors'][2]['position'],list(m.actors[2]['position']))

class LobbyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.server=GameServer()
        self.clients=[]
        for name in ('Alice','Bob','Carol','Dave','Eve'):
            c=Client(FakeSocket())
            self.server.clients[c.id]=c
            self.server.command(c,dict(type='hello',version=1,name=name))
            self.clients.append(c)

    async def asyncTearDown(self):
        tasks=[r.task for r in self.server.rooms.values() if r.task]
        for t in tasks: t.cancel()
        await asyncio.gather(*tasks,return_exceptions=True)

    def create(self):
        self.server.command(self.clients[0],dict(type='create',name='Test room',difficulty=0))
        return self.clients[0].room

    async def test_host_powerup_settings(self):
        from server.simulation import DEFAULT_AMOUNTS
        r = self.create()
        owner, guest = self.clients[:2]
        self.server.command(guest, dict(type='join', room=r.id))
        self.assertEqual(r.public()['powerup_amounts'], DEFAULT_AMOUNTS)
        for command in ('powerup_amount', 'reset_powerups'):
            with self.assertRaises(ValueError):
                self.server.command(guest, dict(type=command, powerup='bomb', change=1))
        for change in (True, 1.0, 0, 2, -2, '1', None):
            with self.assertRaises(ValueError):
                self.server.command(owner, dict(type='powerup_amount', powerup='bomb', change=change))
        for kind in ('unknown', [], None):
            with self.assertRaises(ValueError):
                self.server.command(owner, dict(type='powerup_amount', powerup=kind, change=1))
        for _ in range(30): self.server.command(owner, dict(type='powerup_amount', powerup='bomb', change=1))
        self.assertEqual(r.powerup_amounts['bomb'], 20)
        for _ in range(30): self.server.command(owner, dict(type='powerup_amount', powerup='speed', change=-1))
        self.assertEqual(r.powerup_amounts['speed'], 0)
        expected = r.powerup_amounts.copy()
        self.server.command(owner, dict(type='start'))
        self.assertEqual(r.match.powerup_amounts, expected)
        self.assertEqual(r.match.snapshot()['powerup_amounts'], expected)
        with self.assertRaises(ValueError): self.server.command(owner, dict(type='reset_powerups'))
        with self.assertRaises(ValueError): self.server.command(owner, dict(type='powerup_amount', powerup='bomb', change=-1))
        r.task.cancel()
        await asyncio.gather(r.task, return_exceptions=True)
        r.state = 'finished'
        r.ready = dict.fromkeys(r.members, False)
        self.server.leave(owner)
        self.assertEqual(r.owner, guest.id)
        self.assertEqual(r.powerup_amounts, expected)
        self.server.command(guest, dict(type='ready'))
        self.server.command(guest, dict(type='start'))
        self.assertEqual(r.match.powerup_amounts, expected)
        r.task.cancel()
        await asyncio.gather(r.task, return_exceptions=True)
        r.state = 'finished'
        self.server.command(guest, dict(type='reset_powerups'))
        self.assertEqual(r.powerup_amounts, DEFAULT_AMOUNTS)
        self.assertEqual(r.match.powerup_amounts, expected, 'Previous match owns an independent copy')

    async def test_join_start_and_capacity(self):
        r=self.create()
        for c in self.clients[1:4]: self.server.command(c,dict(type='join',room=r.id))
        with self.assertRaises(ValueError): self.server.command(self.clients[4],dict(type='join',room=r.id))
        with self.assertRaises(ValueError): self.server.command(self.clients[1],dict(type='start'))
        self.server.command(self.clients[0],dict(type='start'))
        self.assertEqual(r.match.humans,{0,1,2,3})
        self.assertEqual(self.server.rooms_message()['rooms'],[])
        with self.assertRaises(ValueError): self.server.command(self.clients[4],dict(type='join',room=r.id))
        with self.assertRaises(ValueError): self.server.command(self.clients[0],dict(type='start'))

    async def test_fill_ai_disconnect_transfer_and_cleanup(self):
        r=self.create()
        self.server.command(self.clients[1],dict(type='join',room=r.id))
        self.server.command(self.clients[0],dict(type='start'))
        self.assertEqual(r.match.humans,{0,1})
        self.server.leave(self.clients[0])
        self.assertEqual(r.owner,self.clients[1].id)
        self.assertEqual(r.match.humans,{1})
        self.server.leave(self.clients[1])
        self.assertFalse(self.server.rooms)
        await asyncio.gather(r.task,return_exceptions=True)

    async def test_rematch_choices(self):
        r=self.create()
        self.server.command(self.clients[1],dict(type='join',room=r.id))
        r.state='finished'
        r.ready=dict.fromkeys(r.members,False)
        self.server.command(self.clients[0],dict(type='ready'))
        with self.assertRaises(ValueError): self.server.command(self.clients[0],dict(type='start'))
        self.server.command(self.clients[1],dict(type='ready'))
        self.server.command(self.clients[0],dict(type='start'))
        self.assertEqual(r.state,'playing')

    async def test_input_validation_and_identity(self):
        r=self.create()
        self.server.command(self.clients[0],dict(type='start'))
        for direction in ([True,0], [99,0], [float('nan'),0], [0,float('inf')], ['1',0], 'right', None):
            with self.assertRaises(ValueError): self.server.command(self.clients[0],dict(type='input',direction=direction))
        self.server.command(self.clients[0],dict(type='input',direction=[.5,-math.sqrt(.75)]))
        self.assertAlmostEqual(self.clients[0].direction[0],.5)
        self.assertAlmostEqual(self.clients[0].direction[1],-math.sqrt(.75))
        self.server.command(self.clients[0],dict(type='input',direction=[1,1]))
        self.assertAlmostEqual(math.hypot(*self.clients[0].direction),1)
        self.server.command(self.clients[0],dict(type='input',direction=[1,0],bomb=True,actor=3))
        self.assertEqual(self.clients[0].direction,(1,0))
        self.assertEqual(r.slots[self.clients[0].id],0)
        with self.assertRaises(ValueError): self.server.command(self.clients[0],dict(type='hello',name='Other',version=1))
        for value in ('', 'x'*21, 'a\nb', 123):
            with self.assertRaises(ValueError): self.server.text(value,20)

class CertificateTests(unittest.TestCase):
    def test_generation_reuse_and_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            _,pem=certificates(directory)
            _,again=certificates(directory)
            self.assertEqual(pem,again)
            self.assertEqual((Path(directory)/'server.key').stat().st_mode & 0o777,0o600)
            self.assertIn('BEGIN CERTIFICATE',pem)
            subprocess.run(['openssl','verify','-CAfile',str(Path(directory)/'server.crt'),str(Path(directory)/'server.crt')],check=True,capture_output=True)

if __name__=='__main__': unittest.main()
