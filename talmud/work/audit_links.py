"""Audit all internal hrefs and fragment anchors in the generated EPUBs.

Reports:
  - Broken file links (href points to a file not in the EPUB)
  - Broken fragment anchors (fragment not found in target file)
  - Noterefs whose targets are not epub:type="footnote" asides

Exits with code 1 if any errors are found.

Usage:
  python talmud/work/audit_links.py
  python talmud/work/audit_links.py --pilot
"""
import argparse
import posixpath
import sys
import urllib.parse
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'outputs'
BOOKS = OUT / 'books'
NS = '{http://www.w3.org/1999/xhtml}'


def audit_epub(p):
    errors = []
    with zipfile.ZipFile(p) as z:
        names = set(z.namelist())
        ids: dict[str, set] = {}
        trees: dict[str, ET.Element] = {}

        for name in z.namelist():
            if name.endswith(('.xhtml', '.opf', '.ncx')):
                root = ET.fromstring(z.read(name))
                trees[name] = root
                ids[name] = {n.attrib['id'] for n in root.iter() if 'id' in n.attrib}

        for name, tree in trees.items():
            for a in tree.iter():
                href = a.attrib.get('href')
                if not href:
                    continue
                u = urllib.parse.urlsplit(href)
                if u.scheme:
                    continue
                dest = (
                    posixpath.normpath(posixpath.join(posixpath.dirname(name), u.path))
                    if u.path else name
                )
                if dest not in names:
                    errors.append(f'{name}: broken file link → {href}')
                    continue
                if u.fragment:
                    if u.fragment not in ids.get(dest, set()):
                        errors.append(f'{name}: broken anchor → {href}')
                    epub_type = a.attrib.get('{http://www.idpf.org/2007/ops}type')
                    if epub_type == 'noteref':
                        target = next(
                            (n for n in trees.get(dest, ET.Element('_')).iter()
                             if n.attrib.get('id') == u.fragment),
                            None,
                        )
                        if target is None:
                            errors.append(f'{name}: noteref target missing → {href}')
                        elif target.tag != NS + 'aside':
                            errors.append(f'{name}: noteref not aside → {href}')
                        elif not ''.join(target.itertext()).strip():
                            errors.append(f'{name}: empty noteref → {href}')
    return errors


def main():
    parser = argparse.ArgumentParser(description='Audit links in Talmud EPUBs.')
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

    total_errors = []
    for p in epub_paths:
        errs = audit_epub(p)
        for err in errs:
            total_errors.append(f'{p.name}: {err}')

    if total_errors:
        print(f'{len(total_errors)} link error(s):')
        for err in total_errors:
            print(' ', err)
        sys.exit(1)
    else:
        print(f'No link errors in {len(epub_paths)} EPUBs.')


if __name__ == '__main__':
    main()
