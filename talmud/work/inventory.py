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
# NOTE (Oct 2026): Sefaria spells three titles without apostrophes
# (Taanit, Moed Katan, Meilah). We use Sefaria's spelling here so catalog
# lookups, schema URLs, and link matching work. Traditional spellings
# Ta'anit / Mo'ed Katan / Me'ilah are display aliases only.
MASECHTA_ORDER = [
    # Seder Zeraim
    'Berakhot',
    # Seder Moed
    'Shabbat', 'Eruvin', 'Pesachim', 'Rosh Hashanah', 'Yoma', 'Sukkah',
    'Beitzah', 'Taanit', 'Megillah', 'Moed Katan', 'Chagigah',
    # Seder Nashim
    'Yevamot', 'Ketubot', 'Nedarim', 'Nazir', 'Sotah', 'Gittin', 'Kiddushin',
    # Seder Nezikin
    'Bava Kamma', 'Bava Metzia', 'Bava Batra', 'Sanhedrin', 'Makkot',
    'Shevuot', 'Avodah Zarah', 'Horayot',
    # Seder Kodashim
    'Zevachim', 'Menachot', 'Chullin', 'Bekhorot', 'Arakhin', 'Temurah',
    'Keritot', 'Meilah', 'Tamid',
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
    # Tamid has an anonymous commentator printed in Vilna in place of Rashi.
    # Sefaria titles it "Mefaresh on Tamid" (confirmed Oct 2026).
    'Tamid': 'Mefaresh on Tamid',
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
    # Blacklist policy (Oct 2026): include every Bavli commentary Sefaria
    # offers in Hebrew or English. Only the edition-level language filter
    # below excludes anything.
    # Sefaria files most commentaries UNDER Talmud/Bavli (e.g. categories
    # ['Talmud','Bavli','Rishonim on Talmud',...]), so the commentary check
    # must come before the base-text skip. Only true base-text nodes
    # (masechtos without commentary markers) are skipped.
    commentary_titles = set()
    for n in _walk(toc):
        cats = n.get('categories', [])
        is_commentary = any(
            c in cats
            for c in ('Rishonim on Talmud', 'Acharonim on Talmud', 'Modern Commentary on Talmud')
        )
        if is_commentary:
            # TOC also lists Yerushalmi/Mishnah commentaries under similar
            # markers — keep only Bavli here; the books.json scan below
            # enforces the same rule.
            if 'Bavli' in cats or 'Yerushalmi' not in cats and 'Mishnah' not in cats:
                commentary_titles.add(n['title'])
            continue
        if 'Talmud' in cats and 'Bavli' in cats:
            continue  # base text, guides, minor tractates
    # books.json scan: the TOC walk above only found ~124 titles (mostly
    # Rashi/Tosafot/Steinsaltz). Sefaria actually ships ~1000+ Bavli
    # commentaries (Maharsha, Pnei Yehoshua, etc.). Catch them by title
    # suffix + Bavli category. Requires 'Bavli' in categories so
    # Yerushalmi ("... on Jerusalem Talmud X") and Mishnah ("... on Mishnah
    # X") titles are excluded even though they share the masechta name.
    for b in books:
        title = b.get('title', '')
        if title in MASECHTA_ORDER:
            continue  # base text itself
        cats = b.get('categories', [])
        if 'Talmud' not in cats or 'Bavli' not in cats:
            continue
        if not any(title.endswith(f' on {m}') for m in MASECHTA_ORDER):
            continue
        commentary_titles.add(title)
    # Also add explicitly required pilot sources (in case a spelling drifts).
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
        """Blacklist policy: include everything on the Bavli.

        Language filtering happens at the edition level in the download
        plan (Hebrew + English only, skip merged/test/[fr]/[de]). There is
        currently no title-level blacklist.
        """
        return 'include', 'All Bavli commentaries included (blacklist policy, Oct 2026).'

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
        """Return the highest-priority Hebrew text edition for a masechta.

        Sefaria ships two Davidson Hebrew editions: plain "Aramaic"
        (unpointed) and "Vocalized Aramaic" (niqqud + punctuation). The
        reader's vowel toggle and search normalization assume pointed text,
        so Vocalized wins everywhere it exists (all 37 masechtos, verified
        Oct 2026: Berakhot Vocalized carries ~227k marks in U+0591-05C7,
        plain Aramaic zero).
        """
        candidates = [
            b for b in editions_by_title.get(title, [])
            if b.get('language', '').upper() == 'HEBREW' and b.get('versionTitle', '') != 'merged'
            and b.get('json_url')
        ]
        for c in candidates:
            if 'Vocalized' in c.get('versionTitle', ''):
                return c
        # Fallback if a masechta ever loses its vocalized edition.
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

    def _edition_ok(edition):
        """Blacklist: Hebrew/English only, no merged/test/junk."""
        if edition.get('versionTitle', '') == 'merged':
            return False
        if not edition.get('json_url'):
            return False
        # Owner decision Oct 2026: English + Hebrew only. Skip French,
        # German, and other languages at inventory time so they are never
        # downloaded or built (this was the cause of the Berakhot [fr]
        # language-mismatch warnings). Note: Sefaria mislabels the French
        # editions as language=English, so also match versionTitle.
        if edition.get('language', '').upper() not in ('HEBREW', 'ENGLISH'):
            return False
        _vt = edition.get('versionTitle', '')
        if '[fr]' in _vt or '[de]' in _vt or 'german' in _vt.lower():
            return False
        if re.search(r'(^test\b|\btest$|abbreviated|summary)', _vt, re.I):
            return False
        return True

    def _rank_edition(e):
        vt = e.get('versionTitle', '')
        score = 0
        if 'Vilna' in vt or 'William Davidson' in vt:
            score += 1000
        if 'Wikisource' in vt:
            score += 100
        score += float(e.get('priority') or 0)
        return score

    for src in sources:
        if src['status'] != 'include':
            continue
        # Blacklist policy: every Hebrew/English edition except merged,
        # test/abridged/summary, and mislabeled [fr]/[de]/german.
        # Steady: the build processes one masechta at a time, so keeping all
        # editions is laptop-safe (no in-memory blowup).
        for edition in src['available_versions']:
            if not _edition_ok(edition):
                continue
            lang = 'he' if edition.get('language', '').upper() == 'HEBREW' else 'en'
            download_plan.append(dict(
                title=src['title'],
                role='commentary',
                language=lang,
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
                    'Blacklist policy Oct 2026: include all Bavli commentaries; '
                    'exclude only non-Hebrew/non-English, merged, test/abridged, '
                    'and [fr]/[de] editions. Download and build steady (batched, '
                    'one masechta at a time).'
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
        'William Davidson (Steinsaltz) English; all Bavli commentaries in '
        'Hebrew/English (blacklist policy Oct 2026); personal use; Bigme B751C.',
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
        '## Commentary sources (blacklist policy)',
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
        f'{len(download_plan)} edition files to fetch (base texts + all commentaries, Hebrew/English only).',
        '',
        '## Remaining steps',
        '',
        '1. Review this file, then run: python talmud/work/sync.py schemas',
        '2. python talmud/work/sync.py texts [--masechta Berakhot for one book at a time]',
        '3. python talmud/work/sync.py links',
        '4. python talmud/work/build.py --pilot (quick check) or --masechta Berakhot (one book)',
        '5. python talmud/work/validate.py --pilot',
        '6. Measure EPUB sizes and first-open times on the Bigme.',
        '7. Build remaining masechtos one at a time per the blacklist policy.',
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
