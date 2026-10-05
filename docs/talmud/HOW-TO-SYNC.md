# How to sync and build the Talmud data

This pipeline uses Sefaria's public export bucket and GitHub repository, the same
sources as Tanach. Every download is cached with a content hash, so after the first
sync the build runs fully offline. Run all commands from the repository root.

## Before you start

- Python 3.10 or later (standard library only for sync and build).
- Internet access for the first download only.
- Java for EPUBCheck validation: `python talmud/work/sync.py java` fetches it into
  `talmud/work/tools/` (unpacked, not installed). EPUBCheck 5.4.0 was used at the
  last run.

## Steps

**1. Catalog**

```powershell
python talmud/work/sync.py catalog
```

Downloads Sefaria's full edition list (`books.json`, from the Sefaria-Export GitHub
repository) and its table of contents with category hierarchy (from the export
bucket), caching both in `talmud/work/cache/`. Repeating it is harmless.

**2. Inventory**

```powershell
python talmud/work/inventory.py
```

Writes `talmud/outputs/source-selection.json` (the 37 tractates in order, available
Hebrew and William Davidson English editions, available commentaries with coverage
and size estimates) and a readable summary, `talmud/outputs/source-review.md`.
Review the summary before fetching.

**3. Fetch editions**

```powershell
python talmud/work/sync.py schemas
python talmud/work/sync.py texts
python talmud/work/sync.py links
```

- `schemas`: structure files that tell the build how commentary lines up with each
  amud and segment.
- `texts`: every selected edition (the pilot is about 100 MB; the full Bavli plus
  commentary is several GB).
- `links`: Sefaria's link files, which supply commentary-to-text attachments beyond
  the direct references. They are large; downloads use 8 parallel workers, which is
  safe for Sefaria's public bucket. If you are rate-limited, lower `max_workers` in
  `sync.py`.

Files already cached are skipped. Failures are written to `*-failures.json` in the
cache folder. (The last full sync, on 5 Oct 2026, fetched 264 of 264 texts and 17 of
17 link files; the only misses were the known Ta'anit, Mo'ed Katan, and Me'ilah
schemas.)

**4. Build**

```powershell
python talmud/work/build.py --pilot
```

Produces `talmud/work/talmud.sqlite` (the working database), one EPUB per tractate in
`talmud/outputs/books/` (pilot: six tractates), and `talmud/outputs/build-report.json`
(segment counts and warnings). For the full 37, leave off `--pilot`.

**5. Validate**

```powershell
python talmud/work/validate.py --pilot
```

Runs EPUBCheck, checks internal links, confirms no cantillation marks remain, and
checks structure. Results go to `talmud/work/validation/` and
`talmud/outputs/full-validation-results.json`. Also run
`python talmud/work/audit_links.py --pilot`.

## Rebuilding one tractate

After the first full build, rebuild a single tractate from the existing database:

```powershell
python talmud/work/regenerate.py --masechta Berakhot
```

Use a full `build.py --pilot` (not `regenerate.py`) when the amud labeling or the
source data changed.

## Data sources

| Source | Location |
|---|---|
| Edition list | github.com/Sefaria/Sefaria-Export |
| Text export | storage.googleapis.com/sefaria-export/ |
| Link files | same bucket, `links/` prefix |

Free for non-commercial personal use. Always check each edition's license field before
any distribution; the pipeline records edition details and SHA-256 hashes in
`outputs/source-selection.json`.

## Troubleshooting

| Error | Fix |
|---|---|
| `FileNotFoundError: talmud/work/cache/books.json` | Run `sync.py catalog` first |
| `FileNotFoundError: talmud/outputs/source-selection.json` | Run `inventory.py` before `sync.py texts` |
| `AssertionError: Missing Hebrew masechtos` | A tractate is missing from the export or spelled differently. Check `books.json` and update `MASECHTA_ORDER` in `build.py` if needed, then note it in `docs/talmud-epub-plan.md` |
