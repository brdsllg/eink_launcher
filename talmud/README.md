# Talmud EPUB pipeline

This segment of the reader repository produces Talmud Bavli EPUBs for personal
use on the Bigme e-ink device. It mirrors the layout and tooling of `tanach/`
and shares the same reader contract. Read `tanach/docs/tanach-epub.md` and
`tanach/outputs/reader-compatibility.md` first; the Talmud product follows those
conventions wherever this document is silent.

Current status: **pilot pipeline ready — no data fetched yet.**
Run `python work/sync.py catalog` to begin.

## What this produces

One EPUB per masechta, one XHTML document per amud (side of a folio). Bilingual
Hebrew/Aramaic + William Davidson English translation, with Rashi, Tosafot, and
Steinsaltz notes as the pilot commentary set.

Final scope: the traditional 37 masechtos of Talmud Bavli with Gemara. The pilot
covers six representative amudim; see `docs/talmud-epub-plan.md` for the list.

## Layout

| Path | Purpose |
|---|---|
| `docs/talmud-epub-plan.md` | Planning document and decisions |
| `work/sync.py` | Download and cache Sefaria data |
| `work/inventory.py` | Build source selection manifest |
| `work/build.py` | Normalize to SQLite and generate EPUBs |
| `work/validate.py` | EPUBCheck + structural checks |
| `work/regenerate.py` | CLI wrapper — rebuild from existing SQLite |
| `work/package_samples.py` | Package pilot amudim as a sample set |
| `work/audit_hebrew.py` | Verify no cantillation marks remain in output |
| `work/audit_links.py` | Verify note and chapter cross-links resolve |
| `work/inventory_report.py` | Produce a per-tractate commentary coverage table |
| `work/talmud.sqlite` | Normalized intermediate database (generated) |
| `outputs/` | Generated EPUBs, reports, and zips |

## Commands

All commands run from the repository root with `python talmud/work/<script>.py`.

```powershell
# 1. Download the Sefaria catalog (table of contents + book list)
python talmud/work/sync.py catalog

# 2. Build a source-selection manifest with per-tractate coverage
python talmud/work/inventory.py

# 3. Fetch text and commentary editions
python talmud/work/sync.py schemas
python talmud/work/sync.py texts
python talmud/work/sync.py links

# 4. Normalize into talmud.sqlite and generate pilot EPUBs
python talmud/work/build.py --pilot

# 5. Validate pilot EPUBs
python talmud/work/validate.py --pilot

# 6. Package pilot samples
python talmud/work/package_samples.py

# 7. Full 37-masechta build (after measuring pilot)
python talmud/work/build.py
python talmud/work/validate.py
```

Single-masechta rebuild (after the first full build):
```powershell
python talmud/work/regenerate.py --masechta Berakhot
```

## Design decisions

See `docs/talmud-epub-plan.md` for all settled decisions, open questions, and
the commentary-expansion plan.

## Licensing

Personal use only. Never commit generated EPUBs or raw Sefaria data to a public
repository or its releases. Store them via private LFS or direct local copy.
Record edition and license metadata in `outputs/source-selection.json`; personal
use is not a blanket license determination.
