"""Rebuild Talmud EPUBs from the normalized SQLite without re-normalizing.

Use for single-masechta rebuilds after the first full build.  If the source
data has changed (new Sefaria fetch), run build.py instead.

Usage:
  python talmud/work/regenerate.py --masechta Berakhot
  python talmud/work/regenerate.py --masechta "Bava Metzia"
  python talmud/work/regenerate.py               # regenerate all masechtos
"""
import argparse
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'outputs'


def main():
    config_path = OUT / 'source-selection.json'
    if not config_path.exists():
        print('ERROR: Run inventory.py first.')
        raise __import__('sys').exit(1)
    config = json.loads(config_path.read_text(encoding='utf-8'))
    masechta_order = config['preferences']['masechta_order']

    parser = argparse.ArgumentParser(
        description='Rebuild Talmud EPUBs from existing talmud.sqlite.'
    )
    parser.add_argument(
        '--masechta', choices=masechta_order,
        help='Rebuild one masechta without replacing full-coverage.json.',
    )
    args = parser.parse_args()

    # Patch build module config
    import build as bm
    bm._require_config()
    bm.MASECHTA_ORDER = masechta_order

    dbpath = ROOT / 'work' / 'talmud.sqlite'
    with sqlite3.connect(dbpath) as conn:
        conn.row_factory = sqlite3.Row
        editions = {r['id']: dict(r) for r in conn.execute('SELECT * FROM editions')}
        masechtos = [args.masechta] if args.masechta else None
        bm.generate(conn, editions, masechtos=masechtos)


if __name__ == '__main__':
    main()
