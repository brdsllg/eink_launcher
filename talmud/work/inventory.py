"""Build a reproducible, offline Talmud Bavli source inventory.

Reads the cached Sefaria catalog and writes:
  outputs/source-selection.json  — full edition/commentary manifest
  outputs/source-review.md       — human-readable summary
  work/cache/download-plan.json  — list of files to fetch with sync.py texts

Mirrors tanach/work/inventory.py.  Never treats 'merged' editions as approved.
Run after sync.py catalog.
"""
import collections
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'work' / 'cache'
OUT = ROOT / 'outputs'
OUT.mkdir(exist_ok=True)
(ROOT / 'work').mkdir(exist_ok=True)

# ─── Canonical masechta order ────────────────────────────────────────────────
# Traditional Bavli, 37 masechtos with Gemara, in seder order.
# Mishnah-only tractates are excluded per the plan.
MASECHTA_ORDER = [
    # Seder Zeraim
    'Berakhot',
    # Seder Moed
    'Shabbat', 'Eruvin', 'Pesachim', 'Rosh Hashanah', 'Yoma', 'Sukkah',
    'Beitzah', "Ta'anit", 'Megillah', "Mo'ed Katan", 'Chagigah',
    # Seder Nashim
    'Yevamot', 'Ketubot', 'Nedarim', 'Nazir', 'Sotah', 'Gittin', 'Kiddushin',
    # Seder Nezikin
    'Bava Kamma', 'Bava Metzia', 'Bava Batra', 'Sanhedrin', 'Makkot',
    'Shevuot', 'Avodah Zarah', 'Horayot',
    # Seder Kodashim
    'Zevachim', 'Menachot', 'Chullin', 'Bekhorot', 'Arakhin', 'Temurah',
    'Keritot', "Me'ilah", 'Tamid',
    # Seder Tohorot
    'Niddah',
]
assert len(MASECHTA_ORDER) == 37, len(MASECHTA_ORDER)

# Pilot amudim from the plan.  These are the only segments built in --pilot mode.
PILOT_AMUDIM = [
    ('Berakhot', '2a'),
    ('Berakhot', '2b'),
    ('Bava Metzia', '2a'),
    ('Bava Batra', '29a'),
    ('Sanhedrin', '96b'),
    ('Sanhedrin', '97a'),
    ('Tamid', '25b'),
    ('Shabbat', '73a'),
]
PILOT_MASECHTOS = list(dict.fromkeys(m for m, _ in PILOT_AMUDIM))

# Commentary sources to include in the pilot, in display order.
PILOT_COMMENTARY_ORDER = ['Rashi', 'Tosafot', 'Steinsaltz']
# Generic Rashi-slot sources: some masechtos substitute a different commentator.
RASHI_SLOT_ALIASES = {
    # From Bava Batra 29a onward, Rashbam replaces Rashi.
    'Bava Batra': 'Rashbam on Bava Batra',
    # Tamid has an anonymous commentator; Sefaria lists it as "Pseudo-Rashi on Tamid".
    'Tamid': 'Pseudo-Rashi on Tamid',
}


def _key(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24]


def _walk(nodes):
    for node in nodes:
        if 'title' in node:
            yield node
        yield from _walk(node.get('contents', []))


def main():
    books_path = CACHE / 'books.json'
    toc_path = CACHE / 'table_of_contents.json'
    if not books_path.exists() or not toc_path.exists():
        raise FileNotFoundError(
            'Run sync.py catalog first to download books.json and table_of_contents.json'
        )

    books = json.loads(books_path.read_text(encoding='utf-8-sig'))['books']
    toc = json.loads(toc_path.read_text(encoding='utf-8-sig'))

    # ── Find Bavli masechtos in the TOC ─────────────────────────────────────
    bavli_nodes = {
        n['title']: n
        for n in _walk(toc)
        if n.get('categories', [None])[0] == 'Talmud'
        and 'Bavli' in n.get('categories', [])
    }

    # ── Index available editions by title ───────────────────────────────────
    editions_by_title = collections.defaultdict(list)
    for b in books:
        if b['title'] in bavli_nodes or any(
            b['title'].startswith(m + ' on ') or
            b['title'].startswith('Steinsaltz on ') or
            b['title'] in (
                f'Rashi on {m}' for m in MASECHTA_ORDER
            ) or
            b['title'] in (
                f'Tosafot on {m}' for m in MASECHTA_ORDER
            )
            for m in MASECHTA_ORDER
        ):
            editions_by_title[b['title']].append(b)
        # Broader catch: any Talmud-category title
        if 'Talmud' in b.get('categories', []):
            editions_by_title[b['title']].append(b)

    # De-duplicate (the loop above can double-count)
    for title in list(editions_by_title):
        seen = set()
        deduped = []
        for e in editions_by_title[title]:
            k = (e.get('json_url', ''), e.get('versionTitle', ''), e.get('language', ''))
            if k not in seen:
                seen.add(k)
                deduped.append(e)
        editions_by_title[title] = deduped

    # ── Verify all 37 masechtos appear in the catalog ───────────────────────
    missing_from_catalog = [m for m in MASECHTA_ORDER if m not in bavli_nodes and m not in editions_by_title]
    # Not every masechta may have a TOC node; some appear only in books.json.
    # That is acceptable; we rely on editions_by_title for the download plan.

    # ── Build sources list (commentaries) ───────────────────────────────────
    # Find all commentary and supercommentary titles linked to Bavli.
    commentary_titles = set()
    for n in _walk(toc):
        cats = n.get('categories', [])
        if 'Talmud' in cats and 'Bavli' in cats:
            continue  # base text
        if any(
            c in cats
            for c in ('Rishonim on Talmud', 'Acharonim on Talmud', 'Modern Commentary on Talmud')
        ):
            commentary_titles.add(n['title'])
    # Also add explicitly required pilot sources.
    for m in MASECHTA_ORDER:
        for prefix in ('Rashi on', 'Tosafot on', 'Steinsaltz on'):
            t = f'{prefix} {m}'
            if editions_by_title.get(t):
                commentary_titles.add(t)
        # Rashi-slot aliases
        alias = RASHI_SLOT_ALIASES.get(m)
        if alias and editions_by_title.get(alias):
            commentary_titles.add(alias)

    def _commentary_status(title, cats):
        """Pilot policy: include the three pilot sources; mark everything else 'review'."""
        for m in MASECHTA_ORDER:
            if title in (f'Rashi on {m}', f'Tosafot on {m}', f'Steinsaltz on {m}'):
                return 'include', 'Pilot commentary set.'
            alias = RASHI_SLOT_ALIASES.get(m)
            if alias and title == alias:
                return 'include', 'Rashi-slot substitute for this masechta (pilot set).'
        return 'review', (
            'Not in pilot set. Include after measuring pilot EPUB sizes and load times. '
            'See docs/talmud/docs/talmud-epub-plan.md commentary-policy section.'
        )

    sources = []
    for title in sorted(commentary_titles):
        node = bavli_nodes.get(title, {})
        cats = node.get('categories', [])
        status, reason = _commentary_status(title, cats)
        sources.append(dict(
            title=title,
            status=status,
            reason=reason,
            description=node.get('enShortDesc', ''),
            sort_order=len(sources),
            available_versions=editions_by_title.get(title, []),
            export_available=bool(editions_by_title.get(title)),
            selected_versions=[],
            license_status='Read individual JSON license fields before build',
            edition_decisions={},
        ))

    # ── Build download plan ──────────────────────────────────────────────────
    # For each masechta: one Hebrew edition + William Davidson English.
    # For each included commentary source: all available non-merged editions.
    download_plan = []

    def _best_hebrew(title):
        """Return the highest-priority Hebrew text edition for a masechta."""
        candidates = [
            b for b in editions_by_title.get(title, [])
            if b.get('language', '').upper() == 'HEBREW' and b.get('versionTitle', '') != 'merged'
            and b.get('json_url')
        ]
        # Prefer 'William Davidson Edition - Aramaic' or 'Wikisource Talmud Bavli'
        for pref in ('William Davidson', 'Wikisource', 'Vilna'):
            for c in candidates:
                if pref in c.get('versionTitle', ''):
                    return c
        return candidates[0] if candidates else None

    def _davidson_english(title):
        """Return the William Davidson English edition, if available."""
        candidates = [
            b for b in editions_by_title.get(title, [])
            if b.get('language', '').upper() == 'ENGLISH'
            and 'William Davidson' in b.get('versionTitle', '')
            and b.get('versionTitle', '') != 'merged'
            and b.get('json_url')
        ]
        return candidates[0] if candidates else None

    for masechta in MASECHTA_ORDER:
        he = _best_hebrew(masechta)
        en = _davidson_english(masechta)
        if he:
            download_plan.append(dict(
                title=masechta,
                role='hebrew',
                language='he',
                versionTitle=he.get('versionTitle', ''),
                json_url=he['json_url'],
                source_category='base',
                sort_order=0,
            ))
        if en:
            download_plan.append(dict(
                title=masechta,
                role='translation',
                language='en',
                versionTitle=en.get('versionTitle', ''),
                json_url=en['json_url'],
                source_category='base',
                sort_order=1,
            ))

    for src in sources:
        if src['status'] != 'include':
            continue
        for edition in src['available_versions']:
            if edition.get('versionTitle', '') == 'merged':
                continue
            if not edition.get('json_url'):
                continue
            download_plan.append(dict(
                title=src['title'],
                role='commentary',
                language=edition.get('language', 'he'),
                versionTitle=edition.get('versionTitle', ''),
                json_url=edition['json_url'],
                source_category='commentary',
                sort_order=src['sort_order'],
            ))

    # ── Compute coverage estimates ───────────────────────────────────────────
    # We cannot compute text sizes until we fetch, so record edition counts.
    coverage = {}
    for masechta in MASECHTA_ORDER:
        he_count = sum(
            1 for b in editions_by_title.get(masechta, [])
            if b.get('language', '').upper() == 'HEBREW' and b.get('versionTitle') != 'merged'
        )
        en_count = sum(
            1 for b in editions_by_title.get(masechta, [])
            if b.get('language', '').upper() == 'ENGLISH' and b.get('versionTitle') != 'merged'
        )
        has_davidson = any(
            'William Davidson' in b.get('versionTitle', '')
            for b in editions_by_title.get(masechta, [])
            if b.get('language', '').upper() == 'ENGLISH'
        )
        coverage[masechta] = dict(
            he_editions=he_count,
            en_editions=en_count,
            has_william_davidson_english=has_davidson,
            commentary_sources=[
                s['title'] for s in sources
                if s['status'] == 'include'
                and masechta in s['title']
            ],
        )

    # ── Write outputs ────────────────────────────────────────────────────────
    config = dict(
        schema_version=1,
        stage='inventory_not_build_ready',
        preferences=dict(
            use='personal',
            corpus='Talmud Bavli',
            masechta_count=37,
            masechta_order=MASECHTA_ORDER,
            pilot_masechtos=PILOT_MASECHTOS,
            pilot_amudim=PILOT_AMUDIM,
            languages=['he', 'en'],
            hebrew=dict(
                nikud=True,
                cantillation=False,
            ),
            english=dict(
                primary_translation='William Davidson (Steinsaltz)',
                policy='William Davidson only; missing segments stay blank',
            ),
            commentary=dict(
                pilot_set=['Rashi', 'Tosafot', 'Steinsaltz'],
                rashi_slot_aliases=RASHI_SLOT_ALIASES,
                picker_order=['Rashi/Rashi-slot', 'Tosafot', 'everything else'],
                expansion_policy=(
                    'Blacklist preferred. Measure pilot first, then add sources in batches.'
                ),
            ),
            segment_unit='Sefaria segment (e.g. Berakhot 2a:1)',
            chapter_unit='amud (one XHTML document per side)',
            packaging='one EPUB per masechta',
            device='Bigme B751C',
        ),
        cache_inputs={
            p.name: dict(
                sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
                bytes=p.stat().st_size,
            )
            for p in CACHE.glob('*.json')
        },
        sources=sources,
        masechta_coverage=coverage,
        missing_from_catalog=missing_from_catalog,
    )

    OUT.mkdir(exist_ok=True)
    (OUT / 'source-selection.json').write_text(
        json.dumps(config, ensure_ascii=False, indent=2), encoding='utf-8'
    )
    (CACHE / 'download-plan.json').write_text(
        json.dumps(download_plan, ensure_ascii=False, indent=2), encoding='utf-8'
    )

    # ── Human-readable summary ───────────────────────────────────────────────
    include_count = sum(1 for s in sources if s['status'] == 'include')
    review_count = sum(1 for s in sources if s['status'] == 'review')
    lines = [
        '# Talmud Bavli EPUB source inventory',
        '',
        'Draft selection manifest. Catalogs are cached locally. '
        'Edition licenses, actual amud coverage, and commentary attachment '
        'still require verification after fetching.',
        '',
        '## Confirmed preferences',
        '',
        '37 masechtos of Talmud Bavli with Gemara; Hebrew with nikud; '
        'William Davidson (Steinsaltz) English; Rashi, Tosafot, Steinsaltz '
        'commentary for the pilot; personal use; Bigme B751C.',
        '',
        '## Pilot masechtos',
        '',
        ', '.join(PILOT_MASECHTOS),
        '',
        '## Pilot amudim',
        '',
    ]
    for masechta, amud in PILOT_AMUDIM:
        lines.append(f'- {masechta} {amud}')
    lines += [
        '',
        '## Masechta catalog coverage',
        '',
        '| Masechta | Hebrew eds | English eds | William Davidson? |',
        '|---|---|---|---|',
    ]
    for m in MASECHTA_ORDER:
        cv = coverage[m]
        wd = 'yes' if cv['has_william_davidson_english'] else '**missing**'
        lines.append(
            f"| {m} | {cv['he_editions']} | {cv['en_editions']} | {wd} |"
        )
    lines += [
        '',
        '## Pilot commentary sources',
        '',
        f'Included: {include_count} | Pending review: {review_count}',
        '',
        '| Title | Status |',
        '|---|---|',
    ]
    for s in sources:
        if s['status'] == 'include':
            lines.append(f"| {s['title']} | include |")
    lines += [
        '',
        '## Download plan',
        '',
        f'{len(download_plan)} edition files to fetch (base texts + pilot commentaries).',
        '',
        '## Remaining steps',
        '',
        '1. Review this file, then run: python talmud/work/sync.py schemas',
        '2. python talmud/work/sync.py texts',
        '3. python talmud/work/sync.py links',
        '4. python talmud/work/build.py --pilot',
        '5. python talmud/work/validate.py --pilot',
        '6. Measure EPUB sizes and first-open times on the Bigme.',
        '7. Expand commentary per the blacklist policy in docs/talmud/docs/talmud-epub-plan.md.',
    ]
    (OUT / 'source-review.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')

    print(json.dumps(dict(
        masechtos=len(MASECHTA_ORDER),
        pilot_masechtos=len(PILOT_MASECHTOS),
        pilot_amudim=len(PILOT_AMUDIM),
        commentary_sources=len(sources),
        included_sources=include_count,
        download_plan_items=len(download_plan),
        missing_from_catalog=missing_from_catalog,
    ), indent=2))


if __name__ == '__main__':
    main()
