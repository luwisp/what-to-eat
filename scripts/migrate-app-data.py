#!/usr/bin/env python3
"""Copy the previous default database on first renamed startup; keep the source backup."""
import argparse
from contextlib import closing
from pathlib import Path
import os
import sqlite3
import tempfile

cli = argparse.ArgumentParser()
cli.add_argument('--db', type=Path, required=True)
args = cli.parse_args()
# Only the legacy default filename is recognized, never an arbitrary database.
legacy = args.db.with_name('huaiwei.sqlite')
if args.db.name == 'juxiaobao.sqlite' and not args.db.exists() and legacy.exists():
    args.db.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='juxiaobao-migrate-', suffix='.sqlite', dir=args.db.parent)
    os.close(fd)
    try:
        with closing(sqlite3.connect(legacy.resolve().as_uri() + '?mode=ro', uri=True)) as source:
            source.execute('SELECT schema_version,payload_json FROM app_snapshot WHERE id=1').fetchone()
            with closing(sqlite3.connect(temporary)) as target:
                source.backup(target)
                assert target.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        os.replace(temporary, args.db)
        print('Existing application database migrated; original backup retained.')
    finally:
        Path(temporary).unlink(missing_ok=True)
