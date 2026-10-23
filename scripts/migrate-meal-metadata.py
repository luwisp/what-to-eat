#!/usr/bin/env python3
"""Fill missing roles and repair imported noodle kinds without replacing merchant edits."""
import argparse
import json
import sqlite3
import tempfile
from importlib.util import spec_from_file_location, module_from_spec
from pathlib import Path


def noodle_repairs(db, snapshot):
    if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='menu_imports'").fetchone():
        return set()
    originals = {}
    for raw, in db.execute('SELECT source_rows_json FROM menu_imports'):
        for row in json.loads(raw):
            originals[row['dishId']] = row['original']
    facts = {fact['dishId']: fact for fact in snapshot.get('mealMetadata', [])}
    repairs = set()
    for dish in snapshot['dishes']:
        original = originals.get(dish['id'], {})
        fact = facts.get(dish['id'], {})
        if (original.get('名称') == dish['name'] and original.get('分类') == '面条'
                and dish['category'] == 'staple' and fact.get('role') == 'staple'
                and fact.get('stapleKind') == 'other'):
            repairs.add(dish['id'])
    return repairs


def migrate(path):
    spec = spec_from_file_location('metadata', Path(__file__).with_name('prepare-meal-metadata.py'))
    metadata = module_from_spec(spec)
    spec.loader.exec_module(metadata)
    with sqlite3.connect(path) as db:
        snapshot = json.loads(db.execute('SELECT payload_json FROM app_snapshot WHERE id=1').fetchone()[0])
        present = {fact['dishId'] for fact in snapshot.get('mealMetadata', [])}
        repairs = noodle_repairs(db, snapshot)
        targets = [restaurant for restaurant in snapshot['restaurants'] if any(
            dish['restaurantId'] == restaurant['id'] and (dish['id'] not in present or dish['id'] in repairs)
            for dish in snapshot['dishes'])]
        generated = []
        for restaurant in targets:
            with tempfile.TemporaryDirectory() as directory:
                generated.extend(metadata.prepare(path, Path(directory) / 'metadata.json',
                                                  restaurant['restaurantCode'])['dishes'])
        additions = [fact for fact in generated if fact['dishId'] not in present]
        corrections = {fact['dishId'] for fact in generated
                       if fact['dishId'] in repairs and fact['stapleKind'] == 'noodles'}
        if additions or corrections:
            db.execute('BEGIN IMMEDIATE')
            current = json.loads(db.execute('SELECT payload_json FROM app_snapshot WHERE id=1').fetchone()[0])
            if current != snapshot:
                raise RuntimeError('Snapshot changed during migration; stop the server and retry')
            for fact in snapshot.get('mealMetadata', []):
                if fact['dishId'] in corrections:
                    fact['stapleKind'] = 'noodles'
            snapshot.setdefault('mealMetadata', []).extend(additions)
            changed_ids = {fact['dishId'] for fact in additions} | corrections
            affected = {dish['restaurantId'] for dish in snapshot['dishes'] if dish['id'] in changed_ids}
            for version in snapshot['menuVersions']:
                if version['restaurantId'] in affected:
                    version['menuVersion'] += 1
            rooms = {session['id'] for session in snapshot['sessions'] if session['restaurantId'] in affected}
            for session in snapshot['sessions']:
                if session['id'] in rooms:
                    session['stateVersion'] += 1
                    session['recommendationInvalid'] = True
                    if session['state'] == 'recommended':
                        session['state'] = 'open'
            for recommendation in snapshot['recommendations']:
                if recommendation['sessionId'] in rooms:
                    recommendation['canConfirm'] = False
                    recommendation['accepted'] = False
            for job in snapshot['jobs']:
                if job['sessionId'] in rooms and job['status'] == 'inProgress':
                    job['status'] = 'cancelled'
            db.execute('UPDATE app_snapshot SET payload_json=? WHERE id=1',
                       (json.dumps(snapshot, ensure_ascii=False),))
            db.commit()
        print(f'Role metadata migration: {len(additions)} records added, {len(corrections)} noodle kinds corrected')


if __name__ == '__main__':
    cli = argparse.ArgumentParser()
    cli.add_argument('--db', type=Path, required=True)
    migrate(cli.parse_args().db)
