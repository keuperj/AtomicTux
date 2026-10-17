"""Offline server rules/lobby tests: python3 -m unittest tests.test_server -v"""
import asyncio
import copy
import json
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

    def test_seed_and_spawns(self):
        self.assertEqual(Match(7,{}).grid,Match(7,{}).grid)
        m = Match(8,{0:'Alice',2:'Bob'},0)
        self.assertEqual(m.actors[2]['move_time'],.17)
        self.assertEqual(m.actors[1]['move_time'],.42)
        self.assertEqual(len(m.actors),4)
        for a in m.actors: self.assertEqual(m.tile(a['cell']),0)

    def test_collision_and_capacity(self):
        m=self.fresh()
        self.assertFalse(m.move(0,(-1,0)))
        self.assertFalse(m.move(0,(1,1)))
        self.assertTrue(m.place(0))
        self.assertFalse(m.place(0))
        self.assertTrue(m.move(0,(1,0)))
        self.assertFalse(m.move(0,(1,0)))
        m.tick(.2)
        self.assertFalse(m.move(0,(-1,0)))

    def test_chain_and_walls(self):
        m=self.fresh()
        m.grid[1][4]=2
        m.place(0)
        m.actors[0]['cell']=(8,5)
        m.actors[1]['cell']=(3,1)
        m.place(1)
        m.actors[1]['cell']=(8,7)
        m.bombs[0]['fuse']=0
        m.tick(.01)
        self.assertFalse(m.bombs)
        self.assertIn((4,1),m.flames)
        self.assertNotIn((5,1),m.flames)
        self.assertEqual(m.grid[1][4],0)

    def test_powerups_and_shield(self):
        m=self.fresh()
        for kind in ('bomb','fire','speed','kick','shield'):
            m.actors[0]['cell']=(1,1)
            m.actors[0]['cooldown']=0
            m.pickups[(2,1)]=kind
            m.move(0,(1,0))
        a=m.actors[0]
        self.assertEqual((a['capacity'],a['power']),(2,3))
        self.assertLess(a['move_time'],.17)
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
        a.update(cell=(3,5),kick=True)
        m.place(0)
        a['cell']=(2,5)
        m.move(0,(1,0))
        self.assertEqual(m.bombs[0]['cell'],(4,5))
        a['cell']=(2,3)
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
        m.actors[2]['cell']=(5,5)
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
        for direction in ([1,1], [True,0], [99,0], 'right', None):
            with self.assertRaises(ValueError): self.server.command(self.clients[0],dict(type='input',direction=direction))
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
