"""Download public Sefaria data with content hashes; downstream build is offline.

Usage (from repository root):
    python talmud/work/sync.py catalog
    python talmud/work/sync.py schemas
    python talmud/work/sync.py texts
    python talmud/work/sync.py links
    python talmud/work/sync.py java       # downloads Java runtime for EPUBCheck
    python talmud/work/sync.py epubcheck  # downloads EPUBCheck jar

Mirrors tanach/work/sync.py.  All files are cached with SHA-256 sidecars so
subsequent runs are no-ops for already-cached files.
"""
import concurrent.futures as cf
import datetime
import hashlib
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'work' / 'cache'
BASE = 'https://storage.googleapis.com/sefaria-export/'


def fetch(url, path):
    """Download url to path, writing a .meta.json sidecar. No-op if both exist."""
    path.parent.mkdir(parents=True, exist_ok=True)
    meta_path = path.with_suffix(path.suffix + '.meta.json')
    if path.exists() and meta_path.exists():
        return json.loads(meta_path.read_text())
    for attempt in range(3):
        try:
            req = urllib.request.Request(
                url, headers={'User-Agent': 'Personal-Talmud-EPUB/0.1'}
            )
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
                meta = dict(
                    url=url,
                    sha256=hashlib.sha256(data).hexdigest(),
                    bytes=len(data),
                    fetched_at=datetime.datetime.now(
                        datetime.timezone.utc
                    ).isoformat(),
                    etag=r.headers.get('ETag'),
                    last_modified=r.headers.get('Last-Modified'),
                )
            temp = path.with_suffix(path.suffix + '.part')
            temp.write_bytes(data)
            temp.replace(path)
            meta_path.write_text(json.dumps(meta, indent=2))
            return meta
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def key(value):
    """Short stable key derived from a string (URL or title)."""
    return hashlib.sha256(value.encode()).hexdigest()[:24]


def batch(items):
    failures = []
    with cf.ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(fetch, u, p): (u, p) for u, p in items}
        for i, f in enumerate(cf.as_completed(futures), 1):
            u, p = futures[f]
            try:
                f.result()
            except Exception as ex:
                failures.append(dict(url=u, path=str(p), error=str(ex)))
            if i % 50 == 0:
                print(f'{i}/{len(futures)} downloaded or cached', flush=True)
    print(
        f'Finished {len(futures)} requests; failures: {len(failures)}', flush=True
    )
    return failures


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else ''

    if mode == 'catalog':
        failures = batch([
            (
                'https://raw.githubusercontent.com/Sefaria/Sefaria-Export/master/books.json',
                CACHE / 'books.json',
            ),
            (
                BASE + 'table_of_contents.json',
                CACHE / 'table_of_contents.json',
            ),
        ])
        if failures:
            raise RuntimeError(failures)
        raise SystemExit(0)

    if mode in ('java', 'epubcheck'):
        # Reuse already-unpacked tools from either segment; otherwise cache the
        # release metadata and delegate the download+unpack to tanach's
        # installer so both segments share one code path.
        import subprocess

        def usable(binary, dest):
            pats = ('java.exe', 'java') if binary == 'java' else (binary,)
            return any(p.is_file() for pat in pats for p in dest.rglob(pat))

        tanach_tools = ROOT.parent / 'tanach' / 'work' / 'tools'
        tools = ROOT / 'work' / 'tools'
        binary = 'java' if mode == 'java' else 'epubcheck.jar'
        for base in (tools, tanach_tools):
            if usable(binary, base):
                print(f'Using existing {mode} from {base}', flush=True)
                raise SystemExit(0)
        # Download release metadata then the actual archive.
        release_url = (
            'https://api.github.com/repos/adoptium/temurin21-binaries/releases/latest'
            if mode == 'java'
            else 'https://api.github.com/repos/w3c/epubcheck/releases/latest'
        )
        meta_path = CACHE / f'{mode}-release.json'
        failures = batch([(release_url, meta_path)])
        if failures:
            raise RuntimeError(failures)
        print(f'{mode} release metadata cached at {meta_path}', flush=True)
        installer = ROOT.parent / 'tanach' / 'work' / 'get_validation_tools.py'
        run = subprocess.run([sys.executable, str(installer), '--tools-dir', str(tools)])
        raise SystemExit(run.returncode)

    # For schemas / texts / links we need the source-selection config.
    config_path = ROOT / 'outputs' / 'source-selection.json'
    if not config_path.exists():
        print(
            'ERROR: Run inventory.py first to create outputs/source-selection.json',
            file=sys.stderr,
        )
        raise SystemExit(1)
    config = json.loads(config_path.read_text(encoding='utf-8'))

    if mode == 'inspect':
        # Quick sanity-check fetch of a few items.
        items = [
            (
                BASE + 'schemas/' + urllib.parse.quote(t.replace(' ', '_'), safe='') + '.json',
                CACHE / 'schemas' / f'{key(t)}.json',
            )
            for t in ['Rashi on Berakhot', 'Berakhot', 'Tosafot on Berakhot']
        ]
        items.append((
            'https://storage.googleapis.com/storage/v1/b/sefaria-export/o'
            '?prefix=links%2F&fields=items(name,size,generation),nextPageToken',
            CACHE / 'link-list.json',
        ))

    elif mode == 'schemas':
        masechta_titles = config['preferences']['masechta_order']
        commentary_titles = [
            s['title'] for s in config['sources'] if s['status'] == 'include'
        ]
        all_titles = masechta_titles + commentary_titles
        items = [
            (
                BASE + 'schemas/' + urllib.parse.quote(t.replace(' ', '_'), safe='') + '.json',
                CACHE / 'schemas' / f'{key(t)}.json',
            )
            for t in all_titles
        ]

    elif mode == 'texts':
        plan_path = CACHE / 'download-plan.json'
        if not plan_path.exists():
            print(
                'ERROR: Run inventory.py first to create work/cache/download-plan.json',
                file=sys.stderr,
            )
            raise SystemExit(1)
        plan = json.loads(plan_path.read_text(encoding='utf-8'))
        items = [
            (b['json_url'], CACHE / 'texts' / f"{key(b['json_url'])}.json")
            for b in plan
        ]

    elif mode == 'links':
        link_list_path = CACHE / 'link-list.json'
        if not link_list_path.exists():
            print(
                'ERROR: Run sync.py inspect first to cache the link listing',
                file=sys.stderr,
            )
            raise SystemExit(1)
        listing = json.loads(link_list_path.read_text())
        if listing.get('nextPageToken'):
            raise RuntimeError('Paginate bucket listing before downloading links')
        import re
        items = [
            (
                BASE + x['name'] + '?generation=' + x['generation'],
                CACHE / x['name'],
            )
            for x in listing['items']
            if re.fullmatch(r'links/links\d+\.csv', x['name'])
        ]

    else:
        print(
            f'Unknown mode {mode!r}. Valid: catalog inspect schemas texts links java epubcheck',
            file=sys.stderr,
        )
        raise SystemExit(1)

    failures = batch(items)
    (CACHE / f'{mode}-failures.json').write_text(json.dumps(failures, indent=2))
    if failures:
        print(f'WARNING: {len(failures)} failures written to {mode}-failures.json')
