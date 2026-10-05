"""Produce a per-tractate commentary coverage table from the Sefaria catalog.

Run after sync.py catalog and inventory.py.  Does NOT require fetching texts.
Output: outputs/commentary-coverage.md — human-readable table with
per-masechta availability for every linked commentary source, plus total
text size estimates where editions have been downloaded.

Usage:
  python talmud/work/inventory_report.py
"""
import collections
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'work' / 'cache'
OUT = ROOT / 'outputs'


def main():
    config_path = OUT / 'source-selection.json'
    if not config_path.exists():
        raise FileNotFoundError('Run inventory.py first')
    config = json.loads(config_path.read_text(encoding='utf-8'))

    masechta_order = config['preferences']['masechta_order']
    sources = config.get('sources', [])

    # Build a set of commentary titles actually linked to each masechta.
    # We rely on the available_versions field in source-selection.json.
    masechta_to_sources: dict[str, list[str]] = collections.defaultdict(list)
    for s in sources:
        title = s['title']
        for m in masechta_order:
            if f' on {m}' in title or f'on {m}' in title:
                masechta_to_sources[m].append(title)

    # Source names without the masechta suffix, for the column header.
    def _short_name(title, masechta):
        return title.replace(f' on {masechta}', '').strip()

    # All unique short names across the corpus.
    all_short_names: list[str] = []
    seen: set[str] = set()
    for m in masechta_order:
        for title in masechta_to_sources[m]:
            sn = _short_name(title, m)
            if sn not in seen:
                seen.add(sn)
                all_short_names.append(sn)

    # Pilot sources first in display order.
    pilot_order = ['Rashi', 'Rashbam', 'Mefaresh', 'Tosafot', 'Steinsaltz']
    ordered_names = [n for n in pilot_order if n in seen]
    ordered_names += [n for n in all_short_names if n not in set(ordered_names)]

    # Build coverage matrix.
    matrix: dict[str, dict[str, str]] = {}
    for m in masechta_order:
        row = {}
        short_names_here = {_short_name(t, m) for t in masechta_to_sources[m]}
        for sn in ordered_names:
            if sn in short_names_here:
                # Check download status
                full_title = next(
                    (t for t in masechta_to_sources[m] if _short_name(t, m) == sn),
                    None,
                )
                cached = False
                if full_title:
                    src_entry = next(
                        (s for s in sources if s['title'] == full_title), None
                    )
                    if src_entry and src_entry.get('available_versions'):
                        import hashlib
                        for ed in src_entry['available_versions']:
                            cache_file = CACHE / 'texts' / (
                                hashlib.sha256(ed.get('json_url', '').encode()).hexdigest()[:24] + '.json'
                            )
                            if cache_file.exists():
                                cached = True
                                break
                row[sn] = '✓ fetched' if cached else '✓'
            else:
                row[sn] = '—'
        matrix[m] = row

    # Write markdown table.
    # Limit columns to keep the table readable; show pilot cols first.
    display_cols = ordered_names[:12]  # cap at 12 columns
    header = '| Masechta | ' + ' | '.join(display_cols) + ' |'
    sep = '|---|' + '---|' * len(display_cols)
    lines = [
        '# Talmud Bavli commentary coverage per masechta',
        '',
        'Generated from Sefaria catalog. '
        '"✓" = source linked in catalog; "✓ fetched" = edition also cached locally; "—" = not linked.',
        '',
        f'Showing first {len(display_cols)} of {len(ordered_names)} unique commentary sources.',
        '',
        header,
        sep,
    ]
    for m in masechta_order:
        row_cells = [matrix[m].get(sn, '—') for sn in display_cols]
        lines.append('| ' + m + ' | ' + ' | '.join(row_cells) + ' |')

    lines += [
        '',
        '## Notes',
        '',
        '- Rashi is replaced by Rashbam in Bava Batra from 29a.',
        '- Tamid uses Mefaresh (anonymous Vilna commentary in the Rashi slot).',
        '- Coverage of non-pilot commentaries varies significantly by masechta.',
        '- Run inventory.py then sync.py texts to download editions.',
    ]

    out_path = OUT / 'commentary-coverage.md'
    out_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'Coverage table written to {out_path}')
    print(f'  {len(masechta_order)} masechtos × {len(ordered_names)} commentary sources')


if __name__ == '__main__':
    main()
