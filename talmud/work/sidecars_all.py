"""Parallel study-sidecar builder (fast but non-volatile).

Splits the books into --jobs shards and runs one
`dart run tool/build_study_index.dart <epubs...> --out study` process per
shard (separate processes, separate memory). Each sidecar is written via
temp-file + rename inside the Dart tool, so Ctrl-C keeps finished books;
re-running with --skip-existing resumes. Default single-arg behaviour of
the Dart tool is unchanged.

Usage (from repository root):
    python talmud/work/sidecars_all.py --jobs 3 --skip-existing
    python talmud/work/sidecars_all.py --books Taanit,Temurah --jobs 2
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent import futures as cf
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent  # package root (pubspec.yaml lives here)
OUT = ROOT / 'outputs'
BOOKS = OUT / 'books'
STUDY = BOOKS / 'study'
TOOL = REPO / 'tool' / 'build_study_index.dart'

sys.path.insert(0, str(ROOT / 'work'))
from build import slug  # pure helper; importing build has no side effects

WROTE_RE = re.compile(r'^wrote\s+(.+?([a-z0-9-]+)\.study\.sqlite)\s+\(')
FAILED_RE = re.compile(r'^FAILED\s+(.+?):')


def load_order():
    config = json.loads((OUT / 'source-selection.json').read_text(encoding='utf-8'))
    return config['preferences']['masechta_order']


def paths_for(order):
    items = []
    missing = []
    for m in order:
        epub = BOOKS / f'{slug(m)}.epub'
        sidecar = STUDY / f'{slug(m)}.study.sqlite'
        if not epub.exists():
            missing.append(m)
        else:
            items.append((m, epub, sidecar))
    return items, missing


def needs_build(epub, sidecar):
    return not (
        sidecar.exists()
        and sidecar.stat().st_size > 0
        and sidecar.stat().st_mtime >= epub.stat().st_mtime
    )


def find_dart():
    # Windows: `dart` on PATH is flutter's dart.bat shim, which Python
    # cannot spawn directly — use the bundled SDK exe instead.
    found = shutil.which('dart')
    if found and found.lower().endswith('.exe') and os.path.isfile(found):
        return found
    candidates = []
    fr = os.environ.get('FLUTTER_ROOT')
    if fr:
        candidates.append(Path(fr) / 'bin' / 'cache' / 'dart-sdk' / 'bin' / 'dart.exe')
    candidates.append(Path.home() / 'flutter' / 'bin' / 'cache' / 'dart-sdk' / 'bin' / 'dart.exe')
    for c in candidates:
        if c.is_file():
            return str(c)
    return found or 'dart'


DART = find_dart()


def run_shard(shard):
    """Build one shard in a subprocess; return (done_slugs, failed, seconds, tail)."""
    t0 = time.time()
    epubs = [str(ep) for _, ep, _ in shard]
    run = subprocess.run(
        [DART, 'run', str(TOOL), *epubs,
         '--out', str(STUDY)],
        cwd=str(REPO),
        capture_output=True, text=True, encoding='utf-8', errors='replace',
    )
    dt = time.time() - t0
    done, failed = [], []
    for line in (run.stdout or '').splitlines():
        line = line.strip()
        wm = WROTE_RE.match(line)
        if wm:
            done.append(wm.group(2))
            continue
        fm = FAILED_RE.match(line)
        if fm:
            failed.append(fm.group(1))
    tail = ((run.stdout or '') + '\n' + (run.stderr or ''))[-2000:]
    return done, failed, run.returncode, dt, tail


def main():
    ap = argparse.ArgumentParser(
        description='Build study sidecars in parallel shards (resumable).')
    ap.add_argument('--jobs', type=int, default=3,
                    help='Concurrent shards (default 3; each holds a whole book in memory).')
    ap.add_argument('--skip-existing', action='store_true',
                    help='Skip books whose sidecar is newer than its EPUB.')
    ap.add_argument('--books', default=None,
                    help='Comma-separated masechta subset (default: all 37 in order).')
    args = ap.parse_args()

    order = load_order()
    if args.books:
        want = [b.strip() for b in args.books.split(',') if b.strip()]
        unknown = [b for b in want if b not in order]
        if unknown:
            ap.error(f'unknown masechtos: {", ".join(unknown)}')
        order = [m for m in order if m in want]
    items, missing = paths_for(order)
    if missing:
        print('missing EPUBs (build them first): ' + ', '.join(missing))
        raise SystemExit(1)
    todo = [(m, ep, sc) for m, ep, sc in items
            if not (args.skip_existing and not needs_build(ep, sc))]
    skipped = [m for m, _, _ in items if m not in {t[0] for t in todo}]
    print(f'{len(todo)} to build, {len(skipped)} skipped, '
          f'{args.jobs} jobs', flush=True)
    if not todo:
        return

    # Biggest-first round-robin so shards finish evenly.
    todo_sorted = sorted(todo, key=lambda t: t[1].stat().st_size, reverse=True)
    shards = [[] for _ in range(min(args.jobs, len(todo_sorted)))]
    for i, item in enumerate(todo_sorted):
        shards[i % len(shards)].append(item)
    shards = [s for s in shards if s]

    t_start = time.time()
    done_all, failed_all = [], []
    try:
        with cf.ThreadPoolExecutor(max_workers=len(shards)) as pool:
            future_of = {pool.submit(run_shard, s): s for s in shards}
            for i, fut in enumerate(cf.as_completed(future_of), 1):
                done, failed, rc, dt, tail = fut.result()
                done_all.extend(done)
                failed_all.extend(failed)
                el = time.time() - t_start
                if rc != 0 and not done:
                    print(f'[shard {i}/{len(shards)}] FAILED (rc={rc}, {dt:.0f}s)',
                          flush=True)
                    print(tail, flush=True)
                else:
                    print(f'[shard {i}/{len(shards)}] {len(done)} sidecars in '
                          f'{dt:.0f}s (elapsed {el / 60:.0f} min)', flush=True)
                    for f in failed:
                        print(f'  FAILED: {f}', flush=True)
    except KeyboardInterrupt:
        print('Interrupted — finished sidecars are kept. Re-run with '
              '--skip-existing to resume.', flush=True)
        raise SystemExit(130)

    fresh = sum(
        1 for m, ep, sc in items
        if sc.exists() and sc.stat().st_size > 0
        and sc.stat().st_mtime >= ep.stat().st_mtime
    )
    print(f'done: {len(done_all)} built, {len(skipped)} skipped, '
          f'{len(failed_all)} failed; {fresh}/{len(items)} sidecars fresh',
          flush=True)
    if failed_all:
        print('retry: ' + ', '.join(sorted(set(failed_all))), flush=True)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
