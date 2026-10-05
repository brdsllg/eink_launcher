# Archived documentation

These files are the **earlier versions** of documents that have since been rewritten
and consolidated. They are kept for history and provenance only — **do not follow
their instructions or treat their status notes as current.** The current documents
live one level up in [`docs/`](../), and [`docs/tanach/`](../talmud/) /
[`docs/tanach/`](../tanach/) for the two EPUB-building segments.

Everything here was superseded on **5 October 2026**, when the documentation was
condensed into the single `docs/` tree.

## `root/` — the old repository-root documents

| Archived file | Superseded by | Note |
| --- | --- | --- |
| `README.md` | [`docs/README.md`](../README.md) | The old root readme mixed a personal note with a long release-by-release history |
| `READER_PLAN.md` | [`docs/READER_PLAN.md`](../READER_PLAN.md) | Condensed to decisions and current behaviour |
| `LAYOUT_DESIGN.md` | [`docs/LAYOUT_DESIGN.md`](../LAYOUT_DESIGN.md) | Condensed; dimensions kept, comparisons dropped |
| `BUTTON_SUPPORT.md` | [`docs/BUTTON_SUPPORT.md`](../BUTTON_SUPPORT.md) | Shortened to behaviour and accepted key pairs |
| `annotation_plan.md` | [`docs/annotation_plan.md`](../annotation_plan.md) | Rewritten as "Selection and annotations" |
| `ANDROID_HARDENING_PLAN.md` | [`docs/ANDROID_HARDENING_PLAN.md`](../ANDROID_HARDENING_PLAN.md) | Rewritten as "Android reliability" |
| `BIGME_TEST_LOG.md` | [`docs/DEVICE_TESTING.md`](../DEVICE_TESTING.md) | **Merged.** The 31 Aug manual pass and the PDF-001/002/003 findings are now one test history |
| `DEVICE_VALIDATION_2026-09-02.md` | [`docs/DEVICE_TESTING.md`](../DEVICE_TESTING.md) | **Merged.** The ADB results, memory table, and evidence limits are now in one place |
| `PDF_RESPONSIVENESS.md` | [`docs/READER_PLAN.md`](../READER_PLAN.md) ("Staying responsive") and [`docs/DEVICE_TESTING.md`](../DEVICE_TESTING.md) | **Merged.** Describes version 1.0.2, which is no longer current |

## `talmud/` — the old Talmud segment documents

| Archived file | Superseded by |
| --- | --- |
| `README.md` | [`docs/talmud/README.md`](../talmud/README.md) |
| `HOW-TO-SYNC.md` | [`docs/talmud/HOW-TO-SYNC.md`](../talmud/HOW-TO-SYNC.md) |
| `docs/talmud-epub-plan.md` | [`docs/talmud/docs/talmud-epub-plan.md`](../talmud/docs/talmud-epub-plan.md) |
| `docs/reader-device-findings.md` | [`docs/talmud/docs/reader-device-findings.md`](../talmud/docs/reader-device-findings.md) |

## `tanach/` — the old Tanach segment documents

| Archived file | Superseded by |
| --- | --- |
| `README.md` | [`docs/tanach/README.md`](../tanach/README.md) |
| `docs/tanach-epub.md` | [`docs/tanach/docs/tanach-epub.md`](../tanach/docs/tanach-epub.md) |
| `docs/REBUILD-EPUBS.md` | [`docs/tanach/docs/REBUILD-EPUBS.md`](../tanach/docs/REBUILD-EPUBS.md) |
| `work/legacy/README.md` | [`docs/tanach/work/legacy/README.md`](../tanach/work/legacy/README.md) |

## Deliberately **not** archived

The markdown files still sitting in `talmud/outputs/` and `tanach/outputs/` are
**live pipeline artifacts, not stale documentation**. The build scripts generate them
and read them back, so moving them would break the pipelines:

| File | Used by |
| --- | --- |
| `talmud/outputs/source-review.md` | written by `talmud/work/inventory.py` |
| `talmud/outputs/sample-guide.md` | written by `talmud/work/package_samples.py` |
| `tanach/outputs/reader-compatibility.md` | rewritten by `check_presentation.py`, `finalize_whitelist.py`, and the `work/legacy/` scripts; packed into ZIPs |
| `tanach/outputs/commentary-whitelist.md` | written by `make_whitelist.py`, rewritten by `finalize_whitelist.py` |
| `tanach/outputs/sample-guide.md`, `source-review.md`, `selected-commentaries.md`, `pipeline-readme.md` | written by `tanach/work/package_samples.py` and the `work/legacy/` scripts; packed into ZIPs |
| `tanach/outputs/FULL-BUILD-README.md` | read and packed into the 39-book ZIP by `tanach/work/package_full.py` |

Read-only summaries of these live in [`docs/talmud/outputs/`](../talmud/outputs/)
and [`docs/tanach/outputs/`](../tanach/outputs/); the `outputs/` copies stay
authoritative for the build.