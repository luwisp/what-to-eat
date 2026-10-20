#!/usr/bin/env python3
"""Fill missing role records in older snapshots without reimporting dishes or changing merchant edits."""
import argparse,json,sqlite3,tempfile
from pathlib import Path
from importlib.util import spec_from_file_location,module_from_spec
cli=argparse.ArgumentParser();cli.add_argument('--db',type=Path,required=True);args=cli.parse_args()
spec=spec_from_file_location('metadata',Path(__file__).with_name('prepare-meal-metadata.py'));mod=module_from_spec(spec);spec.loader.exec_module(mod)
with sqlite3.connect(args.db) as db:
    snapshot=json.loads(db.execute('SELECT payload_json FROM app_snapshot WHERE id=1').fetchone()[0])
    present={f['dishId'] for f in snapshot.get('mealMetadata',[])}
    missing=[r for r in snapshot['restaurants'] if any(d['restaurantId']==r['id'] and d['id'] not in present for d in snapshot['dishes'])]
    generated=[]
    for r in missing:
        with tempfile.TemporaryDirectory() as directory:
            generated.extend(mod.prepare(args.db,Path(directory)/'metadata.json',r['restaurantCode'])['dishes'])
    generated=[f for f in generated if f['dishId'] not in present]
    if generated:
        db.execute('BEGIN IMMEDIATE')
        # Guard against an external writer between generation and commit.
        current=json.loads(db.execute('SELECT payload_json FROM app_snapshot WHERE id=1').fetchone()[0])
        if current!=snapshot:raise RuntimeError('Snapshot changed during migration; stop the server and retry')
        snapshot.setdefault('mealMetadata',[]).extend(generated)
        affected={d['restaurantId'] for d in snapshot['dishes'] if d['id'] in {f['dishId'] for f in generated}}
        for version in snapshot['menuVersions']:
            if version['restaurantId'] in affected:version['menuVersion']+=1
        rooms={s['id'] for s in snapshot['sessions'] if s['restaurantId'] in affected}
        for s in snapshot['sessions']:
            if s['id'] in rooms:
                s['stateVersion']+=1;s['recommendationInvalid']=True
                if s['state']=='recommended':s['state']='open'
        for r in snapshot['recommendations']:
            if r['sessionId'] in rooms:r['canConfirm']=False;r['accepted']=False
        for j in snapshot['jobs']:
            if j['sessionId'] in rooms and j['status']=='inProgress':j['status']='cancelled'
        db.execute('UPDATE app_snapshot SET payload_json=? WHERE id=1',(json.dumps(snapshot,ensure_ascii=False),))
        db.commit()
    print(f'Role metadata migration: {len(generated)} records added')
