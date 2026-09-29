# How to sync Talmud data from Sefaria

This pipeline uses Sefaria's public export bucket and GitHub repository, the
same sources as the Tanach pipeline. All fetches are cached locally with content
hashes so the build can run fully offline after the initial sync.

## Prerequisites

- Python 3.10 or later (standard library only for sync and build)
- Internet access for the initial fetch; all subsequent builds are offline
- Java (for EPUBCheck validation); download via `python talmud/work/sync.py java`

## Step 1 — Catalog

```powershell
python talmud/work/sync.py catalog
```

Downloads:
- `https://raw.githubusercontent.com/Sefaria/Sefaria-Export/master/books.json`
  — full list of available editions.
- `https://storage.googleapis.com/sefaria-export/table_of_contents.json`
  — full TOC with category hierarchy.

Both are cached in `talmud/work/cache/` alongside `.meta.json` sidecar files.
Re-running this command is a no-op if the files already exist.

## Step 2 — Inventory

```powershell
python talmud/work/inventory.py
```

Reads the cached catalog and writes `talmud/outputs/source-selection.json` with:
- All 37 Bavli masechtos in canonical order
- Available edition metadata per masechta (Hebrew, William Davidson English)
- Available commentary sources (Rashi, Tosafot, Steinsaltz, and all others)
- Per-source coverage estimates and commentary text-size estimates

Also writes `talmud/outputs/source-review.md` — a human-readable summary.
Review this before fetching to confirm the edition choices.

## Step 3 — Fetch editions

```powershell
python talmud/work/sync.py schemas
python talmud/work/sync.py texts
python talmud/work/sync.py links
```

`schemas`: Downloads JSON schema files that describe the structure of each text
(section names, addressable depth, base text relationships). Required so the
build knows how to map commentary segments to amud/segment positions.

`texts`: Downloads every selected edition text. Uses the download plan written by
`inventory.py`. The pilot set is ~100 MB; the full Bavli + commentary is several
GB.

`links`: Downloads the Sefaria link index CSV files from the export bucket. These
supply commentary-to-base-text attachment data beyond the direct schema refs.

All three steps cache each file with a SHA-256 sidecar. Re-running skips files
that are already cached. Failures are written to `*-failures.json` files in the
cache directory.

## Step 4 — Build

```powershell
python talmud/work/build.py --pilot
```

Reads the cached texts and produces:
- `talmud/work/talmud.sqlite` — normalized intermediate database
- `talmud/outputs/books/` — one EPUB per masechta (pilot: 4 tractates)
- `talmud/outputs/build-report.json` — segment counts, warning list

For the full 37-masechta build, omit `--pilot`:
```powershell
python talmud/work/build.py
```

## Step 5 — Validate

```powershell
python talmud/work/validate.py --pilot
```

Runs EPUBCheck 5.3.0 on each generated EPUB, checks internal anchor integrity,
verifies no cantillation marks remain, and confirms structural invariants.
Results land in `talmud/work/validation/` and `talmud/outputs/full-validation-results.json`.

## Incremental rebuilds

After the first full build, use `regenerate.py` to rebuild a single masechta
from the existing SQLite without re-running the full normalization:

```powershell
python talmud/work/regenerate.py --masechta Berakhot
```

## Sefaria data sources

| Source | URL |
|---|---|
| Book edition list | https://github.com/Sefaria/Sefaria-Export |
| Text export bucket | https://storage.googleapis.com/sefaria-export/ |
| Link CSV files | Same bucket, `links/` prefix |

Data is freely available for non-commercial personal use. Always check individual
edition license fields before any distribution. This pipeline records all edition
metadata and SHA-256 content hashes in `outputs/source-selection.json`.

## Troubleshooting

**`FileNotFoundError: talmud/work/cache/books.json`**
Run `python talmud/work/sync.py catalog` first.

**`FileNotFoundError: talmud/outputs/source-selection.json`**
Run `python talmud/work/inventory.py` before `sync.py texts`.

**`AssertionError: Missing Hebrew masechtos`**
Some masechtos may not be in the Sefaria export yet or use different title
spellings. Check `talmud/work/cache/books.json` and update `MASECHTA_ORDER` in
`build.py` if needed. Open an issue in `docs/talmud-epub-plan.md`.

**Slow downloads**
The link CSV files are large. `sync.py links` uses 8 parallel workers; this is
safe for Sefaria's public bucket. If rate-limited, reduce `max_workers` in
`sync.py`.
