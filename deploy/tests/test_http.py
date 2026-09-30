"""Exercise the real PHP entrypoints without Telegram network calls or real data."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('prepare_http',ROOT/'deploy/prepare.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

@unittest.skipUnless(shutil.which('php'),'PHP CLI needed for HTTP integration')
class HTTPTests(unittest.TestCase):
    def start_server(self,root,env=None):
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        proc=subprocess.Popen(['php','-S',f'127.0.0.1:{port}','-t',str(root)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (proc.terminate(),proc.wait(timeout=5)))
        for _ in range(100):
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.1):break
            except OSError:time.sleep(.03)
        return f'http://127.0.0.1:{port}'
    def request(self,base,path,body=None,headers=None):
        req=urllib.request.Request(base+path,data=None if body is None else json.dumps(body).encode(),headers=headers or {})
        try:
            with urllib.request.urlopen(req,timeout=5) as r:return r.status,r.read(),r.headers
        except urllib.error.HTTPError as e:return e.code,e.read(),e.headers
    def test_sqlite_installed_api_and_public_boundaries(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);settings=root/'settings.json'
            settings.write_text(json.dumps({'public_url':'https://example.com','owner_id':'123456','bot_username':'example_test_bot','bot_token':'123456:'+('a'*35)}))
            bundle=m.prepare(settings,root/'bundle');public=root/'public';private=root/'private'
            subprocess.run(['php',str(bundle/'install.php'),str(public),str(private)],check=True,capture_output=True)
            base=self.start_server(public)
            self.assertEqual(self.request(base,'/index.php?route=health')[0],200)
            for route in ['sync','mini-sync','webhook']:
                self.assertEqual(self.request(base,'/index.php?route='+route,{})[0],401)
            token=json.loads(settings.read_text())['sync_token']
            code,data,_=self.request(base,'/index.php?route=sync',{'operations':[]},{'Authorization':'Bearer '+token})
            self.assertEqual(code,200);self.assertEqual(json.loads(data)['records'],[])
            code,data,headers=self.request(base,'/mini/index.php')
            self.assertEqual(code,200);self.assertIn('Content-Security-Policy',headers)
            for path in ['/private/config.php','/data/flodo.sqlite','/server/src/core.php','/.env']:
                self.assertEqual(self.request(base,path)[0],404)
    def test_vercel_entrypoints_deny_unauthenticated_calls(self):
        env=dict(os.environ,OWNER_ID='123456',BOT_TOKEN='123456:'+('a'*35),PUBLIC_URL='https://example.com',DATABASE_URL='postgresql://unused:unused@127.0.0.1/unused?sslmode=require',SYNC_TOKEN='a'*64,WEBHOOK_SECRET='b'*64,CRON_SECRET='c'*64)
        base=self.start_server(ROOT,env)
        self.assertEqual(self.request(base,'/api/index.php?route=health')[0],200)
        for route in ['sync','mini-sync','webhook']:
            self.assertEqual(self.request(base,'/api/index.php?route='+route,{})[0],401)
        self.assertEqual(self.request(base,'/api/cron.php')[0],401)
        self.assertEqual(self.request(base,'/api/cron.php',headers={'Authorization':'Bearer invalid'})[0],401)
