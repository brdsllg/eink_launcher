# Tanach EPUB segment

A self-contained, personal-use pipeline that builds a 39-book Tanach EPUB collection
from Sefaria, plus the collection it produces. It is independent of the Flutter
reader in `lib/`: the reader only consumes the finished EPUBs, and nothing here
imports reader code.

The segment lives at `tanach/` (formerly `build/tanach_full/`) because `flutter clean`
deletes `build/`, and this folder holds the only copy of the collection, the
normalized database, and the offline source cache.

## Layout

| Path | Purpose |
|---|---|
| `docs/tanach/docs/tanach-epub.md` | **Read first.** Current brief: settled requirements, reader status, source limits, verification facts |
| `docs/tanach/docs/REBUILD-EPUBS.md` | Plain-language guide to rebuilding the books |
| `docs/tanach/work/legacy/README.md` | What the historical one-off scripts did, and why not to rerun them |
| `docs/archived/` | The earlier versions of these documents, kept for history only |
| `work/` | Pipeline scripts, normalized database (`tanach.sqlite`), raw Sefaria cache, validation tools, browser preview |
| `work/legacy/` | One-off past migrations. Not part of the build; do not rerun (see `docs/tanach/work/legacy/README.md`) |
| `outputs/books/` | The 39 complete-book EPUBs, presentation revision 5 (canonical output) |
| `outputs/samples/` | Nine chapter samples for reader and presentation checks |
| `outputs/tanach-39-epubs.zip` (+ `.sha256`) | Distributable full collection |
| `outputs/tanach-samples.zip` | Distributable sample set |
| `outputs/tanach-pipeline.zip` | Portable scripts and configuration (no cache, database, or tools) |

The human-readable documents live in `docs/tanach/`; this folder keeps only the
scripts, the generated books, and the markdown the pipeline rewrites itself.

Documents and reports that the packaging scripts rewrite live next to the data in
`outputs/`: `reader-compatibility.md`, `commentary-whitelist.md`, `sample-guide.md`,
the JSON reports (`full-*`, `sample-*`, `build-report.json`, `validation-results.json`,
`reader-contract-facts.json`), `source-selection.json`, and two layout preview images.

## Commands

Run from this folder (`cd tanach`) in PowerShell. Paths are worked out from each
script's own location, so nothing needs configuring.

```powershell
python -X utf8 work/regenerate.py                  # redraw EPUBs from work/tanach.sqlite
python -X utf8 work/regenerate.py --book Obadiah   # rebuild one book as a trial
python -X utf8 work/build.py                       # refresh the database from the cache, then redraw
python -X utf8 work/validate.py                    # EPUBCheck + structure and link checks on outputs/books
python -X utf8 work/package_full.py                # checksums + outputs/tanach-39-epubs.zip
python -X utf8 work/package_samples.py             # guides + sample and pipeline ZIPs
python -X utf8 work/audit_chapter_compression.py --level 6   # measure chapter compression
```

For a plain-language walk-through, see
[docs/REBUILD-EPUBS.md](docs/REBUILD-EPUBS.md).

Other tools:

- `work/derive_parshiyot.py` builds the weekly-portion table the five Torah books
  embed. It reads Hebcal's public API once (cached in `work/cache/leyning/`), checks
  the seven aliyah boundaries against the database, and rewrites the `PARSHIYOT` block
  in `work/build.py`. `--check` verifies without rewriting; the build itself never
  uses the network.
- Checks: `work/test_pipeline.py`, `work/check_heading_presentation.py`,
  `work/check_grouped_notes.py`, and `work/visual-check.cjs` (browser rendering).
- `work/tools/` holds the Java runtime and EPUBCheck; `work/get_validation_tools.py`
  re-downloads them if missing.

### Starting in a fresh workspace

Keep `outputs/source-selection.json`, then:

```powershell
python -X utf8 work/sync.py catalog
python -X utf8 work/sync.py inspect
python -X utf8 work/sync.py schemas
python -X utf8 work/plan.py
python -X utf8 work/sync.py texts
python -X utf8 work/sync.py links
python -X utf8 work/build.py
```

Downloads are pinned and checksummed; failures are recorded in `work/cache/`. **Do not
run `inventory.py` over an edited `source-selection.json`:** it is the first-time
discovery script and regenerates that file. After changing the selection, run
`plan.py`, `sync.py texts`, and `build.py`. Editions with unclear provenance stay
"pending" and are not downloaded.

## Reader-side checks

The reader's tests find this segment through environment variables:

```powershell
$env:TANACH_FULL_BOOKS_DIR = "$PWD\outputs\books"     # test/reader/tanach_full_sqlite_integration_test.dart
$env:TANACH_SAMPLES_DIR    = "$PWD\outputs\samples"   # test/reader/tanach_compatibility_test.dart
```

On this machine `flutter` must not be run as a bare foreground command. Wrap it and
read the log:

```powershell
cmd /c "cd /d C:\Users\levi\eink_launcher && flutter test test\reader\tanach_full_sqlite_integration_test.dart > out.txt 2>&1"
```

## Syncing across machines

**Pipeline sources and settings: normal git.** Tracked (see the root `.gitignore`):
`work/*.py`, `work/*.cjs`, `work/legacy/**`, the `tanach/README.md` pointer, the
`outputs/*.md` guides, and `outputs/source-selection.json`. The written documents live
in `docs/tanach/` (also tracked, outside this folder). A `git clone` or `git pull`
gives a working pipeline; the other machine needs Python 3.11+ for offline steps and
can fetch Java and EPUBCheck with `work/get_validation_tools.py`.

**Raw data and generated files: never git** (about 2 GB, ignored): `work/cache/`
(about 1.1 GB), `work/tanach.sqlite` (323 MB), `work/tools/`, `work/preview/`,
`work/validation/`, and everything in `outputs/` except the markdown guides and the
manifest (`books/` is 67 MB; also `samples/`, the ZIPs, the JSON reports, and previews).

Choose one route for the generated files:

| Route | Steps | Notes |
|---|---|---|
| Direct file copy | Copy `outputs/`, plus `work/cache/` and `work/tanach.sqlite` if the other machine should rebuild offline | Simplest; nothing is published |
| GitHub Release assets | `git tag tanach-v5-2026-09-17`, `git push origin --tags`, attach `tanach-39-epubs.zip`, its `.sha256`, and `tanach-pipeline.zip` in the web UI | Keeps binaries out of history; verify with `Get-FileHash` |
| Git LFS on a **private** remote | `git lfs install`, add `outputs/*.zip` and `outputs/books/*.epub` to `.gitattributes`, commit and push | A plain clone brings the EPUBs. GitHub's free allowance is 1 GB storage and 1 GB/month; each rebuild re-uploads about 70 MB |
| Regenerate locally | Copy `work/cache/` and `work/tanach.sqlite`, then run `work/regenerate.py` | The pipeline alone cannot rebuild offline; the cache must be copied regardless |

The device is not a git target. Send books over ADB, for example
`adb push tanach/outputs/books/. /sdcard/Download/Tanach/`.

> **Licensing guard rail:** the repository is public, and the collection is
> personal-use, Sefaria-derived content with per-edition licenses. Never publish the
> EPUBs, the commentary text, or the ZIPs to the public repository or its releases.
> Use a private LFS remote or a direct file copy.

Useful checks before committing:

```powershell
git status --ignored=matching -- tanach   # exactly what is local-only
git add -A --dry-run -- tanach            # exactly what a commit would include
```
