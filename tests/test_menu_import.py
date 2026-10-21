"""SQLite importer contract tests. Run: python3 -m unittest discover -s tests -p 'test_menu_import.py'."""
import base64
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('menu_import', ROOT / 'scripts/import-menu.py')
menu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(menu)
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a4WQAAAAASUVORK5CYII=')


def workbook(path, rows):
    worksheet = ET.Element(menu.S + 'worksheet')
    data = ET.SubElement(worksheet, menu.S + 'sheetData')
    for number, values in enumerate([menu.HEADERS] + rows, 1):
        row = ET.SubElement(data, menu.S + 'row', r=str(number))
        for index, value in enumerate(values):
            cell = ET.SubElement(row, menu.S + 'c', r=f'{chr(65 + index)}{number}', t='inlineStr')
            if value.startswith('='):
                ET.SubElement(cell, menu.S + 'f').text = value[1:]
            else:
                ET.SubElement(ET.SubElement(cell, menu.S + 'is'), menu.S + 't').text = value
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('xl/workbook.xml', f'<workbook xmlns="{menu.S[1:-1]}" xmlns:r="{menu.R[1:-1]}"><sheets><sheet name="菜单" sheetId="1" r:id="rId1"/></sheets></workbook>')
        archive.writestr('xl/_rels/workbook.xml.rels', '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>')
        archive.writestr('xl/worksheets/sheet1.xml', ET.tostring(worksheet))
        archive.writestr('xl/cellimages.xml', f'<images xmlns:xdr="{menu.XDR[1:-1]}" xmlns:a="{menu.A[1:-1]}" xmlns:r="{menu.R[1:-1]}"><xdr:pic><xdr:nvPicPr><xdr:cNvPr name="ID_TEST"/></xdr:nvPicPr><a:blip r:embed="rId1"/></xdr:pic></images>')
        archive.writestr('xl/_rels/cellimages.xml.rels', '<Relationships><Relationship Id="rId1" Target="media/a.png"/></Relationships>')
        archive.writestr('xl/media/a.png', PNG)


def dish(name='测试菜', price='9.9', ingredients='土豆， UNKNOWN ，unknown，土豆'):
    return [name, price, '=_xlfn.DISPIMG("ID_TEST",1)', '热菜', ingredients, '微辣', '咸', '炒', '测试简介']


class MenuImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.source = self.path / 'menu.xlsx'
        self.args = menu.parser().parse_args(['--source', str(self.source), '--db', str(self.path / 'app.sqlite'),
                                             '--assets-dir', str(self.path / 'images'),
                                             '--snapshot-out', str(self.path / 'snapshot.json')])
        workbook(self.source, [dish()])

    def snapshot(self):
        with sqlite3.connect(self.args.db) as db:
            return json.loads(db.execute('SELECT payload_json FROM app_snapshot').fetchone()[0])

    def test_prices_unknown_images_and_idempotent_reimport(self):
        result = menu.import_menu(self.args)
        self.assertEqual(result['menuVersion'], 1)
        with sqlite3.connect(self.args.db) as db:
            name, fen, category, ingredients, spice = db.execute('SELECT name,priceFen,category,ingredients,spiceLevel FROM dishes').fetchone()
            self.assertEqual((name, fen, category, spice), ('测试菜', 990, 'hot', 1))
            self.assertEqual(json.loads(ingredients), ['土豆', 'unknown'])
            filename, content = db.execute('SELECT filename,content FROM menu_assets').fetchone()
            self.assertEqual(content, PNG)
            self.assertEqual((self.args.assets_dir / filename).read_bytes(), PNG)
            self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
        self.assertEqual(json.loads(self.args.snapshot_out.read_text()), self.snapshot())
        before = self.snapshot()
        again = menu.import_menu(self.args)
        self.assertFalse(again['changed'])
        self.assertEqual(again['menuVersion'], 1)
        self.assertEqual(before, self.snapshot())
        # Derived images can be restored solely from committed SQLite assets.
        (self.args.assets_dir / filename).unlink()
        menu.import_menu(self.args)
        self.assertEqual((self.args.assets_dir / filename).read_bytes(), PNG)

    def test_update_archives_missing_dishes_preserves_accounts_and_invalidates_results(self):
        workbook(self.source, [dish(), dish('将下架', '2')])
        menu.import_menu(self.args)
        before = self.snapshot()
        rid = before['restaurants'][0]['id']
        before['users'] = [{'id': 'user-sentinel'}]
        before['restaurants'].append({'id': 'other', 'restaurantCode': 'OTHER', 'ownerId': 'merchant', 'name': '其他店', 'description': ''})
        before['authSessions'] = [{'accountId': 'user-sentinel', 'tokenHash': 'hash'}]
        before['sessions'] = [dict(id='room', restaurantId=rid, stateVersion=7, state='recommended', recommendationInvalid=False)]
        before['recommendations'] = [dict(sessionId='room', canConfirm=True, accepted=True)]
        before['jobs'] = [dict(sessionId='room', status='inProgress')]
        with sqlite3.connect(self.args.db) as db:
            db.execute('UPDATE app_snapshot SET payload_json=?', (menu.dumps(before),))
        workbook(self.source, [dish(price='10.01')])
        self.assertEqual(menu.import_menu(self.args)['menuVersion'], 2)
        after = self.snapshot()
        self.assertEqual(after['users'], before['users'])
        self.assertEqual(after['authSessions'], before['authSessions'])
        self.assertEqual(len(after['restaurants']), 2)
        self.assertEqual(after['sessions'][0]['stateVersion'], 8)
        self.assertEqual(after['sessions'][0]['state'], 'open')
        self.assertFalse(after['recommendations'][0]['canConfirm'])
        self.assertEqual(after['jobs'][0]['status'], 'cancelled')
        self.assertFalse(next(d for d in after['dishes'] if d['name'] == '将下架')['available'])
        self.assertEqual(next(d for d in after['dishes'] if d['name'] == '测试菜')['priceFen'], 1001)
        self.assertFalse(menu.import_menu(self.args)['changed'])

    def test_invalid_source_and_database_write_failure_leave_old_state(self):
        menu.import_menu(self.args)
        before = self.snapshot()
        invalid_spice = dish()
        invalid_spice[5] = '非常辣'
        invalid_category = dish()
        invalid_category[3] = '新分类'
        missing_image = dish()
        missing_image[2] = '=_xlfn.DISPIMG("MISSING",1)'
        invalid_rows = [[dish(price='9.999')], [dish(price='NaN')], [dish(price='-1')],
                        [dish(), dish()], [invalid_spice], [invalid_category], [missing_image]]
        for rows in invalid_rows:
            workbook(self.source, rows)
            with self.assertRaises(ValueError):
                menu.import_menu(self.args)
            self.assertEqual(self.snapshot(), before)
        workbook(self.source, [dish(price='12')])
        with sqlite3.connect(self.args.db) as db:
            db.execute("CREATE TRIGGER fail_snapshot BEFORE INSERT ON app_snapshot BEGIN SELECT RAISE(ABORT,'injected failure'); END")
            manifest = db.execute('SELECT * FROM menu_imports').fetchall()
        with self.assertRaises(sqlite3.IntegrityError):
            menu.import_menu(self.args)
        self.assertEqual(self.snapshot(), before)
        with sqlite3.connect(self.args.db) as db:
            self.assertEqual(db.execute('SELECT * FROM menu_imports').fetchall(), manifest)

    def test_unknown_schema_and_ownership_conflicts_are_rejected(self):
        with sqlite3.connect(self.args.db) as db:
            db.execute('CREATE TABLE unrelated (id INTEGER)')
        with self.assertRaisesRegex(ValueError, '不是本导入器'):
            menu.import_menu(self.args)
        self.args.db = self.path / 'valid.sqlite'
        menu.import_menu(self.args)
        self.args.owner_id = 'different-owner'
        with self.assertRaisesRegex(ValueError, '归属'):
            menu.import_menu(self.args)
        self.args.owner_id = ''
        before = self.snapshot()
        before['schemaVersion'] = 99
        with sqlite3.connect(self.args.db) as db:
            db.execute('UPDATE app_snapshot SET payload_json=?', (menu.dumps(before),))
        with self.assertRaisesRegex(ValueError, 'schemaVersion'):
            menu.import_menu(self.args)
        self.assertEqual(self.snapshot()['schemaVersion'], 99)

    def test_short_code_collisions_are_rejected_without_writing(self):
        menu.import_menu(self.args)
        before = self.snapshot()
        before['sessions'] = [dict(id='room', roomCode=self.args.restaurant_code.lower())]
        with sqlite3.connect(self.args.db) as db:
            db.execute('UPDATE app_snapshot SET payload_json=?', (menu.dumps(before),))
        with self.assertRaisesRegex(ValueError, '聚餐码冲突'):
            menu.import_menu(self.args)
        self.assertEqual(self.snapshot(), before)
        before['sessions'] = []
        with sqlite3.connect(self.args.db) as db:
            db.execute('UPDATE app_snapshot SET payload_json=?', (menu.dumps(before),))
        self.args.restaurant_code = self.args.restaurant_code.lower()
        with self.assertRaisesRegex(ValueError, '大小写冲突'):
            menu.import_menu(self.args)
        self.assertEqual(self.snapshot(), before)

    def test_dry_run_writes_nothing_and_formula_is_not_executed(self):
        self.args.dry_run = True
        self.assertTrue(menu.import_menu(self.args)['dryRun'])
        self.assertFalse(self.args.db.exists())
        self.assertFalse(self.args.assets_dir.exists())
        self.assertEqual(menu.normalize_ingredients(' ， '), ['unknown'])
        row = dish()
        row[1] = '=1+1'
        workbook(self.source, [row])
        with self.assertRaisesRegex(ValueError, '公式'):
            menu.import_menu(self.args)

    def test_real_laoxiangji_workbook(self):
        source = ROOT / 'data/fixtures/老乡鸡菜谱.xlsx'
        dishes, assets, rows = menu.extract_menu(source, 'restaurant-test', '/menu-images')
        self.assertEqual(len(dishes), 84)
        self.assertEqual(len(assets), 83)
        self.assertEqual(len(rows), 84)
        self.assertEqual(len({d['id'] for d in dishes}), 84)
        self.assertTrue(all(d['imageUrl'] for d in dishes))
        self.assertEqual(next(d for d in dishes if d['name'] == '咸蛋狮子头')['priceFen'], 990)
        self.assertEqual(next(d for d in dishes if d['name'] == '蒸嫩豆腐')['priceFen'], 390)
        self.assertTrue(all(isinstance(d['priceFen'], int) and d['ingredients'] for d in dishes))


if __name__ == '__main__':
    unittest.main()
