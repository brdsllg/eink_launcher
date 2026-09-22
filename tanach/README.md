# Tanach EPUB segment

Self-contained, personal-use Tanach EPUB content pipeline and the collection it produces.
It is deliberately independent of the Flutter reader in `lib/`: the reader only consumes the
generated EPUBs, and nothing in this segment imports reader code.

This folder was previously `build/tanach_full/`. It was moved out of `build/` on 22 September
2026 because `flutter clean` deletes `build/`, and the pipeline holds the only copy of the
39-book collection, the normalized database, and the offline source cache.

## Layout

| Path | Purpose |
|---|---|
| `docs/tanach-epub.md` | Current handoff brief: settled content requirements, reader integration status, verification facts. Read this first. |
| `docs/archive/PROJECT-CONTEXT-2026-09-16.md` | Superseded 16 September brief. Kept for provenance only. |
| `work/` | Pipeline scripts, normalized database (`tanach.sqlite`), raw Sefaria cache, validation runtimes, browser preview. |
| `work/legacy/` | Historical one-shot migrations. Not part of the build; do not rerun (see `work/legacy/README.md`). |
| `outputs/books/` | 39 complete-book EPUBs, presentation revision 5. Canonical build output. |
| `outputs/samples/` | The nine chapter samples used for reader and presentation checks. |
| `outputs/tanach-39-epubs.zip` (+ `.sha256`) | Distributable full collection. |
| `outputs/tanach-samples.zip` | Distributable sample set. |
| `outputs/tanach-pipeline.zip` | Portable scripts plus configuration bundle (no cache, no database, no runtimes). |

Pipeline-generated documents live next to the data in `outputs/`, because the packaging
scripts read and rewrite them there: `reader-compatibility.md` (reader parser/rendering
contract), `sample-guide.md`, `source-review.md`, `selected-commentaries.md`,
`commentary-whitelist.md`, `pipeline-readme.md`, `FULL-BUILD-README.md`, the JSON reports
(`full-*`, `sample-*`, `build-report.json`, `validation-results.json`,
`reader-contract-facts.json`), and the two layout preview PNGs.

## Commands

Run these from this segment root (`cd tanach`) in PowerShell. `ROOT` is derived from the
script file location, so no configuration is needed:

```powershell
python -X utf8 work/regenerate.py            # redraw EPUBs from work/tanach.sqlite
python -X utf8 work/validate.py              # EPUBCheck 5.3.0 + structure/anchor checks over outputs/books
python -X utf8 work/package_full.py          # checksums + outputs/tanach-39-epubs.zip
python -X utf8 work/package_samples.py       # guides + outputs/tanach-samples.zip + tanach-pipeline.zip
```

`work/build.py`, `work/test_pipeline.py`, `work/check_heading_presentation.py`,
`work/check_grouped_notes.py`, and `work/visual-check.cjs` cover normalization, headings,
comment grouping, and browser rendering. `work/tools/` holds the extracted Java runtime and
EPUBCheck; `work/get_validation_tools.py` re-downloads them if they are missing.

## Reader-side integration checks

The reader tests locate this segment through environment variables:

```powershell
$env:TANACH_FULL_BOOKS_DIR = "$PWD\outputs\books"     # test/reader/tanach_full_sqlite_integration_test.dart
$env:TANACH_SAMPLES_DIR    = "$PWD\outputs\samples"   # test/reader/tanach_compatibility_test.dart
```

`flutter` must not be run as a bare foreground command on this machine; wrap it and read the
log, for example:

```powershell
cmd /c "cd /d C:\Users\levi\eink_launcher && flutter test test\reader\tanach_full_sqlite_integration_test.dart > out.txt 2>&1"
```

## Version control

The heavy data is git-ignored (see the root `.gitignore`):

- `/tanach/work/` — cache, database, runtimes, preview (about 1.9 GB).
- `/tanach/outputs/*` — books, samples, reports and ZIPs; the top-level `*.md` guides are
  re-included so the reader contract and guides stay reviewable.

## Cleanup log — 22 September 2026

- Moved `build/tanach_full/{work,outputs}` here and deleted the empty `build/tanach_full/`.
- Removed `outputs/tanach-39-epubs/` (46 files, 74.7 MB): a byte-identical extracted copy of
  `outputs/tanach-39-epubs.zip`.
- Renamed `outputs/tanach-samples/` to `outputs/samples/` and kept only the nine EPUBs; the
  five duplicated guides it carried were byte-identical copies of the files in `outputs/`.
  This also restores the path that `work/check_presentation.py`,
  `work/inspect_reader_contract.py`, and `work/finalize_whitelist.py` expect.
- Moved the superseded 16 September brief to `docs/archive/PROJECT-CONTEXT-2026-09-16.md`;
  `docs/tanach-epub.md` (18 September) supersedes it.
- Quarantined the historical one-shot scripts and the obsolete coverage snapshot in
  `work/legacy/`.
- Removed `work/__pycache__` and the downloaded `work/tools/{java,epubcheck}.zip` archives
  (83 MB); the extracted runtimes are untouched.
- Corrected the stale "not yet a full-39-book builder" text in `outputs/pipeline-readme.md`
  and in the readme embedded in `work/package_samples.py`.
