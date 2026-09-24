import argparse
import sqlite3
from build import BOOK_ORDER, ROOT, generate


def main():
    parser = argparse.ArgumentParser(
        description='Rebuild Tanach EPUBs from the normalized SQLite database.'
    )
    parser.add_argument(
        '--book', choices=BOOK_ORDER,
        help='Rebuild one book without replacing full-coverage.json.',
    )
    args = parser.parse_args()
    with sqlite3.connect(ROOT / 'work/tanach.sqlite') as conn:
        conn.row_factory = sqlite3.Row
        editions = {row['id']: dict(row) for row in conn.execute('SELECT * FROM editions')}
        generate(conn, editions, books=[args.book] if args.book else None)


if __name__ == '__main__':
    main()
