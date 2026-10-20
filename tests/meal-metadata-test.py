#!/usr/bin/env python3
"""Check that role facts remain conservative when the imported menu changes."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('meal_metadata', ROOT / 'scripts/prepare-meal-metadata.py')
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.db = self.directory / 'menu.sqlite'
        shutil.copyfile(ROOT / 'data/runtime/huaiwei.sqlite', self.db)
        with sqlite3.connect(self.db) as db:
            self.snapshot = json.loads(db.execute('SELECT payload_json FROM app_snapshot WHERE id=1').fetchone()[0])

    def generate(self, edit=False):
        if edit:
            with sqlite3.connect(self.db) as db:
                db.execute('UPDATE app_snapshot SET payload_json=? WHERE id=1', (json.dumps(self.snapshot),))
        before = hashlib.sha256(self.db.read_bytes()).digest()
        output = self.directory / 'metadata.json'
        metadata.prepare(self.db, output, assets=self.directory / 'assets')
        self.assertEqual(hashlib.sha256(self.db.read_bytes()).digest(), before)
        return json.loads(output.read_text())

    def test_real_roles_and_user_confirmed_single_portions(self):
        facts = {f['dishId']: f for f in self.generate()['dishes']}
        dishes = {d['name']: d for d in self.snapshot['dishes']}
        self.assertEqual(len(facts), 84)
        self.assertEqual(facts[dishes['米饭']['id']]['stapleUnits'], 1)
        noodles = [f for f in facts.values() if f['stapleKind'] == 'noodles']
        self.assertTrue(noodles)
        self.assertTrue(all(f['stapleUnits'] == 1 for f in noodles))
        self.assertTrue(any(f['role'] == 'side' for f in facts.values()))
        for name, dish in dishes.items():
            fact = facts[dish['id']]
            expected = 2 if name == '金牌老母鸡汤中份' else 5 if name == '金牌老母鸡汤大份' else 1
            self.assertEqual(fact['servesMax'], expected, name)

    def test_renamed_or_recategorized_recipe_loses_source_role(self):
        dish = next(d for d in self.snapshot['dishes'] if d['category'] == 'hot')
        dish['name'] = '已修改配方的新菜'
        facts = self.generate(edit=True)['dishes']
        self.assertEqual(next(f for f in facts if f['dishId'] == dish['id'])['role'], 'unknown')

    def test_removed_ingredients_cannot_remain_positive_wish_facts(self):
        for dish in self.snapshot['dishes']:
            dish['ingredients'] = ['水']
        facts = self.generate(edit=True)['dishes']
        self.assertTrue(all(not f['primaryIngredients'] for f in facts))
        self.assertTrue(all(not f['vegetable'] for f in facts))


if __name__ == '__main__':
    unittest.main(verbosity=2)
