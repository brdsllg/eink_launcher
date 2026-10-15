# How to sync and build the Talmud data

This pipeline uses Sefaria's public export bucket and GitHub repository, the same
sources as Tanach. Every download is cached with a content hash, so after the first
sync the build runs fully offline. Run all commands from the repository root.

## Before you start

- Python 3.10 or later (standard library only for sync and build).
- Internet access for the first download only.
- Java for EPUBCheck validation: `python talmud/work/sync.py java` makes sure a Java
  runtime is available (reusing an unpacked copy from either segment, otherwise
  downloading and unpacking the pinned release into `talmud/work/tools/`, nothing
  installed). EPUBCheck 5.4.0 was used at the last run; `sync.py epubcheck` does
  the same for the EPUBCheck jar.

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
cache folder. (Oct 2026: 282 texts, 148 schemas, 0 failures. The three formerly
"missing" tractates use Sefaria's spelling — Taanit, Moed Katan, Meilah — and
fetch normally. Commentary downloads are English + Hebrew only.)

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

**6. Prebuild the on-device index (recommended)**

```powershell
dart run tool/build_study_index.dart talmud/outputs/books --out talmud/outputs/books/study
```

Writes one `<tractate>.study.sqlite` file into the `study` subfolder (the same
index the reader would otherwise build on first open, so opening on the Bigme
is instant). Copy the EPUBs plus the `study` folder onto the device:

- Device (Talmud): EPUBs at `/sdcard/books/3. nigleh/talmud/talmud w meforshim HE/`,
  sidecars in its `study/` subfolder.

Rebuild the sidecars whenever the EPUBs change; a stale sidecar is ignored
automatically. The reader also accepts a sidecar sitting next to its EPUB.

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
