"""Verify no cantillation marks remain in generated EPUB Hebrew text blocks.

Cantillation (U+0591–U+05AF) should have been stripped during normalization.
Nikud (U+05B0–U+05C7) must be preserved.

Exits with code 1 if any violations are found.

Usage:
  python talmud/work/audit_hebrew.py
  python talmud/work/audit_hebrew.py --pilot
"""
import argparse
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'outputs'
BOOKS = OUT / 'books'
NS = '{http://www.w3.org/1999/xhtml}'
CANTILLATION = re.compile('[\u0591-\u05af]')
HEBREW_LETTERS = re.compile('[\u05d0-\u05ea]')


def check_epub(p):
    violations = []
    with zipfile.ZipFile(p) as z:
        for name in z.namelist():
            if not name.endswith('.xhtml'):
                continue
            root = ET.fromstring(z.read(name))
            for node in root.iter():
                classes = node.attrib.get('class', '').split()
                if 'hebrew' in classes or 'note-he' in classes:
                    text = ''.join(node.itertext())
                    if CANTILLATION.search(text):
                        # Report a snippet
                        snippet = text[:80].replace('\n', ' ')
                        violations.append(
                            f'{p.name}: {name}: cantillation in .{" .".join(classes)!r}: {snippet!r}'
                        )
                    # Warn if a Hebrew-class block has no Hebrew letters at all
                    if not HEBREW_LETTERS.search(text) and text.strip():
                        violations.append(
                            f'{p.name}: {name}: hebrew-class block with no Hebrew letters: {text[:40]!r}'
                        )
    return violations


def main():
    parser = argparse.ArgumentParser(description='Audit Hebrew blocks in Talmud EPUBs.')
    parser.add_argument('--pilot', action='store_true')
    args = parser.parse_args()

    if args.pilot:
        import json
        config = json.loads((OUT / 'source-selection.json').read_text(encoding='utf-8'))
        from build import slug
        pilot = set(config['preferences'].get('pilot_masechtos', []))
        epub_paths = [BOOKS / f'{slug(m)}.epub' for m in pilot if (BOOKS / f'{slug(m)}.epub').exists()]
    else:
        epub_paths = sorted(BOOKS.glob('*.epub'))

    all_violations = []
    for p in epub_paths:
        v = check_epub(p)
        all_violations.extend(v)

    if all_violations:
        print(f'{len(all_violations)} violation(s):')
        for v in all_violations:
            print(' ', v)
        sys.exit(1)
    else:
        print(f'No cantillation violations in {len(epub_paths)} EPUBs.')


if __name__ == '__main__':
    main()
