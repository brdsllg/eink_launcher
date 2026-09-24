"""Measure chapter XHTML gzip size and host decompression time in built EPUBs."""

import argparse
import gzip
import json
import time
import zipfile
from pathlib import Path

from sync import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--level', type=int, choices=range(1, 10), default=6)
    args = parser.parse_args()
    totals = {'chapters': 0, 'raw_bytes': 0, 'gzip_bytes': 0,
              'encode_seconds': 0.0, 'decode_seconds': 0.0}
    largest = []
    for book in sorted((ROOT / 'outputs/books').glob('*.epub')):
        with zipfile.ZipFile(book) as epub:
            for name in epub.namelist():
                if not (name.startswith('EPUB/chapter-') and name.endswith('.xhtml')):
                    continue
                raw = epub.read(name)
                start = time.perf_counter()
                packed = gzip.compress(raw, compresslevel=args.level)
                totals['encode_seconds'] += time.perf_counter() - start
                start = time.perf_counter()
                assert gzip.decompress(packed) == raw
                totals['decode_seconds'] += time.perf_counter() - start
                totals['chapters'] += 1
                totals['raw_bytes'] += len(raw)
                totals['gzip_bytes'] += len(packed)
                largest.append((len(raw), len(packed), book.name, name))
    if not totals['chapters']:
        parser.error('No chapter XHTML files found in outputs/books')
    print(json.dumps({
        'gzip_level': args.level,
        **totals,
        'largest_chapters': [
            {'raw_bytes': raw, 'gzip_bytes': packed, 'book': book, 'path': path}
            for raw, packed, book, path in sorted(largest, reverse=True)[:5]
        ],
    }, indent=2))


if __name__ == '__main__':
    main()
