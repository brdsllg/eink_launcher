"""Package the pilot amudim as a sample zip for device testing.

Produces:
  outputs/talmud-samples.zip      — one EPUB per pilot masechta
  outputs/sample-checksums.json   — SHA-256 per sample EPUB
  outputs/sample-guide.md         — what each pilot covers and why

Run after build.py --pilot and validate.py --pilot.

Mirrors tanach/work/package_samples.py.
"""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'outputs'
BOOKS = OUT / 'books'


def main():
    config_path = OUT / 'source-selection.json'
    if not config_path.exists():
        raise FileNotFoundError('Run inventory.py first')
    config = json.loads(config_path.read_text(encoding='utf-8'))

    from build import slug
    pilot_masechtos = config['preferences'].get('pilot_masechtos', [])
    pilot_amudim = config['preferences'].get('pilot_amudim', [])

    sample_epubs = []
    missing = []
    for masechta in pilot_masechtos:
        p = BOOKS / f'{slug(masechta)}.epub'
        if p.exists():
            sample_epubs.append(p)
        else:
            missing.append(masechta)

    if missing:
        print(f'WARNING: Missing pilot EPUBs: {missing}')
        print('Run build.py --pilot first.')

    if not sample_epubs:
        raise RuntimeError('No pilot EPUBs found. Run build.py --pilot.')

    # Validate that samples passed EPUBCheck (check validation results)
    validation_path = OUT / 'full-validation-results.json'
    if validation_path.exists():
        results = json.loads(validation_path.read_text())
        failed = [
            r['file'] for r in results
            if r.get('epubcheck_exit', -1) != 0 or r.get('structure') != 'pass'
        ]
        if failed:
            print(f'WARNING: These EPUBs failed validation: {failed}')
            print('Fix validation errors before packaging samples for device testing.')

    # Write zip
    zip_path = OUT / 'talmud-samples.zip'
    checksums = {}
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in sample_epubs:
            data = p.read_bytes()
            checksums[p.name] = hashlib.sha256(data).hexdigest()
            z.writestr(p.name, data)

    (OUT / 'sample-checksums.json').write_text(
        json.dumps(checksums, indent=2), encoding='utf-8'
    )

    # Sample guide
    lines = [
        '# Talmud Bavli EPUB pilot sample set',
        '',
        'Pilot amudim for device testing on the Bigme B751C. '
        'Not the complete 37-masechta collection.',
        '',
        '## Your settings',
        '',
        '- William Davidson (Steinsaltz) English beneath the Hebrew/Aramaic.',
        '- Rashi (or its masechta-specific substitute), Tosafot, Steinsaltz notes.',
        '- One EPUB per masechta, one XHTML document per amud.',
        '- Nikud included; cantillation stripped.',
        '',
        '## Pilot amudim',
        '',
        '| Masechta | Amud | Why |',
        '|---|---|---|',
    ]
    reasons = {
        ('Berakhot', '2a'): 'Opening sugya, dense Rashi and Tosafot, baseline',
        ('Berakhot', '2b'): 'Opening sugya continued',
        ('Bava Metzia', '2a'): 'Casuistic Nezikin sugya, dense Tosafot',
        ('Bava Batra', '29a'): 'Rashbam replaces Rashi from here',
        ('Sanhedrin', '96b'): 'Aggadic content, Steinsaltz notes',
        ('Sanhedrin', '97a'): 'Aggadic content continued',
        ('Tamid', '25b'): 'Smallest tractate, anonymous commentator in Rashi slot',
        ('Shabbat', '73a'): 'List of 39 melachos, heavy commentary',
    }
    for masechta, amud in pilot_amudim:
        reason = reasons.get((masechta, amud), '')
        lines.append(f'| {masechta} | {amud} | {reason} |')

    lines += [
        '',
        '## What to check on device',
        '',
        '1. First-open import time for each masechta.',
        '2. Page-turn speed with commentary visible.',
        '3. Hebrew/Aramaic rendering (nikud, RTL, font).',
        '4. Commentary navigation — tap "Notes & commentary" link, tap back.',
        '5. Amud TOC navigation.',
        '6. Search: enter a Hebrew word; check result count and navigation.',
        '',
        '## Masechtos in this sample',
        '',
    ]
    for masechta in pilot_masechtos:
        amud_list = [a for m, a in pilot_amudim if m == masechta]
        lines.append(f'- **{masechta}**: amudim {", ".join(amud_list)}')

    lines += [
        '',
        '## SHA-256 checksums',
        '',
    ]
    for fname, sha in checksums.items():
        lines.append(f'- `{fname}`: `{sha}`')

    (OUT / 'sample-guide.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')

    print(f'Packaged {len(sample_epubs)} pilot EPUBs → {zip_path}')
    print(json.dumps(checksums, indent=2))


if __name__ == '__main__':
    main()
