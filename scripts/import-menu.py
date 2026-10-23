#!/usr/bin/env python3
"""Offline import of an XLSX menu into the shared dining snapshot in SQLite (stdlib only)."""
import argparse
from collections import Counter
from contextlib import closing
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import posixpath
import re
import sqlite3
import sys
import time
import xml.etree.ElementTree as ET
import zipfile

S = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
R = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
XDR = '{http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing}'
A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'
PROJECT_ROOT = Path(__file__).resolve().parents[1]
APP_ID = 0x48574D49
COLLECTIONS = ('users merchants authSessions visitorSessions defaultSettings restaurants '
               'menuVersions dishes setMeals sessions participants recommendations '
               'chatMessages dedupeRecords jobs mealMetadata').split()
CATEGORIES = {'凉菜': 'cold', '热菜': 'hot', '汤': 'soup', '主食': 'staple',
              '饮品': 'drink', '饮料': 'drink', '面点': 'staple', '面条': 'staple',
              '馄饨': 'staple', '辅食': 'hot', '小吃': 'hot',
              **{k: k for k in ('cold', 'hot', 'soup', 'staple', 'drink')}}
SPICE = {'不辣': 0, '微辣': 1, '中辣': 2, '重辣': 3,
         **{str(i): i for i in range(4)}}
HEADERS = ['名称', '当前价格', '图片', '分类', '食材', '辣度', '口味', '烹饪方式', '简介']


def dumps(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True)


def stable_id(prefix, text):
    return prefix + hashlib.sha256(text.encode()).hexdigest()[:24]


def normalize_ingredients(text):
    values = []
    for part in re.split(r'[，,、；;\r\n]+', text):
        value = part.strip()
        if not value:
            continue
        if value.lower() == 'unknown':
            value = 'unknown'
        if value not in values:
            values.append(value)
    return values or ['unknown']


def price_fen(value):
    try:
        amount = Decimal(value)
        fen = amount * 100
        if not amount.is_finite() or amount < 0 or fen != fen.to_integral_value() or fen > 2**63 - 1:
            raise ValueError('价格须为非负金额且最多两位小数')
        return int(fen)
    except (InvalidOperation, ValueError, OverflowError) as exc:
        raise ValueError(f'非法价格 {value!r}') from exc


def package_target(base, target):
    # Never resolve external references or ZIP paths outside the workbook package.
    path = posixpath.normpath(posixpath.join(base, target))
    if path.startswith('../') or path.startswith('/') or '://' in path:
        raise ValueError('不安全的 Excel 资源路径')
    return path


def relationships(archive, path, base):
    return {item.attrib['Id']: package_target(base, item.attrib['Target'])
            for item in ET.fromstring(archive.read(path))
            if item.attrib.get('TargetMode') != 'External'}


def read_workbook(path, sheet=None):
    """Read cell values plus WPS DISPIMG assets, without executing any formula."""
    with zipfile.ZipFile(path) as archive:
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            strings = [''.join(n.text or '' for n in si.iter(S + 't'))
                       for si in ET.fromstring(archive.read('xl/sharedStrings.xml'))]
        workbook = ET.fromstring(archive.read('xl/workbook.xml'))
        sheets = workbook.find(S + 'sheets')
        selected = next((s for s in sheets if sheet is None or s.attrib['name'] == sheet), None)
        if selected is None:
            raise ValueError(f'找不到工作表 {sheet!r}')
        rels = relationships(archive, 'xl/_rels/workbook.xml.rels', 'xl')
        root = ET.fromstring(archive.read(rels[selected.attrib[R + 'id']]))
        images = {}
        if 'xl/cellimages.xml' in archive.namelist():
            image_rels = relationships(archive, 'xl/_rels/cellimages.xml.rels', 'xl')
            for pic in ET.fromstring(archive.read('xl/cellimages.xml')).iter(XDR + 'pic'):
                props = pic.find('.//' + XDR + 'cNvPr')
                blip = pic.find('.//' + A + 'blip')
                if props is not None and blip is not None:
                    target = image_rels.get(blip.attrib[R + 'embed'])
                    if target:
                        data = archive.read(target)
                        suffix = Path(target).suffix.lower()
                        if suffix not in ('.jpg', '.jpeg', '.png', '.gif', '.webp'):
                            raise ValueError(f'不支持的图片类型 {suffix}')
                        digest = hashlib.sha256(data).hexdigest()
                        images[props.attrib['name']] = (digest + suffix, data)
        result = []
        for row in root.findall('.//' + S + 'sheetData/' + S + 'row'):
            cells = {}
            for cell in row.findall(S + 'c'):
                column = re.sub(r'\d+', '', cell.attrib['r'])
                value = cell.find(S + 'v')
                text = (value.text or '') if value is not None else ''
                kind = cell.attrib.get('t')
                if kind == 's':
                    text = strings[int(text)]
                elif kind == 'inlineStr':
                    text = ''.join(n.text or '' for n in cell.iter(S + 't'))
                formula = cell.find(S + 'f')
                if formula is not None:
                    text = formula.text or ''
                    if 'DISPIMG(' not in text:
                        raise ValueError(f'单元格 {cell.attrib["r"]} 含不支持的公式，不使用可能过期的缓存值')
                cells[column] = text.strip()
            if any(cells.values()):
                result.append((int(row.attrib['r']), cells))
        return selected.attrib['name'], result, images


def extract_menu(path, restaurant_id, image_url_prefix, sheet=None):
    sheet_name, rows, image_map = read_workbook(path, sheet)
    if not rows:
        raise ValueError('工作表为空')
    columns = {value: col for col, value in rows[0][1].items()}
    missing = set(HEADERS) - columns.keys()
    if missing:
        raise ValueError('缺少表头: ' + ', '.join(sorted(missing)))
    dishes, assets, provenance, names = [], {}, [], set()
    for row_number, cells in rows[1:]:
        raw = {key: cells.get(columns[key], '') for key in HEADERS}
        try:
            name = raw['名称']
            if not name or name in names:
                raise ValueError('菜名为空或重复')
            names.add(name)
            if raw['分类'] not in CATEGORIES or raw['辣度'] not in SPICE:
                raise ValueError('未知分类或辣度，须显式补充映射')
            image = raw['图片']
            image_url = ''
            if image:
                match = re.fullmatch(r'=?\s*(?:_xlfn\.)?DISPIMG\("([^"]+)",\s*1\)', image)
                if not match or match[1] not in image_map:
                    raise ValueError('图片公式无效或找不到内嵌图片；不执行其他公式')
                filename, data = image_map[match[1]]
                assets[filename] = data
                image_url = image_url_prefix.rstrip('/') + '/' + filename
            dish = dict(id=stable_id('dish-', restaurant_id + '\0' + name), restaurantId=restaurant_id,
                        name=name, description=raw['简介'], taste=raw['口味'], cookingMethod=raw['烹饪方式'],
                        priceFen=price_fen(raw['当前价格']), imageUrl=image_url,
                        category=CATEGORIES[raw['分类']], ingredients=normalize_ingredients(raw['食材']),
                        spiceLevel=SPICE[raw['辣度']], available=True, isSignature=False)
            dishes.append(dish)
            provenance.append({'row': row_number, 'dishId': dish['id'], 'original': raw})
        except (ValueError, KeyError) as exc:
            raise ValueError(f'{sheet_name} 第 {row_number} 行 ({raw["名称"]}): {exc}') from exc
    if not dishes:
        raise ValueError('没有可导入的菜品')
    return dishes, assets, provenance


def init_database(connection):
    application_id = connection.execute('PRAGMA application_id').fetchone()[0]
    objects = connection.execute("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").fetchall()
    if objects and application_id != APP_ID:
        raise ValueError('目标数据库不是本导入器的快照格式，拒绝修改；请指定新 --db')
    if application_id == APP_ID and connection.execute('PRAGMA user_version').fetchone()[0] != 1:
        raise ValueError('不支持的导入数据库版本')
    if application_id not in (0, APP_ID):
        raise ValueError('目标 SQLite application_id 不匹配')
    connection.execute(f'PRAGMA application_id={APP_ID}')
    connection.execute('PRAGMA user_version=1')
    connection.execute('''CREATE TABLE IF NOT EXISTS app_snapshot (
        id INTEGER PRIMARY KEY CHECK(id=1), schema_version INTEGER NOT NULL CHECK(schema_version=1),
        payload_json TEXT NOT NULL CHECK(json_valid(payload_json)))''')
    connection.execute('''CREATE TABLE IF NOT EXISTS menu_imports (
        source_key TEXT PRIMARY KEY, restaurant_id TEXT NOT NULL, source_sha256 TEXT NOT NULL,
        dish_ids_json TEXT NOT NULL, source_rows_json TEXT NOT NULL, imported_at INTEGER NOT NULL)''')
    connection.execute('''CREATE TABLE IF NOT EXISTS menu_assets (
        filename TEXT PRIMARY KEY, content BLOB NOT NULL)''')
    # One canonical snapshot; these views are convenient SQL projections, not duplicated state.
    for view, collection, fields in [
        ('restaurants', 'restaurants', ['id', 'ownerId', 'restaurantCode', 'name', 'description']),
        ('dishes', 'dishes', ['id', 'restaurantId', 'name', 'description', 'taste', 'cookingMethod',
                             'priceFen', 'imageUrl', 'category', 'ingredients', 'spiceLevel', 'available', 'isSignature']),
        ('menu_versions', 'menuVersions', ['restaurantId', 'menuVersion'])]:
        columns = ','.join(f"json_extract(value, '$.{field}') AS [{field}]" for field in fields)
        connection.execute(f'''CREATE VIEW IF NOT EXISTS {view} AS SELECT {columns}
            FROM app_snapshot, json_each(app_snapshot.payload_json, '$.{collection}') WHERE app_snapshot.id=1''')


def validate_snapshot(snapshot):
    if snapshot.get('schemaVersion') != 1 or any(not isinstance(snapshot.get(k), list) for k in COLLECTIONS):
        raise ValueError('数据库快照 schemaVersion 或集合结构无效；不会重置数据库')


def import_menu(args):
    restaurant_id = stable_id('restaurant-', args.restaurant_code)
    dishes, assets, provenance = extract_menu(args.source, restaurant_id, args.image_url_prefix, args.sheet)
    source_sha = hashlib.sha256(args.source.read_bytes()).hexdigest()
    result = {'source': str(args.source), 'sourceSha256': source_sha, 'dishes': len(dishes),
              'images': len(assets), 'categories': dict(Counter(d['category'] for d in dishes)),
              'restaurantCode': args.restaurant_code, 'database': str(args.db)}
    if args.dry_run:
        return {**result, 'dryRun': True}
    args.db.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(args.db, timeout=30, isolation_level=None)) as connection:
        connection.execute('PRAGMA synchronous=FULL')
        connection.execute('BEGIN IMMEDIATE')
        try:
            init_database(connection)
            stored = connection.execute('SELECT payload_json FROM app_snapshot WHERE id=1').fetchone()
            snapshot = json.loads(stored[0]) if stored else {'schemaVersion': 1, **{k: [] for k in COLLECTIONS}}
            snapshot.setdefault("mealMetadata", [])
            validate_snapshot(snapshot)
            if any(r.get('roomCode', '').lower() == args.restaurant_code.lower() for r in snapshot['sessions']):
                raise ValueError('餐馆码与已有聚餐码冲突，请改用其他餐馆码')
            if any(r['restaurantCode'].lower() == args.restaurant_code.lower() and r['restaurantCode'] != args.restaurant_code for r in snapshot['restaurants']):
                raise ValueError('餐馆码与已有餐馆码大小写冲突')
            restaurant = next((r for r in snapshot['restaurants'] if r['restaurantCode'] == args.restaurant_code), None)
            previous = connection.execute('SELECT restaurant_id,dish_ids_json FROM menu_imports WHERE source_key=?',
                                          (args.source_key,)).fetchone()
            if restaurant and (not previous or previous[0] != restaurant['id']):
                raise ValueError('餐馆码已被其他来源占用；拒绝覆盖')
            if previous and previous[0] != restaurant_id:
                raise ValueError('source-key 已绑定其他餐馆，不能改绑')
            if args.owner_id and not any(m['id'] == args.owner_id for m in snapshot['merchants']):
                raise ValueError('归属校验失败：owner-id 必须是当前数据库中已存在的商家 ID')
            if restaurant and restaurant['ownerId'] != args.owner_id:
                raise ValueError('owner-id 与现有餐馆不一致；不允许通过导入脚本转移归属')
            desired = dict(id=restaurant_id, ownerId=args.owner_id, restaurantCode=args.restaurant_code,
                           name=args.restaurant_name, description=args.description)
            old_snapshot = dumps(snapshot)
            snapshot['restaurants'] = [r for r in snapshot['restaurants'] if r['id'] != restaurant_id] + [desired]
            old_ids = set(json.loads(previous[1])) if previous else set()
            new_ids = {d['id'] for d in dishes}
            others = []
            for dish in snapshot['dishes']:
                if dish['id'] in new_ids:
                    if dish['restaurantId'] != restaurant_id or dish['id'] not in old_ids:
                        raise ValueError('菜品 ID 冲突')
                    continue
                if dish['id'] in old_ids:
                    dish['available'] = False  # Retain references from historical rooms and set meals.
                others.append(dish)
            snapshot['dishes'] = others + dishes
            # Roles are derived from the imported original category, not the collapsed display category.
            reviewed = json.loads((PROJECT_ROOT / 'data/fixtures/meal-annotations.json').read_text()).get(args.restaurant_code, {})
            roles = {'热菜':'hotMain','凉菜':'coldMain','辅食':'side','小吃':'side','汤':'soup',
                     '主食':'staple','面点':'staple','面条':'staple','馄饨':'staple','饮料':'drink','饮品':'drink'}
            facts = []
            for d, source in zip(dishes, provenance):
                a = reviewed.get(d['name'], {})
                primary = [i for i in a.get('primaryIngredients', []) if i in d['ingredients']]
                facts.append(dict(dishId=d['id'],role=roles.get(source['original']['分类'],'unknown'),
                    vegetable=bool(a.get('vegetable',False)) and bool(primary),primaryIngredients=primary,
                    stapleUnits=a.get('stapleUnits'),stapleKind=a.get('stapleKind',
                        'noodles' if source['original']['分类'] == '面条' else 'other'),
                    soupGroupId=a.get('soupGroupId',''),servesMax=a.get('servesMax')))
            snapshot['mealMetadata'] = [f for f in snapshot['mealMetadata'] if f['dishId'] not in (old_ids | new_ids)] + facts
            # Compare independent of array ordering; reimporting the same menu is a no-op.
            before = json.loads(old_snapshot)
            changed = (sorted(before['restaurants'], key=lambda r: r['id']) != sorted(snapshot['restaurants'], key=lambda r: r['id'])
                       or sorted(before['dishes'], key=lambda d: d['id']) != sorted(snapshot['dishes'], key=lambda d: d['id'])
                       or sorted(before.get('mealMetadata', []), key=lambda f:f['dishId']) != sorted(snapshot['mealMetadata'], key=lambda f:f['dishId']))
            version = next((v for v in snapshot['menuVersions'] if v['restaurantId'] == restaurant_id), None)
            if version is None:
                version = {'restaurantId': restaurant_id, 'menuVersion': 0}
                snapshot['menuVersions'].append(version)
            if changed:
                version['menuVersion'] += 1
                # Offline importer cannot broadcast, but persisted recommendations must be invalidated.
                room_ids = set()
                for room in snapshot['sessions']:
                    if room['restaurantId'] == restaurant_id:
                        room_ids.add(room['id'])
                        room['stateVersion'] += 1
                        room['recommendationInvalid'] = True
                        if room['state'] == 'recommended':
                            room['state'] = 'open'
                for recommendation in snapshot['recommendations']:
                    if recommendation['sessionId'] in room_ids:
                        recommendation['canConfirm'] = False
                        recommendation['accepted'] = False
                for job in snapshot['jobs']:
                    if job['sessionId'] in room_ids and job['status'] == 'inProgress':
                        job['status'] = 'cancelled'
            connection.execute('INSERT OR REPLACE INTO app_snapshot VALUES(1,1,?)', (dumps(snapshot),))
            connection.execute('INSERT OR REPLACE INTO menu_imports VALUES(?,?,?,?,?,?)',
                               (args.source_key, restaurant_id, source_sha, dumps(sorted(new_ids | old_ids)),
                                dumps(provenance), int(time.time() * 1000)))
            connection.executemany('INSERT OR IGNORE INTO menu_assets VALUES(?,?)', assets.items())
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        if connection.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise ValueError('SQLite 完整性检查未通过')
        result.update(changed=changed, menuVersion=version['menuVersion'], restaurantId=restaurant_id)
        # These files are derived caches. SQLite remains sufficient to restore them after interruption.
        try:
            args.assets_dir.mkdir(parents=True, exist_ok=True)
            for filename, data in connection.execute('SELECT filename,content FROM menu_assets'):
                if not re.fullmatch(r'[a-f0-9]{64}\.(?:jpeg|jpg|png|gif|webp)', filename):
                    raise ValueError('数据库图片文件名无效')
                target = args.assets_dir / filename
                target.write_bytes(data)
            if args.snapshot_out:
                args.snapshot_out.parent.mkdir(parents=True, exist_ok=True)
                args.snapshot_out.write_text(dumps(snapshot) + '\n', encoding='utf-8')
        except (OSError, ValueError) as exc:
            raise ValueError(f'数据库已成功提交，但派生文件导出失败：{exc}；修复路径后重跑即可恢复') from exc
    return result


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--source', type=Path, default=PROJECT_ROOT / 'data/fixtures/老乡鸡菜谱.xlsx')
    cli.add_argument('--db', type=Path, default=PROJECT_ROOT / 'data/runtime/juxiaobao.sqlite')
    cli.add_argument('--sheet', help='默认读取第一个工作表')
    cli.add_argument('--source-key', default='laoxiangji-menu', help='稳定的导入来源标识')
    cli.add_argument('--restaurant-code', default='LAOXIANGJI')
    cli.add_argument('--restaurant-name', default='老乡鸡')
    cli.add_argument('--owner-id', default='', help='已有商家 ID；留空表示未分配，不创建账号')
    cli.add_argument('--description', default='老乡鸡是一家以中式快餐为特色的连锁餐饮品牌，从养土鸡起家，实现了从养殖到餐桌的全产业链模式。')
    cli.add_argument('--assets-dir', type=Path, default=PROJECT_ROOT / 'web/menu-images')
    cli.add_argument('--image-url-prefix', default='/menu-images')
    cli.add_argument('--snapshot-out', type=Path, help='可选导出完整 DatabaseSnapshot JSON')
    cli.add_argument('--dry-run', action='store_true', help='只校验和统计，不写数据库或图片')
    return cli


def main():
    args = parser().parse_args()
    if not re.fullmatch(r'[A-Za-z0-9-]{1,64}', args.restaurant_code):
        parser().error('restaurant-code 只能使用 1–64 位字母、数字、短横线')
    try:
        print(json.dumps(import_menu(args), ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, sqlite3.Error, zipfile.BadZipFile, ET.ParseError) as exc:
        print(f'导入失败: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
