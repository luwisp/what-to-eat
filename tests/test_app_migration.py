import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/migrate-app-data.py'
class MigrationTests(unittest.TestCase):
    def test_preserves_snapshot_assets_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as root:
            old = Path(root) / 'huaiwei.sqlite'
            new = Path(root) / 'juxiaobao.sqlite'
            payload = json.dumps({'users':[{'id':'existing'}], 'sessions':[{'roomCode':'EXIST'}]})
            with sqlite3.connect(old) as db:
                db.execute('CREATE TABLE app_snapshot(id INTEGER PRIMARY KEY, schema_version INTEGER, payload_json TEXT)')
                db.execute('INSERT INTO app_snapshot VALUES(1,1,?)', (payload,))
                db.execute('CREATE TABLE menu_assets(name TEXT, content BLOB)')
                db.execute('INSERT INTO menu_assets VALUES(?,?)', ('image', b'image-content'))
            subprocess.run(['python3',str(SCRIPT),'--db',str(new)],check=True,capture_output=True)
            self.assertTrue(old.exists())
            with sqlite3.connect(new) as db:
                self.assertEqual(db.execute('SELECT payload_json FROM app_snapshot').fetchone()[0],payload)
                self.assertEqual(db.execute('SELECT content FROM menu_assets').fetchone()[0],b'image-content')
                db.execute('UPDATE app_snapshot SET payload_json=?', ('newer',))
            subprocess.run(['python3',str(SCRIPT),'--db',str(new)],check=True)
            with sqlite3.connect(new) as db:
                self.assertEqual(db.execute('SELECT payload_json FROM app_snapshot').fetchone()[0],'newer')
    def test_custom_database_does_not_use_legacy_file(self):
        with tempfile.TemporaryDirectory() as root:
            Path(root,'huaiwei.sqlite').touch()
            custom = Path(root,'test.sqlite')
            subprocess.run(['python3',str(SCRIPT),'--db',str(custom)],check=True)
            self.assertFalse(custom.exists())
if __name__ == '__main__': unittest.main()
