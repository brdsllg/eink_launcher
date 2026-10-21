"""Parallel Tanach EPUB generation driver (fast but non-volatile).

Every book is generated in its own worker process from work/tanach.sqlite, so
workers have separate database connections, separate memory, and separate
preview folders. A crash or Ctrl-C keeps finished books; re-run with
--skip-existing to resume. A full run rewrites outputs/full-coverage.json
(entries for skipped books are kept).

Run work/build.py (or `build.py --normalize-only`) first when the source text
changed; this script only redraws the books from the existing database.

Usage (from anywhere):
    python tanach/work/generate_all.py --workers 8 --skip-existing
    python tanach/work/generate_all.py --books Genesis,Psalms --workers 2
"""
import argparse
import json
import os
import sqlite3
import sys
import time
from concurrent import futures as cf
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'outputs'
BOOKS = OUT / 'books'
DB = ROOT / 'work' / 'tanach.sqlite'

sys.path.insert(0, str(ROOT / 'work'))
from build import BOOK_ORDER, generate, slug  # noqa: E402  (import has no side effects)


def auto_workers():
    # Half the logical cores, capped at 8: each book process is small
    # (roughly 100-300 MB) and leaves room for the rest of the laptop.
    return max(1, min(8, (os.cpu_count() or 4) // 2))


def epub_path(book):
    idx = BOOK_ORDER.index(book) + 1
    return BOOKS / f'{idx:02d}-{slug(book)}.epub'


def needs_build(book, db_mtime):
    epub = epub_path(book)
    return not (
        epub.exists()
        and epub.stat().st_size > 0
        and epub.stat().st_mtime >= db_mtime
    )


def run_one(book):
    """Build one book in this process; return (book, entry, seconds)."""
    t0 = time.time()
    conn = sqlite3.connect(str(DB))
    try:
        conn.row_factory = sqlite3.Row
        editions = {r['id']: dict(r) for r in conn.execute('SELECT * FROM editions')}
        chapters = [r[0] for r in conn.execute(
            'SELECT DISTINCT chapter FROM verses WHERE book=? ORDER BY chapter', (book,))]
        if not chapters:
            raise RuntimeError(f'no verses for {book}; run build.py first')
        summary = generate(conn, editions, {book: chapters}, books=[book])
    finally:
        conn.close()
    return book, summary[0], time.time() - t0


def write_coverage(entries):
    path = OUT / 'full-coverage.json'
    prev = {}
    if path.exists():
        try:
            for old in json.loads(path.read_text(encoding='utf-8')):
                prev[old.get('book')] = old
        except ValueError:
            pass
    prev.update(entries)
    merged = [prev[b] for b in BOOK_ORDER if b in prev]
    path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding='utf-8')


def main():
    ap = argparse.ArgumentParser(
        description='Build Tanach EPUBs in parallel from tanach.sqlite (resumable).')
    ap.add_argument('--workers', type=int, default=0,
                    help='Concurrent books (default: auto, capped at 8; 1 = sequential).')
    ap.add_argument('--skip-existing', action='store_true',
                    help='Skip books whose EPUB is newer than tanach.sqlite.')
    ap.add_argument('--books', default=None,
                    help='Comma-separated subset (default: all books in order).')
    args = ap.parse_args()

    workers = args.workers if args.workers > 0 else auto_workers()
    order = list(BOOK_ORDER)
    if args.books:
        want = [b.strip() for b in args.books.split(',') if b.strip()]
        unknown = [b for b in want if b not in order]
        if unknown:
            ap.error(f'unknown books: {", ".join(unknown)}')
        order = [b for b in order if b in want]
    if not DB.exists():
        ap.error(f'missing {DB}; run build.py first')

    db_mtime = DB.stat().st_mtime
    todo = [b for b in order
            if not (args.skip_existing and not needs_build(b, db_mtime))]
    skipped = [b for b in order if b not in todo]
    print(f'{len(todo)} to build, {len(skipped)} skipped, {workers} workers',
          flush=True)
    if not todo:
        write_coverage({})
        return

    t_start = time.time()
    entries = {}
    failures = []
    try:
        with cf.ProcessPoolExecutor(max_workers=min(workers, len(todo))) as pool:
            future_of = {pool.submit(run_one, book): book for book in todo}
            for i, fut in enumerate(cf.as_completed(future_of), 1):
                book = future_of[fut]
                try:
                    book, entry, dt = fut.result()
                except Exception as exc:  # noqa: BLE001 - report and keep going
                    failures.append(book)
                    print(f'[{i}/{len(todo)}] {book} FAILED: {exc}', flush=True)
                    continue
                entries[book] = entry
                el = time.time() - t_start
                eta = el / i * (len(todo) - i) / 60
                print(f'[{i}/{len(todo)}] {book}: {entry["verses"]} verses, '
                      f'{entry["notes"]} notes in {dt:.1f}s '
                      f'(elapsed {el / 60:.1f} min, ~{eta:.1f} min left)',
                      flush=True)
    except KeyboardInterrupt:
        print('Interrupted — finished books are kept. Re-run with '
              '--skip-existing to resume.', flush=True)
        raise SystemExit(130)

    if entries:
        write_coverage(entries)
    print(f'done: {len(entries)} built, {len(skipped)} skipped, '
          f'{len(failures)} failed in {(time.time() - t_start) / 60:.1f} min',
          flush=True)
    if failures:
        print('retry: ' + ', '.join(failures), flush=True)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
