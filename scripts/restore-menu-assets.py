#!/usr/bin/env python3
"""Restore derived images after a frontend build without reimporting or changing menu data."""
import argparse,re,sqlite3
from pathlib import Path
cli=argparse.ArgumentParser()
cli.add_argument('--db',type=Path,default=Path('data/runtime/huaiwei.sqlite'))
cli.add_argument('--output',type=Path,default=Path('web/menu-images'))
args=cli.parse_args()
with sqlite3.connect(args.db.resolve().as_uri()+'?mode=ro',uri=True) as db:
    args.output.mkdir(parents=True,exist_ok=True)
    for name,content in db.execute('SELECT filename,content FROM menu_assets'):
        if not re.fullmatch(r'[a-f0-9]{64}\.(jpeg|jpg|png|gif|webp)',name): raise ValueError('Invalid image filename')
        (args.output/name).write_bytes(content)
