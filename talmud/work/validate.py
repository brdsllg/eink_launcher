"""Validate generated Talmud Bavli EPUBs.

Runs EPUBCheck and performs internal structural checks:
- All internal hrefs and fragment anchors resolve.
- No cantillation marks in Hebrew text blocks.
- All segment sections have data-ref.
- All noteref hrefs point to epub:type="footnote" asides with content.
- No duplicate IDs within a document.

Usage:
  python talmud/work/validate.py           # validate all masechtos
  python talmud/work/validate.py --pilot   # validate pilot masechtos only
"""
import argparse
import json
import posixpath
import re
import subprocess
import urllib.parse
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'outputs'
BOOKS = OUT / 'books'
REPORTS = ROOT / 'work' / 'validation'
REPORTS.mkdir(exist_ok=True)

NS = '{http://www.w3.org/1999/xhtml}'

# Locate Java and EPUBCheck from tanach's tools directory (shared).
_TANACH_TOOLS = ROOT.parent / 'tanach' / 'work' / 'tools'
_LOCAL_TOOLS = ROOT / 'work' / 'tools'


def _find_tool(name, pattern):
    for base in (_LOCAL_TOOLS, _TANACH_TOOLS):
        matches = sorted(p for p in base.rglob(pattern) if p.is_file())
        if matches:
            return matches[0]
    return None


def _find_java():
    return _find_tool('java', 'java.exe') or _find_tool('java', 'java')


def _find_jar():
    return _find_tool('epubcheck', 'epubcheck.jar')


def _epubcheck(p, java, jar):
    report = REPORTS / (p.stem + '.json')
    run = subprocess.run(
        [str(java), '-jar', str(jar), str(p), '-j', str(report)],
        capture_output=True, text=True, encoding='utf-8', errors='replace',
    )
    (REPORTS / (p.stem + '.txt')).write_text(
        run.stdout + '\n' + run.stderr, encoding='utf-8'
    )
    print(p.name, 'EPUBCheck exit', run.returncode, flush=True)
    return p.name, run.returncode


def _structural_check(p):
    """Internal link/anchor, cantillation, and structural checks."""
    errors = []
    with zipfile.ZipFile(p) as z:
        # mimetype must be first and uncompressed
        if z.namelist()[0] != 'mimetype':
            errors.append('mimetype not first entry')
        if z.getinfo('mimetype').compress_type != 0:
            errors.append('mimetype is compressed')
        if z.read('mimetype') != b'application/epub+zip':
            errors.append('mimetype content wrong')

        ids: dict[str, set] = {}
        trees: dict[str, ET.Element] = {}

        for name in z.namelist():
            if name.endswith(('.xhtml', '.opf', '.ncx', '.xml')):
                source = z.read(name)
                root = ET.fromstring(source)
                trees[name] = root
                vals = [n.attrib['id'] for n in root.iter() if 'id' in n.attrib]
                if len(vals) != len(set(vals)):
                    errors.append(f'Duplicate IDs in {name}')
                ids[name] = set(vals)

        # Check all internal hrefs
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
                if dest not in z.namelist():
                    errors.append(f'Broken file link: {name} → {href}')
                    continue
                if u.fragment:
                    if u.fragment not in ids.get(dest, set()):
                        errors.append(f'Broken anchor: {name} → {href}')
                    # noteref must point to epub:type="footnote" aside with content
                    epub_type = a.attrib.get('{http://www.idpf.org/2007/ops}type')
                    if epub_type == 'noteref':
                        target = next(
                            (n for n in trees[dest].iter()
                             if n.attrib.get('id') == u.fragment),
                            None,
                        )
                        if target is None:
                            errors.append(f'Noteref target missing: {name} → {href}')
                        elif target.tag != NS + 'aside':
                            errors.append(f'Noteref target not aside: {name} → {href}')
                        elif target.attrib.get('{http://www.idpf.org/2007/ops}type') != 'footnote':
                            errors.append(f'Noteref target not footnote: {name} → {href}')
                        elif not ''.join(target.itertext()).strip():
                            errors.append(f'Empty noteref target: {name} → {href}')

        # No cantillation in .hebrew paragraphs
        for name, tree in trees.items():
            for node in tree.iter(NS + 'p'):
                if node.attrib.get('class') == 'hebrew':
                    text = ''.join(node.itertext())
                    if re.search('[\u0591-\u05af]', text):
                        errors.append(f'Cantillation in hebrew paragraph: {name}')

        # All segment sections have data-ref
        for name, tree in trees.items():
            for node in tree.iter(NS + 'section'):
                if 'segment' in node.attrib.get('class', ''):
                    if 'data-ref' not in node.attrib:
                        errors.append(f'Segment section missing data-ref: {name}')

    return errors


def main():
    parser = argparse.ArgumentParser(description='Validate Talmud Bavli EPUBs.')
    parser.add_argument('--pilot', action='store_true', help='Validate pilot masechtos only.')
    args = parser.parse_args()

    config_path = OUT / 'source-selection.json'
    if config_path.exists():
        config = json.loads(config_path.read_text(encoding='utf-8'))
        if args.pilot:
            pilot_masechtos = set(config['preferences'].get('pilot_masechtos', []))
        else:
            pilot_masechtos = None
    else:
        pilot_masechtos = None

    from build import slug
    if pilot_masechtos:
        epub_paths = [
            BOOKS / f'{slug(m)}.epub'
            for m in pilot_masechtos
            if (BOOKS / f'{slug(m)}.epub').exists()
        ]
    else:
        epub_paths = sorted(BOOKS.glob('*.epub'))

    if not epub_paths:
        print('No EPUBs found in', BOOKS, file=__import__('sys').stderr)
        raise __import__('sys').exit(1)

    java = _find_java()
    jar = _find_jar()
    results = []

    if java and jar:
        with ThreadPoolExecutor(max_workers=3) as pool:
            codes = dict(pool.map(lambda p: _epubcheck(p, java, jar), epub_paths))
    else:
        print('WARNING: Java or EPUBCheck not found; skipping EPUBCheck validation.')
        codes = {p.name: -1 for p in epub_paths}

    for p in epub_paths:
        errs = _structural_check(p)
        status = 'pass' if not errs else 'fail'
        results.append(dict(
            file=p.name,
            epubcheck_exit=codes.get(p.name, -1),
            structure=status,
            errors=errs,
        ))
        if errs:
            print(f'STRUCTURAL ERRORS in {p.name}:')
            for err in errs:
                print(' ', err)
        else:
            print(f'{p.name}: structural OK')

    out_path = OUT / 'full-validation-results.json'
    out_path.write_text(json.dumps(results, indent=2))
    print(f'Results written to {out_path}')

    failed = [r for r in results if r['epubcheck_exit'] != 0 or r['structure'] != 'pass']
    if failed:
        print(f'{len(failed)} EPUBs failed validation.')
        raise __import__('sys').exit(1)
    print(f'All {len(results)} EPUBs passed.')


if __name__ == '__main__':
    main()
