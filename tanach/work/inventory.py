"""Build a reproducible, offline source inventory; never treat merged editions as approved."""
import collections
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'work/cache'
OUT = ROOT / 'outputs'
OUT.mkdir(exist_ok=True)
books = json.loads((CACHE / 'books.json').read_text(encoding='utf-8-sig'))['books']
toc = json.loads((CACHE / 'table_of_contents.json').read_text(encoding='utf-8-sig'))

def walk(nodes):
    for node in nodes:
        if 'title' in node:
            yield node
        yield from walk(node.get('contents', []))

titles = {n['title']: n for n in walk(toc) if n.get('categories', [None])[0] == 'Tanakh'}
base = [n['title'] for n in titles.values() if len(n.get('categories', [])) == 2 and n['categories'][1] in ('Torah', 'Prophets', 'Writings')]
assert len(base) == 39, (len(base), base)
versions = collections.defaultdict(list)
for b in books:
    if b['title'] in titles:
        versions[b['title']].append(b)

def modern_status(title, cats):
    if title == "The Torah; A Women's Commentary":
        return 'exclude', 'Sefaria identifies Women of Reform Judaism / CCAR publication.'
    if any(x in cats for x in ('Jonathan Sacks', 'Avraham Remer', 'Redeeming Relevance', 'Steinsaltz')) or title.startswith('David Zvi Hoffmann on ') or title in {
        'Birkat Asher on Torah', 'Chibbah Yeteirah on Torah', 'Depths of Yonah',
        'From David to Destruction', 'Megillat Ruth; From Chaos to Kingship',
        'Sefer Daniel; Opportunity in Exile', 'Nechama Leibowitz',
        'The Kehot Chumash; A Chasidic Commentary'}:
        return 'include', 'Recognizable Orthodox author or publisher; editorial selection under user instruction.'
    return 'exclude', 'User explicitly declined all uncertain modern works.'

sources = []
for title, n in titles.items():
    cats = n['categories']
    if title in base:
        continue
    category = next((c for c in cats if c in ('Rishonim on Tanakh', 'Acharonim on Tanakh', 'Modern Commentary on Tanakh', 'Targum')), 'other')
    if category in ('Rishonim on Tanakh', 'Acharonim on Tanakh'):
        status, reason = 'include', 'User requested all classical commentators in these categories.'
    elif category == 'Modern Commentary on Tanakh':
        status, reason = modern_status(title, cats)
    else:
        status, reason = 'exclude', 'User explicitly excluded Targum.'
    sources.append(dict(title=title, category=category, status=status, reason=reason,
        description=n.get('enShortDesc', ''), sort_order=len(sources),
        available_versions=versions[title], export_available=bool(versions[title]),
        selected_versions=[], license_status='Read individual JSON license fields before build'))

translations = collections.defaultdict(list)
for title in base:
    for v in versions[title]:
        if v['language'] == 'English' and v['versionTitle'] != 'merged':
            translations[v['versionTitle']].append(v)
trans = []
for title, entries in sorted(translations.items()):
    if re.search(r'\[(?:fr|es|de|it|pt|pl|fa|ca|lad|eo|ru|fi|ro|tr)\]', title, re.I) or title in {'Alfredo cerhy español ', 'Bibel - Schlachter 2000', 'Biblical Aramaic into Hebrew, Rabbi Dan Be\'eri, 2004', 'Italian II Chronicles Chapter 135', 'Portuguese II Chronicles Chapter 135', 'Spanish II Chronicles Chapter 135', 'Spanish - Reina Valera 1960', 'Rosario-IT', 'שְׁלַח־לְךָ֣ אֲנָשִׁ֗ים'}:
        status, reason = 'exclude_language', 'Explicit non-English language tag.'
    elif 'with Onkelos translation' in title:
        status, reason = 'exclude', 'User excluded Targum; use standalone Metsudah edition.'
    elif any(x in title for x in ('Metsudah', 'The Rashi chumash', 'The Rashi Ketuvim', 'The Koren Jerusalem Bible', 'Rabbi Mike Feuer', 'Rabbi Chaim Jachter', 'The Depths of Yonah', 'Torah Yesharah', 'Isaac Levy')):
        status, reason = 'include', 'Recognizable Orthodox edition or translator; verify actual edition metadata and content.'
    elif any(x in title for x in ('KING JAMES', 'CCAR Press', 'Gender-Sensitive', 'The Contemporary Torah', 'Emoji Megillah')):
        status, reason = 'exclude', 'Outside requested Orthodox translation scope.'
    else:
        status, reason = 'exclude', 'User explicitly declined all uncertain translations.'
    trans.append(dict(version_title=title, status=status, reason=reason,
        books=[v['title'] for v in entries], catalog_book_count=len(entries),
        coverage_note='Catalog presence does not guarantee complete verse coverage.',
        editions=entries, license_status='Not yet fetched'))

config = dict(schema_version=1, stage='inventory_not_build_ready', preferences=dict(
    use='personal', book_divisions=39, book_order=base,
    languages=['he', 'en'], commentary_extent='full',
    hebrew=dict(vowels=True, cantillation=False, qere='main_text', ketiv='square_brackets', divine_names='preserve_source'),
    navigation='chapters', device='Bigme B751C', reader='Existing user reader; future compatibility edits',
    primary_translation=['Metsudah', 'The Koren Jerusalem Bible'], translation_policy='All approved Orthodox English editions; all declined editions excluded',
    targum_policy='exclude', samples={'Genesis':[1], 'Deuteronomy':[32], 'I Samuel':[17], 'Isaiah':[40], 'Jonah':[1], 'Psalms':[23], 'Job':[1], 'Ruth':[3], 'Daniel':[2]}),
    cache_inputs={p.name:dict(sha256=hashlib.sha256(p.read_bytes()).hexdigest(), bytes=p.stat().st_size) for p in CACHE.glob('*.json')},
    sources=sources, translations=trans)
(OUT/'source-selection.json').write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding='utf-8')
lines = ['# Tanach EPUB source inventory', '',
    'This is a draft selection manifest, not a completed EPUB build. Catalogs are cached locally. Edition licenses, actual verse coverage, and commentary attachment still require verification.', '',
    '## Confirmed preferences', '',
    '39 separate books; Hebrew with vowels and no cantillation; qere followed by bracketed ketiv; preserve Divine names; full Hebrew and English commentary where available; Orthodox English translations; chapter navigation; personal use; Bigme B751C.', '',
    '## Samples', '', ', '.join(f'{b} {cs[0]}' for b,cs in config['preferences']['samples'].items()), '',
    '## Translation candidates', '', '| Edition | Decision | Books listed |', '|---|---|---|']
for t in trans:
    if t['status'] != 'exclude_language':
        lines.append(f"| {t['version_title'].replace('|', '/')} | {t['status']} | {t['catalog_book_count']} |")
lines += ['', 'Book counts indicate catalog entries, not verified completeness.', '', '## Modern commentary decisions', '', '| Work | Decision | Export listed |', '|---|---|---|']
for s in sources:
    if s['category'] == 'Modern Commentary on Tanakh':
        lines.append(f"| {s['title']} | {s['status']} | {'yes' if s['export_available'] else 'no'} |")
lines += ['', '## Totals', '']
for cat, count in collections.Counter(s['category'] for s in sources).items():
    lines.append(f'- {cat}: {count} titles in the table of contents.')
lines += ['', '## Remaining implementation work', '',
    '- User decisions recorded: Metsudah first, Koren fallback; no Targum; exclude all uncertain modern works and translations.',
    '- Fetch approved edition JSON and schemas, inspect language and licenses, and report missing exports.',
    '- Cache link files with hashes and download metadata; normalize range-aware note attachments without treating every citation as commentary.',
    '- Preserve original text; transform cantillation and explicitly identified qere/ketiv only in rendered output.',
    '- Build sample EPUBs and validate their packaging, links, Hebrew rendering, and actual reader behavior.', '',
    'Sources: https://github.com/Sefaria/Sefaria-Export and its linked public bucket. Catalog SHA-256 hashes are recorded in source-selection.json.']
(OUT/'source-review.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')
print(json.dumps(dict(base_books=len(base), source_titles=len(sources), translations=len(trans), source_decisions=dict(collections.Counter(s['status'] for s in sources))), indent=2))
