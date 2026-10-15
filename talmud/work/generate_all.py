"""Parallel Talmud EPUB generation driver (fast but non-volatile).

Each book builds in its own `regenerate.py --masechta X` subprocess, so
workers get separate processes, separate read-only DB connections, and the
atomic EPUB rename from build.py. A crash or Ctrl-C keeps finished books;
re-running with --skip-existing resumes. Writes a merged
full-coverage.json at the end (previous entries kept for skipped books).

Usage (from repository root):
    python talmud/work/generate_all.py --workers 6 --skip-existing
    python talmud/work/generate_all.py --books Meilah,Tamid --workers 2
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from concurrent import futures as cf
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'outputs'
BOOKS = OUT / 'books'
DB = ROOT / 'work' / 'talmud.sqlite'

sys.path.insert(0, str(ROOT / 'work'))
from build import slug  # pure helper; importing build has no side effects

LINE_RE = re.compile(
    r'^(?P<m>.+): (?P<amudim>\d+) amudim, (?P<notes>\d+) notes -> (?P<epub>\S+)$'
)


def auto_workers():
    # Laptop-max with headroom: all but 2 cores, capped at 6 so six
    # ~300MB workers (~2GB) stay far under typical RAM and thermals.
    return max(1, min(6, (os.cpu_count() or 4) - 2))


def load_order():
    config = json.loads((OUT / 'source-selection.json').read_text(encoding='utf-8'))
    return config['preferences']['masechta_order']


def total_notes():
    try:
        report = json.loads((OUT / 'build-report.json').read_text(encoding='utf-8'))
        return int(report.get('notes') or 0)
    except (OSError, ValueError):
        return 0


def needs_build(m, db_mtime):
    epub = BOOKS / f'{slug(m)}.epub'
    return not (
        epub.exists()
        and epub.stat().st_size > 0
        and epub.stat().st_mtime >= db_mtime
    )


def run_one(m):
    """Build one book in a subprocess; return (m, rc, seconds, entry, out, err)."""
    t0 = time.time()
    run = subprocess.run(
        [sys.executable, str(ROOT / 'work' / 'regenerate.py'),
         '--masechta', m],
        capture_output=True, text=True, encoding='utf-8', errors='replace',
    )
    dt = time.time() - t0
    entry = None
    for line in (run.stdout or '').splitlines():
        mt = LINE_RE.match(line.strip())
        if mt and mt.group('m') == m:
            ep = BOOKS / mt.group('epub')
            entry = dict(
                masechta=m, amudim=int(mt.group('amudim')),
                notes=int(mt.group('notes')), epub=mt.group('epub'),
                epub_bytes=ep.stat().st_size if ep.exists() else 0,
            )
    return m, run.returncode, dt, entry, (run.stdout or '')[-1500:], (run.stderr or '')[-1500:]


def main():
    ap = argparse.ArgumentParser(
        description='Build Talmud EPUBs in parallel from talmud.sqlite (resumable).')
    ap.add_argument('--workers', type=int, default=0,
                    help='Concurrent books (default: auto, capped at 6; 1 = sequential).')
    ap.add_argument('--skip-existing', action='store_true',
                    help='Skip books whose EPUB is newer than talmud.sqlite.')
    ap.add_argument('--books', default=None,
                    help='Comma-separated subset (default: all 37 in order).')
    args = ap.parse_args()

    workers = args.workers if args.workers > 0 else auto_workers()
    order = load_order()
    if args.books:
        want = [b.strip() for b in args.books.split(',') if b.strip()]
        unknown = [b for b in want if b not in order]
        if unknown:
            ap.error(f'unknown masechtos: {", ".join(unknown)}')
        order = [m for m in order if m in want]
    db_mtime = DB.stat().st_mtime
    todo = [m for m in order
            if not (args.skip_existing and not needs_build(m, db_mtime))]
    skipped = [m for m in order if m not in todo]
    print(f'{len(todo)} to build, {len(skipped)} skipped, '
          f'{workers} workers', flush=True)
    if not todo:
        return

    grand_total = total_notes()
    done_notes = 0
    t_start = time.time()
    entries = {}
    failures = []
    try:
        with cf.ThreadPoolExecutor(max_workers=workers) as pool:
            future_of = {pool.submit(run_one, m): m for m in todo}
            for i, fut in enumerate(cf.as_completed(future_of), 1):
                m, rc, dt, entry, tail_out, tail_err = fut.result()
                if rc == 0 and entry is not None:
                    entries[m] = entry
                    done_notes += entry['notes']
                    el = time.time() - t_start
                    eta = ''
                    if grand_total and done_notes:
                        eta = (f', ETA {el / done_notes * (grand_total - done_notes) / 60:.0f} min')
                    print(f'[{i}/{len(todo)}] {m}: {entry["amudim"]} amudim, '
                          f'{entry["notes"]} notes in {dt:.0f}s '
                          f'(elapsed {el / 60:.0f} min{eta})', flush=True)
                else:
                    failures.append(m)
                    print(f'[{i}/{len(todo)}] {m} FAILED (rc={rc}, {dt:.0f}s)',
                          flush=True)
                    if tail_err.strip():
                        print(tail_err, flush=True)
                    elif tail_out.strip():
                        print(tail_out, flush=True)
    except KeyboardInterrupt:
        print('Interrupted — finished books are kept. Re-run with '
              '--skip-existing to resume.', flush=True)
        raise SystemExit(130)

    # Merged coverage: fresh entries plus previous entries for skipped books.
    prev = {}
    cov_path = OUT / 'full-coverage.json'
    if cov_path.exists():
        try:
            for e in json.loads(cov_path.read_text(encoding='utf-8')):
                prev[e.get('masechta')] = e
        except ValueError:
            pass
    merged = []
    for m in load_order():
        if m in entries:
            merged.append(entries[m])
        elif m in prev:
            merged.append(prev[m])
    if entries:
        cov_path.write_text(
            json.dumps(merged, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'done: {len(entries)} built, {len(skipped)} skipped, '
          f'{len(failures)} failed', flush=True)
    if failures:
        print('retry: ' + ', '.join(failures), flush=True)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
