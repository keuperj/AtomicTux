"""Real TLS integration with Python WebSocket clients and two Godot clients."""
import asyncio
import hashlib
import json
import os
from pathlib import Path
import ssl
import tempfile
import unittest
from websockets.asyncio.server import serve
from websockets.asyncio.client import connect
from server.server import GameServer, certificates

ROOT=Path(__file__).resolve().parents[1]

class IntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_tls_godot_and_reject_wrong_certificate(self):
        with tempfile.TemporaryDirectory(prefix='atomictux-network-') as temp:
            context,pem=certificates(Path(temp)/'certs')
            certificates(Path(temp)/'other-certs')
            server=GameServer(pem,round_seconds=1.2)
            loop=asyncio.get_running_loop()
            def expected_tls_rejection(loop, context):
                if isinstance(context.get('exception'), (ConnectionResetError, ssl.SSLError)):
                    return
                loop.default_exception_handler(context)
            loop.set_exception_handler(expected_tls_rejection)
            async with serve(server.handler,'127.0.0.1',0,ssl=context,process_request=server.http_request,
                             max_size=4096,compression=None) as listener:
                port=listener.sockets[0].getsockname()[1]
                # A certificate which wasn't trusted must fail, rather than silently downgrade.
                with self.assertRaises(ssl.SSLCertVerificationError):
                    async with connect(f'wss://127.0.0.1:{port}/',ssl=ssl.create_default_context()): pass
                trusted=ssl.create_default_context(cadata=pem)
                async with connect(f'wss://127.0.0.1:{port}/',ssl=trusted,server_hostname='atomictux') as ws:
                    await ws.send(json.dumps(dict(type='hello',name='TLS check',version=1)))
                    self.assertEqual(json.loads(await ws.recv())['type'],'welcome')
                    await ws.recv()
                    await ws.send('not json')
                    self.assertEqual(json.loads(await ws.recv())['type'],'error')
                env=os.environ.copy()
                env.update(XDG_DATA_HOME=temp+'/data',XDG_CONFIG_HOME=temp+'/config',XDG_CACHE_HOME=temp+'/cache',
                           ATOMICTUX_TEST_PORT=str(port),ATOMICTUX_TEST_WRONG_CERT=str(Path(temp)/'other-certs'/'server.crt'),ATOMICTUX_TEST_FINGERPRINT=hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest().upper())
                process=await asyncio.create_subprocess_exec(str(ROOT/'godot.sh'),'--headless','--script','tests/test_network.gd',
                            cwd=ROOT,env=env,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.STDOUT)
                try:
                    output,_=await asyncio.wait_for(process.communicate(),45)
                except asyncio.TimeoutError:
                    process.kill()
                    await process.wait()
                    self.fail('Godot integration timed out')
                print(output.decode())
                self.assertEqual(process.returncode,0)
                self.assertNotIn('SCRIPT ERROR',output.decode())
                await asyncio.sleep(.1)
                self.assertFalse(server.rooms,'Empty rooms must be cleaned up')

if __name__=='__main__': unittest.main(verbosity=2)
