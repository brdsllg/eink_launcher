"""Offline Talmud Bavli EPUB builder (Python standard library).

Stages:
  1. Normalize downloaded Sefaria editions into talmud.sqlite.
  2. Generate EPUBs: one EPUB per masechta, one XHTML per amud.

Usage:
  python talmud/work/build.py           # full 37-masechta build
  python talmud/work/build.py --pilot   # pilot amudim only

Called by regenerate.py for single-masechta rebuilds from existing SQLite.
"""
import argparse
import collections
import csv
import hashlib
import html
import json
import re
import sqlite3
import sys
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'work' / 'cache'
OUT = ROOT / 'outputs'

CONFIG = None  # loaded in main() after inventory check


def _require_config():
    global CONFIG
    config_path = OUT / 'source-selection.json'
    if not config_path.exists():
        print('ERROR: Run inventory.py first.', file=sys.stderr)
        raise SystemExit(1)
    CONFIG = json.loads(config_path.read_text(encoding='utf-8'))


MASECHTA_ORDER = None  # set from CONFIG
WARN = []


# ─── Utility ─────────────────────────────────────────────────────────────────

def slug(s):
    return re.sub('[^a-z0-9]+', '-', s.lower()).strip('-')


def e(s):
    return html.escape(str(s), quote=True)


def key(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24]


def natural(s):
    return tuple(int(x) if x.isdigit() else x for x in re.split(r'(\d+)', s))


# ─── Amud helpers ────────────────────────────────────────────────────────────
# Sefaria addresses Bavli pages as strings: '2a', '2b', '3a', ...
# We store them as (daf_number, side) where side is 0='a', 1='b'.

def amud_to_key(amud_str):
    """'2a' -> (2, 0);  '2b' -> (2, 1)"""
    m = re.fullmatch(r'(\d+)([ab])', amud_str)
    if not m:
        raise ValueError(f'Invalid amud: {amud_str!r}')
    return (int(m.group(1)), 0 if m.group(2) == 'a' else 1)


def key_to_amud(daf, side):
    return f'{daf}{"a" if side == 0 else "b"}'


def amud_display(amud_str):
    """Display label: '2a' -> 'Daf 2a'"""
    return f'Daf {amud_str}'


def amud_display_he(amud_str):
    """Hebrew display: '2a' -> 'דף ב׳ עמוד א׳', etc."""
    m = re.fullmatch(r'(\d+)([ab])', amud_str)
    if not m:
        return amud_str
    daf_n = int(m.group(1))
    side_he = 'א׳' if m.group(2) == 'a' else 'ב׳'
    return f'דף {_hebrew_number(daf_n)} עמוד {side_he}'


def _hebrew_number(number):
    """Integer to Hebrew letter-numeral string (gematria), ≤ 999."""
    if not 1 <= number <= 999:
        return str(number)
    letters = ''
    for value, letter in (
        (400, 'ת'), (300, 'ש'), (200, 'ר'), (100, 'ק'),
    ):
        while number >= value:
            letters += letter
            number -= value
    if number in (15, 16):
        letters += {15: 'טו', 16: 'טז'}[number]
    else:
        for value, letter in (
            (90, 'צ'), (80, 'פ'), (70, 'ע'), (60, 'ס'), (50, 'נ'),
            (40, 'מ'), (30, 'ל'), (20, 'כ'), (10, 'י'), (9, 'ט'),
            (8, 'ח'), (7, 'ז'), (6, 'ו'), (5, 'ה'), (4, 'ד'),
            (3, 'ג'), (2, 'ב'), (1, 'א'),
        ):
            if number >= value:
                letters += letter
                number -= value
    return letters + '׳' if len(letters) == 1 else letters[:-1] + '״' + letters[-1]


# ─── HTML sanitiser ──────────────────────────────────────────────────────────

class SafeHTML(HTMLParser):
    """Strip scripts/styles; keep inline formatting and paragraphs."""
    allowed = {
        'b', 'strong', 'i', 'em', 'small', 'sup', 'sub', 'span',
        'p', 'div', 'br', 'ul', 'ol', 'li', 'blockquote',
    }

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.stack = []
        self.skip = 0

    def handle_starttag(self, t, a):
        if t in ('script', 'style'):
            self.skip += 1
            return
        if self.skip or t not in self.allowed:
            return
        attrs = dict(a)
        extra = ''
        if attrs.get('class') == 'footnote':
            extra = ' class="embedded-footnote"'
        self.out.append('<' + t + extra + (' />' if t == 'br' else '>'))
        if t != 'br':
            self.stack.append(t)

    def handle_endtag(self, t):
        if t in ('script', 'style'):
            self.skip = max(0, self.skip - 1)
            return
        if self.skip or t not in self.stack:
            return
        while self.stack:
            end = self.stack.pop()
            self.out.append('</' + end + '>')
            if end == t:
                break

    def handle_data(self, d):
        if not self.skip:
            self.out.append(e(d))

    def finish(self, s):
        self.feed(s)
        while self.stack:
            self.out.append('</' + self.stack.pop() + '>')
        return ''.join(self.out)


def clean(s):
    return SafeHTML().finish(s)


def plaintext(s):
    return html.unescape(re.sub('<[^>]+>', '', s)).strip()


# ─── Schema / segment tree helpers ───────────────────────────────────────────

def leaves(node, path=()):
    if 'nodes' not in node:
        yield path, node
    else:
        for child in node['nodes']:
            name = '' if child.get('default') else child.get('title', child.get('key', ''))
            yield from leaves(child, path + ((name,) if name else ()))


def arrays(value, path=()):
    if isinstance(value, dict):
        for k, v in value.items():
            yield from arrays(v, path + ((k,) if k else ()))
    else:
        yield path, value


def segments(a, loc=()):
    if isinstance(a, str):
        if plaintext(a):
            yield loc, a
    elif isinstance(a, list):
        for i, v in enumerate(a, 1):
            yield from segments(v, loc + (i,))


def parse_address(ref):
    m = re.fullmatch(r'(.*?) (\d+(?:[ab]:?\d*)*)(?:-(\S+))?', ref)
    if not m:
        return ref, (), ()
    prefix, start_s, end_s = m.groups()
    # Talmud refs look like "Berakhot 2a:1" — amud string then colon then segment.
    def _parse(s):
        if not s:
            return ()
        amud_m = re.fullmatch(r'(\d+[ab]):?(\d+)?', s)
        if amud_m:
            daf_side = amud_m.group(1)
            seg = int(amud_m.group(2)) if amud_m.group(2) else None
            daf_n, side = amud_to_key(daf_side)
            return (daf_n, side) + ((seg,) if seg is not None else ())
        # Fallback: plain numeric tuple
        return tuple(int(x) for x in re.split(r'[:.]', s) if x.isdigit())

    return prefix, _parse(start_s), _parse(end_s or start_s)


def in_range(loc, start, end):
    if not start:
        return True
    n = len(start)
    return start <= loc[:n] <= end


# ─── CSS ─────────────────────────────────────────────────────────────────────

CSS = '''body {font-family:serif; margin:5%; color:#111; background:#fff; line-height:1.5;}
h1 {font-size:1.25em; line-height:1.35; margin:1em 0;}
h2 {font-size:1.1em; line-height:1.4;}
.amud-heading {display:flex; justify-content:space-between; align-items:baseline;
  margin:1em 0 .5em; font-size:1.15em; font-weight:bold; line-height:1.4;}
.segment {margin:1.2em 0 1.7em; padding-bottom:1em; border-bottom:1px solid #ccc;}
.segment-heading {display:flex; justify-content:space-between; align-items:baseline;
  margin:.65em 0 .35em; font-size:1.05em; font-weight:bold; line-height:1.4;}
.hebrew {font-family:"Noto Serif Hebrew","David","Times New Roman",serif;
  font-size:1.1em; text-align:right; line-height:1.8; margin:.4em 0; direction:rtl;}
.translation {font-size:1em; text-align:left; line-height:1.65; margin:.55em 0;}
.comment-segment {margin:.7em 0;}
p, .translation, .note-he, .note-en {text-indent:0;}
a {color:inherit; text-decoration:underline;}
.note-links {font-family:sans-serif; font-size:.78em; line-height:1.8; text-align:left; margin:.65em 0 0;}
.note-links a {display:inline-block; margin-right:.65em;}
aside {margin:1.5em 0; border-top:1px solid #bbb; padding-top:.7em;}
.commentary-note {margin:1.5em 0; padding:.6em 0; border-top:1px solid #bbb;}
.note-title {font-family:sans-serif; font-size:.8em; font-weight:bold;
  line-height:1.45; margin:0 0 .7em; text-align:left;}
.note-he {font-family:"Noto Serif Hebrew","David","Times New Roman",serif;
  text-align:right; font-size:1.1em; line-height:1.8; direction:rtl;}
.note-en {text-align:left; font-size:1em; line-height:1.65;}
.note-paragraph {margin:.65em 0;}
.embedded-footnote {font-size:1em;}
.colophon {overflow-wrap:anywhere; font-size:.9em;}
.backlinks {font-family:sans-serif; font-size:.75em; margin:1em 0 0;}
'''


def xhtml(title, body):
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" '
        'lang="en" xml:lang="en">'
        '<head><title>' + e(title) + '</title>'
        '<link rel="stylesheet" type="text/css" href="style.css"/>'
        '</head><body>' + body + '</body></html>'
    )


# ─── EPUB generation ─────────────────────────────────────────────────────────

def _amud_filename(amud_str):
    return f'amud-{amud_str}.xhtml'


def generate(conn, editions, masechtos=None):
    """Generate EPUBs from the normalized talmud.sqlite.

    masechtos: list of masechta names to generate, or None for all 37.
    """
    conn.row_factory = sqlite3.Row
    selected = MASECHTA_ORDER if masechtos is None else [
        m for m in MASECHTA_ORDER if m in set(masechtos)
    ]
    if not selected:
        raise ValueError('No masechtos selected')

    book_dir = OUT / 'books'
    book_dir.mkdir(exist_ok=True)
    summary = []

    for masechta in selected:
        ms = slug(masechta)
        files = {'style.css': re.sub(r'direction:(?:rtl|ltr); ?', '', CSS)}
        used = set()
        total_notes = set()
        total_trans = collections.Counter()

        # Amudim present in the database for this masechta.
        amudim = [
            row['amud']
            for row in conn.execute(
                'SELECT DISTINCT amud FROM segments WHERE masechta=? ORDER BY daf, side',
                (masechta,),
            )
        ]
        if not amudim:
            WARN.append(dict(kind='empty_masechta', masechta=masechta))
            continue

        title = masechta

        # Title page
        intro = (
            f'<h1>{e(masechta)}</h1>'
            f'<p>{len(amudim)} amudim</p>'
            f'<p><a href="nav.xhtml">Contents</a></p>'
        )
        files['title.xhtml'] = xhtml(title, intro)

        for amud in amudim:
            daf_n, side_n = amud_to_key(amud)
            body = [
                f'<h1 class="amud-heading" id="amud-{e(amud)}">'
                f'<span lang="en" xml:lang="en" dir="ltr">{e(amud_display(amud))}</span>'
                f' <span lang="he" xml:lang="he" dir="rtl">{e(amud_display_he(amud))}</span>'
                f'</h1>'
            ]
            aside_blocks = []

            # All notes attached to any segment in this amud
            amud_notes = {
                row['id']: row
                for row in conn.execute(
                    '''SELECT DISTINCT n.*
                       FROM notes n
                       JOIN note_refs r ON r.note_id = n.id
                       WHERE r.masechta = ? AND r.amud = ?
                       ORDER BY n.sort_order, n.ref''',
                    (masechta, amud),
                )
            }

            segments_rows = list(conn.execute(
                '''SELECT * FROM segments
                   WHERE masechta = ? AND amud = ?
                   ORDER BY seg_num''',
                (masechta, amud),
            ))

            for seg in segments_rows:
                seg_id = f's-{ms}-{amud}-{seg["seg_num"]}'
                seg_ref = f'{masechta} {amud}:{seg["seg_num"]}'

                # Notes for this segment
                note_ids = [
                    row['note_id']
                    for row in conn.execute(
                        '''SELECT DISTINCT r.note_id, n.sort_order, n.ref
                           FROM note_refs r
                           JOIN notes n ON n.id = r.note_id
                           WHERE r.masechta = ? AND r.amud = ? AND r.seg_num = ?
                           ORDER BY n.sort_order, n.ref''',
                        (masechta, amud, seg['seg_num']),
                    )
                ]
                total_notes.update(note_ids)

                # Heading row: "Berakhot 2a:1"  /  "ברכות ב׳ עמוד א׳:א׳"
                seg_num_he = _hebrew_number(seg['seg_num'])
                heading = (
                    f'<div class="segment-heading">'
                    f'<span lang="en" xml:lang="en" dir="ltr">{e(seg_ref)}</span>'
                    f' <span lang="he" xml:lang="he" dir="rtl">'
                    f'{e(masechta)} {e(amud_display_he(amud))}:{e(seg_num_he)}'
                    f'</span></div>'
                )

                # Hebrew/Aramaic text
                he_text = clean(seg['hebrew'] or '')
                he_block = (
                    f'<p class="hebrew" dir="rtl" lang="he" xml:lang="he">'
                    f'{he_text}</p>'
                    if he_text else ''
                )

                # English translation
                en_row = conn.execute(
                    '''SELECT text FROM translations
                       WHERE masechta = ? AND amud = ? AND seg_num = ?''',
                    (masechta, amud, seg['seg_num']),
                ).fetchone()
                en_block = ''
                if en_row and plaintext(en_row['text']):
                    total_trans[amud] += 1
                    en_block = (
                        f'<p class="translation" dir="ltr" lang="en" xml:lang="en">'
                        f'{clean(en_row["text"])}</p>'
                    )

                # Note index link
                index_id = f'idx-{seg_id}'
                noteref_links = ''
                if note_ids:
                    noteref_links = (
                        f'<p class="note-links">'
                        f'<a href="#{index_id}">Notes &amp; commentary</a>'
                        f'</p>'
                    )

                body.append(
                    f'<section class="segment" id="{e(seg_id)}" '
                    f'data-ref="{e(seg_ref)}">'
                    + heading + he_block + en_block + noteref_links
                    + '</section>'
                )

                # Index aside for this segment
                if note_ids:
                    index_links = ''.join(
                        f'<a epub:type="noteref" href="#{e("g-" + nid)}">'
                        f'{e(amud_notes[nid]["source"] if nid in amud_notes else nid)}'
                        f'</a> '
                        for nid in note_ids
                        if nid in amud_notes
                    )
                    body.append(
                        f'<aside epub:type="footnote" id="{e(index_id)}" '
                        f'class="note-index">'
                        f'<p class="note-links">{index_links}</p>'
                        f'</aside>'
                    )
                    used.update(note_ids)

            # Commentary asides (grouped by source+segment, one per amud)
            note_order = list(dict.fromkeys(
                row['note_id']
                for row in conn.execute(
                    '''SELECT r.note_id, n.sort_order, n.ref
                       FROM note_refs r
                       JOIN notes n ON n.id = r.note_id
                       WHERE r.masechta = ? AND r.amud = ?
                       ORDER BY n.sort_order, n.ref''',
                    (masechta, amud),
                )
            ))

            for nid in note_order:
                if nid not in amud_notes:
                    continue
                n = amud_notes[nid]
                gid = 'g-' + nid
                source_disp = n['source'] or nid
                ref_disp = n['ref'] or ''
                note_title = (
                    f'<p class="note-title">'
                    f'{e(source_disp)}'
                    f'{(" on " + e(ref_disp)) if ref_disp and ref_disp != source_disp else ""}'
                    f'</p>'
                )
                # Segments attached to this group for back-navigation
                attached_segs = [
                    f's-{ms}-{amud}-{row["seg_num"]}'
                    for row in conn.execute(
                        'SELECT seg_num FROM note_refs WHERE note_id=? AND masechta=? AND amud=?',
                        (nid, masechta, amud),
                    )
                ]
                backlinks = (
                    '<p class="backlinks">'
                    + ' '.join(
                        f'<a href="#{e(sid)}">↑ {e(sid.split("-")[-1])}</a>'
                        for sid in attached_segs
                    )
                    + '</p>'
                )

                he_content = clean(n['he'] or '')
                en_content = clean(n['en'] or '')
                he_div = (
                    f'<div class="note-he" dir="rtl" lang="he" xml:lang="he">'
                    f'{he_content}</div>'
                    if he_content else ''
                )
                en_div = (
                    f'<div class="note-en" dir="ltr" lang="en" xml:lang="en">'
                    f'{en_content}</div>'
                    if en_content else ''
                )

                aside_blocks.append(
                    f'<aside epub:type="footnote" id="{e(gid)}" '
                    f'class="commentary-note" data-source="{e(source_disp)}" '
                    f'data-category="commentary" data-ref="{e(ref_disp)}">'
                    + note_title + he_div + en_div + backlinks
                    + '</aside>'
                )

            files[_amud_filename(amud)] = xhtml(
                f'{masechta} {amud}',
                ''.join(body) + ''.join(aside_blocks),
            )

        # Credits page
        credit_rows = list(conn.execute('SELECT * FROM editions'))
        credit_lines = [
            f'<dt>{e(r["title"])} — {e(r["version_title"])}</dt>'
            f'<dd class="colophon">Language: {e(r["language"])}; '
            f'License: {e(r["license"] or "unknown")}; '
            f'Source: {e(r["source_url"] or "")}; '
            f'SHA-256: {e(r["sha256"] or "")}</dd>'
            for r in credit_rows
        ]
        files['credits.xhtml'] = xhtml(
            'Credits',
            '<h1>Credits</h1><dl>' + ''.join(credit_lines) + '</dl>',
        )

        # OPF manifest + spine
        spine_items = ['title'] + [slug(a) for a in amudim] + ['credits']
        manifest_items = []
        for name, content in sorted(files.items()):
            fid = name.replace('.', '-').replace('/', '-')
            mt = (
                'application/xhtml+xml' if name.endswith('.xhtml')
                else 'text/css' if name.endswith('.css')
                else 'application/xhtml+xml'
            )
            props = ' properties="nav"' if name == 'nav.xhtml' else ''
            manifest_items.append(
                f'<item id="{e(fid)}" href="{e(name)}" media-type="{e(mt)}"{props}/>'
            )

        # nav.xhtml
        nav_items = []
        for amud in amudim:
            fn = _amud_filename(amud)
            nav_items.append(
                f'<li><a href="{e(fn)}#{e("amud-" + amud)}">{e(amud_display(amud))}</a></li>'
            )
        nav_body = (
            '<nav epub:type="toc" id="toc">'
            '<h1>Contents</h1>'
            f'<ol>{chr(10).join(nav_items)}</ol>'
            '</nav>'
        )
        files['nav.xhtml'] = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<!DOCTYPE html>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml" '
            'xmlns:epub="http://www.idpf.org/2007/ops" '
            'lang="en" xml:lang="en">'
            '<head><title>' + e(f'{masechta} Contents') + '</title>'
            '<link rel="stylesheet" type="text/css" href="style.css"/>'
            '</head><body>' + nav_body + '</body></html>'
        )

        # NCX
        ncx_items = ''.join(
            f'<navPoint id="amud-{e(amud)}" playOrder="{i}">'
            f'<navLabel><text>{e(masechta)} {e(amud)}</text></navLabel>'
            f'<content src="{e(_amud_filename(amud))}"/>'
            f'</navPoint>'
            for i, amud in enumerate(amudim, 1)
        )
        book_uid = 'talmud-' + slug(masechta)
        ncx = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
            f'<head><meta name="dtb:uid" content="{e(book_uid)}"/></head>'
            f'<docTitle><text>{e(masechta)}</text></docTitle>'
            f'<navMap>{ncx_items}</navMap>'
            '</ncx>'
        )
        files['toc.ncx'] = ncx

        # OPF
        manifest_xml = '\n'.join(manifest_items)
        # Add nav and ncx
        manifest_xml += (
            f'\n<item id="nav-xhtml" href="nav.xhtml" '
            f'media-type="application/xhtml+xml" properties="nav"/>'
            f'\n<item id="toc-ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
        )
        spine_refs = '\n'.join(
            f'<itemref idref="{e((_amud_filename(a)).replace(".","--").replace("/","-"))}"/>'
            if a not in ('title', 'credits')
            else f'<itemref idref="{e(a + "-xhtml")}"/>'
            for a in (['title'] + amudim + ['credits'])
        )
        # Build spine itemrefs from filenames properly
        def _iref(fname):
            return fname.replace('.', '-').replace('/', '-')

        spine_refs = '\n'.join(
            f'<itemref idref="{e(_iref(fname))}"/>'
            for fname in (
                ['title.xhtml', 'nav.xhtml']
                + [_amud_filename(a) for a in amudim]
                + ['credits.xhtml']
            )
        )

        opf = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<package xmlns="http://www.idpf.org/2007/opf" '
            'xmlns:dc="http://purl.org/dc/elements/1.1/" '
            f'unique-identifier="{e(book_uid)}" version="3.0">'
            '<metadata xmlns:opf="http://www.idpf.org/2007/opf">'
            f'<dc:title>{e(masechta)}</dc:title>'
            '<dc:language>he</dc:language>'
            '<dc:language>en</dc:language>'
            f'<dc:identifier id="{e(book_uid)}">{e(book_uid)}</dc:identifier>'
            '<meta property="dcterms:modified">2026-09-29T00:00:00Z</meta>'
            '</metadata>'
            f'<manifest>{manifest_xml}</manifest>'
            f'<spine toc="toc-ncx" page-progression-direction="ltr">'
            f'{spine_refs}</spine>'
            '</package>'
        )
        files['package.opf'] = opf

        # Write EPUB zip
        epub_path = book_dir / f'{slug(masechta)}.epub'
        with zipfile.ZipFile(epub_path, 'w', zipfile.ZIP_DEFLATED) as z:
            # mimetype must be first and uncompressed
            z.writestr(
                zipfile.ZipInfo('mimetype'), b'application/epub+zip',
                compress_type=zipfile.ZIP_STORED,
            )
            z.writestr(
                'META-INF/container.xml',
                '<?xml version="1.0" encoding="utf-8"?>'
                '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
                '<rootfiles>'
                '<rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/>'
                '</rootfiles>'
                '</container>',
            )
            for fname, content in files.items():
                if isinstance(content, str):
                    content = content.encode('utf-8')
                z.writestr(f'EPUB/{fname}', content)

        note_count = len(total_notes)
        summary.append(dict(
            masechta=masechta,
            amudim=len(amudim),
            notes=note_count,
            epub=epub_path.name,
            epub_bytes=epub_path.stat().st_size,
        ))
        print(
            f'{masechta}: {len(amudim)} amudim, {note_count} notes -> {epub_path.name}',
            flush=True,
        )

    # Full-coverage JSON
    (OUT / 'full-coverage.json').write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8'
    )
    print('Warnings:', json.dumps(
        dict(collections.Counter(w['kind'] for w in WARN)),
        ensure_ascii=False,
    ))
    return summary


# ─── Normalization ────────────────────────────────────────────────────────────

def normalize(conn, pilot_masechtos=None):
    """Read cached Sefaria texts and populate talmud.sqlite."""
    global WARN
    WARN = []

    conn.executescript('''
    DROP TABLE IF EXISTS segments;
    DROP TABLE IF EXISTS translations;
    DROP TABLE IF EXISTS notes;
    DROP TABLE IF EXISTS note_refs;
    DROP TABLE IF EXISTS editions;
    CREATE TABLE segments(
        masechta TEXT, amud TEXT, daf INT, side INT, seg_num INT,
        original TEXT, hebrew TEXT, he_edition TEXT,
        PRIMARY KEY(masechta, amud, seg_num)
    );
    CREATE TABLE translations(
        masechta TEXT, amud TEXT, seg_num INT, edition TEXT, text TEXT,
        PRIMARY KEY(masechta, amud, seg_num, edition)
    );
    CREATE TABLE notes(
        id TEXT PRIMARY KEY, source TEXT, ref TEXT, category TEXT,
        sort_order INT, he TEXT, en TEXT, he_edition TEXT, en_edition TEXT
    );
    CREATE TABLE note_refs(
        note_id TEXT, masechta TEXT, amud TEXT, seg_num INT,
        connection_type TEXT, original_base_ref TEXT, original_note_ref TEXT,
        UNIQUE(note_id, masechta, amud, seg_num, connection_type,
               original_base_ref, original_note_ref)
    );
    CREATE TABLE editions(
        id TEXT PRIMARY KEY, title TEXT, version_title TEXT, language TEXT,
        license TEXT, source_url TEXT, export_url TEXT, sha256 TEXT
    );
    ''')

    plan_path = CACHE / 'download-plan.json'
    if not plan_path.exists():
        raise FileNotFoundError('Run inventory.py and sync.py texts first')
    plan = json.loads(plan_path.read_text(encoding='utf-8'))
    source_policy = {s['title']: s for s in CONFIG['sources']}

    target_masechtos = set(pilot_masechtos or MASECHTA_ORDER)

    docs = []
    edition_info = {}
    schema_cache = {}

    for b in plan:
        if b['title'] not in target_masechtos and not any(
            b['title'].endswith(f' on {m}') or b['title'].startswith('Steinsaltz on ')
            for m in target_masechtos
        ):
            # Check if this is a commentary on one of our target masechtos.
            is_relevant = False
            for m in target_masechtos:
                if (m in b['title'] and b['role'] == 'commentary'):
                    is_relevant = True
                    break
            if not is_relevant and b['title'] not in target_masechtos:
                continue

        if b['role'] == 'commentary':
            policy = source_policy.get(b['title'])
            if policy is None or policy['status'] != 'include':
                continue

        path = CACHE / 'texts' / f"{key(b['json_url'])}.json"
        if not path.exists():
            WARN.append(dict(kind='missing_cached_edition', title=b['title'], url=b['json_url']))
            continue

        d = json.loads(path.read_text(encoding='utf-8'))
        lang = d.get('actualLanguage', d.get('language', ''))
        if lang not in ('en', 'he'):
            WARN.append(dict(kind='language_mismatch', title=b['title'], edition=d.get('versionTitle', '')))
            continue
        if re.search(r'(^test\b|\btest$|abbreviated|summary)', d.get('versionTitle', ''), re.I):
            WARN.append(dict(kind='test_or_abridged_edition', title=b['title'], edition=d.get('versionTitle', '')))
            continue

        eid = 'ed-' + key(b['json_url'])
        meta_path = path.with_suffix('.json.meta.json')
        meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        info = (
            eid, d.get('title', b['title']), d.get('versionTitle', ''),
            lang, d.get('license', 'unknown'),
            d.get('versionSource', ''), b['json_url'], meta.get('sha256', ''),
        )
        conn.execute('INSERT OR IGNORE INTO editions VALUES(?,?,?,?,?,?,?,?)', info)
        edition_info[eid] = dict(
            zip(('id', 'title', 'version_title', 'language',
                 'license', 'source_url', 'export_url', 'sha256'), info)
        )
        docs.append((b, d, eid))

    # ── Insert Hebrew segments ───────────────────────────────────────────────
    # Sefaria Bavli text structure: d['text'] is a list of amudim, each a list
    # of segment strings. Amud labels come from d['sectionNames'] + d['sections'].
    # Fallback: index-based amud generation starting from 2a.
    segment_keys = set()

    for b, d, eid in docs:
        if b['role'] != 'hebrew':
            continue
        masechta = b['title']
        if masechta not in target_masechtos:
            continue

        text_data = d.get('text', [])
        if not isinstance(text_data, list):
            WARN.append(dict(kind='unexpected_text_structure', masechta=masechta))
            continue

        # Generate amud labels: start at 2a, then 2b, 3a, 3b, ...
        def _amud_sequence(count):
            daf = 2
            side = 0  # 0=a, 1=b
            for _ in range(count):
                yield key_to_amud(daf, side)
                side += 1
                if side > 1:
                    side = 0
                    daf += 1

        for amud, chapter_segs in zip(_amud_sequence(len(text_data)), text_data):
            if not isinstance(chapter_segs, list):
                chapter_segs = [chapter_segs] if chapter_segs else []
            daf_n, side_n = amud_to_key(amud)
            for seg_idx, seg_text in enumerate(chapter_segs, 1):
                if not isinstance(seg_text, str) or not plaintext(seg_text):
                    continue
                # Strip nikud-optional cantillation; keep nikud as specified.
                # Cantillation = U+0591..U+05AF; nikud = U+05B0..U+05C7.
                he_clean = re.sub('[\u0591-\u05af]', '', seg_text)
                conn.execute(
                    'INSERT OR IGNORE INTO segments VALUES(?,?,?,?,?,?,?,?)',
                    (masechta, amud, daf_n, side_n, seg_idx, seg_text, he_clean, eid),
                )
                segment_keys.add((masechta, amud, seg_idx))

    # ── Insert English translations ──────────────────────────────────────────
    for b, d, eid in docs:
        if b['role'] != 'translation':
            continue
        masechta = b['title']
        text_data = d.get('text', [])
        if not isinstance(text_data, list):
            continue

        def _amud_sequence(count):
            daf = 2
            side = 0
            for _ in range(count):
                yield key_to_amud(daf, side)
                side += 1
                if side > 1:
                    side = 0
                    daf += 1

        for amud, chapter_segs in zip(_amud_sequence(len(text_data)), text_data):
            if not isinstance(chapter_segs, list):
                chapter_segs = [chapter_segs] if chapter_segs else []
            for seg_idx, seg_text in enumerate(chapter_segs, 1):
                if (masechta, amud, seg_idx) in segment_keys and isinstance(seg_text, str) and plaintext(seg_text):
                    conn.execute(
                        'INSERT OR IGNORE INTO translations VALUES(?,?,?,?,?)',
                        (masechta, amud, seg_idx, eid, seg_text),
                    )

    conn.commit()

    # ── Commentary notes ─────────────────────────────────────────────────────
    raw = {}
    leaf_nodes = {}
    prefix_sources = {}
    leaf_bases = {}

    def _rank(d):
        v = d.get('versionTitle', '')
        return (1000 if 'William Davidson' in v or 'Vilna' in v else 0) + float(d.get('priority') or 0)

    for b, d, eid in sorted(docs, key=lambda x: _rank(x[1]), reverse=True):
        if b['role'] != 'commentary':
            continue
        source = b['title']
        if source not in schema_cache:
            sp = CACHE / 'schemas' / f'{key(source)}.json'
            if sp.exists():
                schema_cache[source] = json.loads(sp.read_text(encoding='utf-8'))
            else:
                WARN.append(dict(kind='missing_schema', source=source))
                continue
        schema = schema_cache[source]
        nodes = {p: n for p, n in leaves(schema.get('schema', {}))}
        bases = [
            x['en'] if isinstance(x, dict) else x
            for x in schema.get('base_text_titles', [])
        ]
        for path, arr in arrays(d.get('text', {})):
            prefix = ', '.join((source,) + path)
            node = nodes.get(path) or next(
                (n for p, n in nodes.items() if ', '.join(p) == ', '.join(path)),
                None,
            )
            if node is None:
                WARN.append(dict(kind='unmapped_schema_leaf', source=source, path=path))
                continue
            leaf_nodes[prefix] = node
            prefix_sources[prefix] = source
            leaf_bases[prefix] = bases
            for loc, text in segments(arr):
                identity = (prefix, loc)
                entry = raw.setdefault(
                    identity,
                    dict(source=source, prefix=prefix, loc=loc,
                         category=b.get('source_category', 'commentary'),
                         sort_order=b.get('sort_order', 0), langs={})
                )
                entry['langs'].setdefault(d.get('language', 'he'), (text, eid))

    notes = {}
    resolver = collections.defaultdict(dict)
    for (prefix, loc), entry in raw.items():
        names = leaf_nodes[prefix].get('sectionNames', [])
        note_loc = loc
        nid = 'n-' + key(prefix + ' ' + ':'.join(map(str, note_loc)))
        note = notes.setdefault(
            nid,
            dict(id=nid, source=entry['source'],
                 ref=prefix + (' ' + ':'.join(map(str, note_loc)) if note_loc else ''),
                 category=entry['category'], sort_order=entry['sort_order'],
                 parts={'he': [], 'en': []}, editions={'he': [], 'en': []})
        )
        for lang, (text, e_id) in entry['langs'].items():
            note['parts'][lang].append((loc, text))
            note['editions'][lang].append(e_id)
        resolver[prefix][loc] = nid

    # Attach notes to segments via schema addressing.
    attachments = set()
    for (prefix, loc), entry in raw.items():
        names = leaf_nodes[prefix].get('sectionNames', [])
        # Talmud commentary uses sectionNames like ['Daf', 'Line'] or ['Chapter', 'Verse'].
        # We need at least 2 levels: amud + segment.
        if len(names) >= 2 and len(loc) >= 2:
            # Try to resolve the masechta from the source title.
            source = entry['source']
            # "Rashi on Berakhot" -> "Berakhot"
            m = re.match(r'.+ on (.+)$', source)
            base_masechta = m.group(1) if m else None
            # "Steinsaltz on Berakhot" -> "Berakhot"
            if base_masechta and base_masechta in target_masechtos:
                # loc[0] = amud index (1-based), loc[1] = segment number
                # Build amud string from amud index.
                amud_idx = loc[0]
                seg_num = loc[1] if len(loc) > 1 else 1

                def _amud_from_idx(idx):
                    daf = 2 + (idx - 1) // 2
                    side = (idx - 1) % 2
                    return key_to_amud(daf, side)

                amud = _amud_from_idx(amud_idx)
                if (base_masechta, amud, seg_num) in segment_keys:
                    nid = resolver[prefix][loc]
                    attachments.add((
                        nid, base_masechta, amud, seg_num,
                        'commentary',
                        f'{base_masechta} {amud}:{seg_num}',
                        prefix + ' ' + ':'.join(map(str, loc)),
                    ))

    # Also use link CSV files for broader attachment.
    links_dir = CACHE / 'links'
    if links_dir.exists():
        link_counts = collections.Counter()
        for file in sorted(links_dir.glob('links*.csv')):
            if not re.fullmatch(r'links\d+\.csv', file.name):
                continue
            try:
                with file.open(encoding='utf-8-sig', newline='') as f:
                    for row in csv.DictReader(f):
                        side = (
                            1 if row.get('Text 1') in target_masechtos
                            else 2 if row.get('Text 2') in target_masechtos
                            else 0
                        )
                        if not side:
                            continue
                        other = 3 - side
                        t_other = row.get(f'Text {other}', '')
                        # Only link commentary sources we actually have
                        if not any(
                            t_other.startswith(f'{src} on') or t_other == src
                            for src in (s['title'] for s in CONFIG['sources'] if s['status'] == 'include')
                        ):
                            continue
                        bp = row.get(f'Text {side}', '')
                        if bp not in target_masechtos:
                            continue
                        nr = row.get(f'Citation {other}', '')
                        if not nr or nr not in resolver:
                            continue
                        base_ref = row.get(f'Citation {side}', '')
                        _, start, end = parse_address(base_ref)
                        for nid in (
                            nid2 for loc2, nid2 in resolver[nr].items()
                            if in_range(loc2, start, end)
                        ):
                            # Determine amud + seg from base ref
                            _, bs, _ = parse_address(base_ref)
                            if bs and len(bs) >= 2:
                                amud_s = key_to_amud(bs[0], bs[1])
                                seg_s = bs[2] if len(bs) > 2 else 1
                                if (bp, amud_s, seg_s) in segment_keys:
                                    attachments.add((
                                        nid, bp, amud_s, seg_s,
                                        row.get('Conection Type', 'commentary'),
                                        base_ref, nr,
                                    ))
                                    link_counts[row.get('Conection Type', '')] += 1
            except Exception as ex:
                WARN.append(dict(kind='link_csv_error', file=file.name, error=str(ex)))
            print('Read', file.name, flush=True)

    # Write notes and refs to DB
    attached = {a[0] for a in attachments}
    for nid in attached:
        n = notes[nid]
        values = []
        for lang in ('he', 'en'):
            parts = sorted(n['parts'][lang])
            values.append(
                '\n'.join(
                    '<div class="note-paragraph">' + clean(t) + '</div>'
                    for _, t in parts
                )
            )
        conn.execute(
            'INSERT OR REPLACE INTO notes VALUES(?,?,?,?,?,?,?,?,?)',
            (nid, n['source'], n['ref'], n['category'], n['sort_order'],
             *values,
             json.dumps(sorted(set(n['editions']['he']))),
             json.dumps(sorted(set(n['editions']['en'])))),
        )
    conn.executemany(
        'INSERT OR IGNORE INTO note_refs VALUES(?,?,?,?,?,?,?)',
        sorted(attachments),
    )
    conn.commit()

    report = dict(
        masechtos=len(target_masechtos),
        segments=len(segment_keys),
        notes=len(attached),
        attachments=len(attachments),
        warnings=WARN,
    )
    (OUT / 'build-report.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8'
    )
    print(json.dumps({k: v for k, v in report.items() if k != 'warnings'}, indent=2))
    print(
        'Warnings by kind:',
        json.dumps(dict(collections.Counter(w['kind'] for w in WARN)), ensure_ascii=False),
        flush=True,
    )
    return report


# ─── Entry point ─────────────────────────────────────────────────────────────

def main():
    _require_config()
    global MASECHTA_ORDER
    MASECHTA_ORDER = CONFIG['preferences']['masechta_order']

    parser = argparse.ArgumentParser(
        description='Normalize Sefaria data and generate Talmud EPUBs.'
    )
    parser.add_argument(
        '--pilot', action='store_true',
        help='Build only the pilot amudim (fast iteration).',
    )
    args = parser.parse_args()

    pilot_masechtos = (
        CONFIG['preferences']['pilot_masechtos'] if args.pilot else None
    )

    dbpath = ROOT / 'work' / 'talmud.sqlite'
    with sqlite3.connect(dbpath) as conn:
        normalize(conn, pilot_masechtos=pilot_masechtos)
        conn.row_factory = sqlite3.Row
        edition_rows = conn.execute('SELECT * FROM editions')
        editions = {r['id']: dict(r) for r in edition_rows}
        generate(conn, editions, masechtos=pilot_masechtos)


if __name__ == '__main__':
    main()
