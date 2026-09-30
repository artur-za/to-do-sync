import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('prepare',Path(__file__).parents[1]/'prepare.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class PrepareTests(unittest.TestCase):
    def test_secrets_private_assets_public_and_rerun_preserves_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);settings=root/'settings.json'
            settings.write_text(json.dumps({'public_url':'https://example.com/todo','owner_id':'123456','bot_username':'example_test_bot','bot_token':'123456:'+('a'*35)}))
            m.prepare(settings,root/'one');first=json.loads(settings.read_text())
            m.prepare(settings,root/'two');second=json.loads(settings.read_text())
            self.assertEqual(first['sync_token'],second['sync_token'])
            self.assertEqual(settings.stat().st_mode&0o777,0o600)
            for file in (root/'one/public').rglob('*'):
                if file.is_file():
                    self.assertNotIn(first['sync_token'],file.read_text())
                    self.assertNotIn(first['bot_token'],file.read_text())
            self.assertTrue((root/'one/private/src/database.php').exists())
            self.assertIn('example_test_bot',(root/'one/public/mini/config.mjs').read_text())
            self.assertEqual(json.loads((root/'one/client.json').read_text())['endpoint'],'https://example.com/todo/index.php?route=sync')
            # Integration: install twice into an isolated tree, preserve UUID epoch and config.
            if __import__('shutil').which('php'):
                public,private=root/'web',root/'private'
                def install(bundle):
                    return subprocess.run(['php',str(root/bundle/'install.php'),str(public),str(private)],capture_output=True,text=True)
                result=install('one');self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                config=(private/'config.php').read_bytes()
                import sqlite3
                with sqlite3.connect(private/'data/flodo.sqlite') as db:epoch=db.execute("SELECT value FROM meta WHERE key='epoch'").fetchone()[0]
                result=install('two');self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual(config,(private/'config.php').read_bytes())
                with sqlite3.connect(private/'data/flodo.sqlite') as db:self.assertEqual(epoch,db.execute("SELECT value FROM meta WHERE key='epoch'").fetchone()[0])
                self.assertTrue(list((private/'backups').glob('*.sqlite')))
                bad=subprocess.run(['php',str(root/'one/install.php'),str(root/'unsafe'),str(root/'unsafe/private')],capture_output=True)
                self.assertNotEqual(bad.returncode,0)
    def test_rejects_unsafe_urls(self):
        for url in ['http://example.com','https://user:pass@example.com','https://example.com?key=secret']:
            with self.assertRaises(ValueError):m.https_url(url)

if __name__=='__main__':unittest.main()
