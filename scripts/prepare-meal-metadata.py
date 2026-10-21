#!/usr/bin/env python3
"""Build version-bound v3 role facts from the imported source and reviewed annotations."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3

ROOT = Path(__file__).resolve().parents[1]


def prepare(db_path, output, code='LAOXIANGJI', assets=None):
    reviewed = json.loads((ROOT / 'data/fixtures/meal-annotations.json').read_text())
    with sqlite3.connect(Path(db_path).resolve().as_uri() + '?mode=ro', uri=True) as db:
        snapshot = json.loads(db.execute('SELECT payload_json FROM app_snapshot WHERE id=1 AND schema_version=1').fetchone()[0])
        restaurant = next(r for r in snapshot['restaurants'] if r['restaurantCode'] == code)
        rid = restaurant['id']
        versions = {v['restaurantId']: v['menuVersion'] for v in snapshot['menuVersions']}
        imported = {}
        for raw, in db.execute('SELECT source_rows_json FROM menu_imports WHERE restaurant_id=?', (rid,)):
            for row in json.loads(raw):
                imported[row['dishId']] = row['original']
        roles = {'热菜': 'hotMain', '凉菜': 'coldMain', '汤': 'soup', '饮品': 'drink', '饮料': 'drink',
                 '辅食': 'side', '小吃': 'side', '主食': 'staple', '面点': 'staple', '面条': 'staple', '馄饨': 'staple'}
        facts = []
        for d in snapshot['dishes']:
            if d['restaurantId'] != rid:
                continue
            original = imported.get(d['id'], {})
            annotation = reviewed.get(code, {}).get(d['name'], {})
            # Stale original classifications cannot silently become facts for an edited menu.
            source_category = original.get('分类') if original.get('名称') == d['name'] else None
            transport = {'hotMain': 'hot', 'coldMain': 'cold', 'staple': 'staple', 'soup': 'soup', 'drink': 'drink', 'side': 'hot'}
            role = roles.get(source_category, 'unknown')
            if transport.get(role) != d['category']:
                role = 'unknown'
            primary = [x for x in annotation.get('primaryIngredients', []) if x in d['ingredients']]
            facts.append(dict(dishId=d['id'], role=role,
                              vegetable=bool(annotation.get('vegetable', False)) and bool(primary),
                              primaryIngredients=primary,
                              stapleUnits=annotation.get('stapleUnits') if role == 'staple' else None,
                              stapleKind=annotation.get('stapleKind', 'noodles' if source_category == '面条' else 'other'),
                              soupGroupId=annotation.get('soupGroupId', ''),
                              servesMax=annotation.get('servesMax') if role != 'unknown' else None,
                              source='原表分类＋人工核对主料/角色；' + annotation.get('portionSource', '规格仅记录显式注释')))
        result = dict(restaurantId=rid, menuVersion=versions[rid], dishes=facts)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        if assets:
            assets.mkdir(parents=True, exist_ok=True)
            for filename, content in db.execute('SELECT filename,content FROM menu_assets'):
                if not re.fullmatch(r'[a-f0-9]{64}\.(jpeg|jpg|png|gif|webp)', filename):
                    raise ValueError('Invalid image filename')
                path = assets / filename
                if not path.exists() or hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(content).digest():
                    path.write_bytes(content)
        return result


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--db', type=Path, default=ROOT / 'data/runtime/juxiaobao.sqlite')
    cli.add_argument('--output', type=Path, default=ROOT / 'data/runtime/meal-metadata.json')
    cli.add_argument('--restaurant-code', default='LAOXIANGJI')
    args = cli.parse_args()
    result = prepare(args.db, args.output, args.restaurant_code, ROOT / 'web/menu-images')
    print(f"Prepared {len(result['dishes'])} role records at menu version {result['menuVersion']} (SQLite read-only)")
