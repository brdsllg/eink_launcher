# Tanach EPUB segment

> New here, or just want to know how to back this up and move it between computers?
> Read [`HOW-TO-SYNC.md`](HOW-TO-SYNC.md) first — it is written in plain language.

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

## Syncing across machines

The segment splits into two payloads that need two different mechanisms.

**Pipeline sources and configuration — normal git.** These are tracked (see the root
`.gitignore`): `work/*.py`, `work/*.cjs`, `work/legacy/**`, `docs/**`, `README.md`, the
`outputs/*.md` guides, and `outputs/source-selection.json` (the authoritative selection
manifest). A `git clone` or `git pull` therefore gives a working pipeline; the other machine
only needs Python 3.11+ for the offline steps and can fetch Java/EPUBCheck with
`work/get_validation_tools.py`.

**Raw data and generated payload — never git.** `work/cache/` (about 1.1 GB),
`work/tanach.sqlite` (323 MB), `work/tools/` runtimes, `work/preview/`, `work/validation/`,
and everything in `outputs/` except the markdown guides and the manifest: `books/` (67 MB),
`samples/`, the ZIPs, JSON reports, and PNG previews.

Choose one route for the payload:

| Route | Steps | Notes |
|---|---|---|
| Direct file copy | Copy `tanach/outputs/`, plus `work/cache/` and `work/tanach.sqlite` if the other machine should rebuild offline. | Simplest. Nothing is published. |
| GitHub Release assets | `git tag tanach-v5-2026-09-17`, `git push origin --tags`, then attach `outputs/tanach-39-epubs.zip`, its `.sha256`, and `outputs/tanach-pipeline.zip` to that release in the web UI. | Keeps binaries out of history; verify with `Get-FileHash` against the `.sha256`. |
| Git LFS on a **private** remote | `git lfs install`, add `outputs/*.zip` and `outputs/books/*.epub` to a `.gitattributes`, then commit and push. | A plain `git clone` then brings the EPUBs. GitHub's free allowance is 1 GB storage and 1 GB/month bandwidth, and every rebuild re-uploads about 70 MB. |
| Regenerate locally | Copy `work/cache/` plus `work/tanach.sqlite` to the second machine, then run `work/regenerate.py`. | The pipeline alone cannot rebuild offline; the cache has to be copied regardless. |

The device is not a git target — send the books to the reader over ADB, for example
`adb push tanach/outputs/books/. /sdcard/Download/Tanach/`.

> **Licensing guard rail:** this repository is public, and the collection is personal-use
> Sefaria-derived content with per-edition licences. Do not publish the EPUBs, the commentary
> text, or the ZIPs to the public repository or its releases. Use a private LFS remote or a
> direct file copy for the generated payload.

Useful checks before committing:

```powershell
git status --ignored=matching -- tanach     # see exactly what is local-only
git add -A --dry-run -- tanach              # see exactly what a commit would include
```

## Version control

- Tracked: `tanach/README.md`, `docs/**`, pipeline sources (`work/*.py`, `work/*.cjs`,
  `work/legacy/**`), the `outputs/*.md` guides, and `outputs/source-selection.json`.
- Local-only (git-ignored, about 2 GB): `work/cache/`, `work/tanach.sqlite`, `work/tools/`,
  `work/preview/`, `work/validation/`, `outputs/books/`, `outputs/samples/`, the ZIPs, JSON
  reports, and PNG previews.

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
