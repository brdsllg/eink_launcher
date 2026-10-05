# Tanach EPUB project: current brief

Last updated 22 Sept 2026 (Hebrew-size amendment 28 Sept). Later decisions here
supersede earlier experiments. Read this before changing the project, and do not
re-ask settled preference questions.

## Goal and status

A personal-use Tanach EPUB collection from Sefaria: Hebrew, Orthodox Jewish English
translations, and a restricted whitelist of full direct commentaries. The content
pipeline stays independent of the reader. The Flutter reader now implements the
format described here, with a lazy SQLite import and search index; physical
validation on the Bigme remains.

- **Collection:** 39 books rebuilt 22 Sept 2026, in `outputs/books/`, packaged as
  `outputs/tanach-39-epubs.zip`. It holds 23,206 verses and 203,039 unique selected
  commentary notes, presented in 112,694 source/verse groups.
- **Format:** presentation revision 5, with Hebrew verse and Hebrew commentary text at
  1.1em.
- **Checks passed:** EPUBCheck 5.3.0, internal links and anchors (every verse-to-index
  and index-to-note link resolves), database invariants, heading checks, and
  grouped-note content preservation. The reader's all-book import, reopen, first/last
  chapter, and search test passed on 24 Sept.
- **Not established:** performance on the device for the largest books.

### Source limits (kept, not filled in)

- **Joshua 21:36–37** have Hebrew but no approved English, so those two verses are
  Hebrew-only.
- **1,645 Sefaria link records** point to places where no approved selected export has
  text. They are listed in `build-report.json`; nothing was invented. Compare this
  count after any future source rebuild.
- **Eleven verses** contain bracketed qere-only or traditional repeated-line material.
  The bracketed reading is kept as source text without square brackets. Ordinary and
  multiword qere/ketiv pairs show the pointed qere followed by the bracketed ketiv.
  The builder documents one exception, Ruth 3:12, which has a ketiv-only word with no
  pointed qere, and rejects unresolved qere placeholders.
- **Pending or unapproved editions** stay excluded. No Targum, and no unselected
  commentary groups.

## Settled content requirements

- **Books:** 39 divisions, not the traditional 24. The order is in
  `outputs/source-selection.json`.
- **Hebrew:** vowels, no cantillation; the qere (pointed, correct reading) first in the
  main text, then the bracketed ketiv (written form). Divine names as in the source.
- **English:** approved Orthodox Jewish translations. Per verse, prefer Metsudah and
  fall back to Koren. Never invent fallback text.
- **Commentary:** full text in Hebrew and any available approved English. Missing
  English never hides available Hebrew. Direct attachments only (including direct
  supercommentary through its parent Rashi comment): no Targum, no broad
  cross-citation expansion, no loosely related essays.
- **Navigation:** chapter-only contents; entirely offline; source credits and licenses
  at the end.
- **Licensing:** personal use. Edition and license data is preserved; personal use is
  not a blanket license decision.
- **Questions:** ask only about genuinely uncertain translation or modern-commentary
  provenance. Do not ask whether obviously Orthodox commentators such as Ramban are
  Orthodox.
- Earlier answers of "no / none" to questions no longer in the record must not be
  guessed at; consult the actual selection configuration.

### Commentary whitelist

Rashi; Ramban; Ibn Ezra; Sforno; Rashbam; Radak; Metzudat David; Metzudat Zion;
Malbim; Ralbag; Abarbanel; Or HaChaim; Ba'al HaTurim; Kitzur Ba'al HaTurim; Kli
Yakar; Chizkuni; Bartenura; Chatam Sofer; Jonathan Sacks (listed collections); Meiri;
Mizrachi; Rabbeinu Bahya; Siftei Chakhamim. Details, IDs, and exclusions are in
`outputs/commentary-whitelist.md`.

## Presentation (revision 5)

- **Page direction** is left-to-right (the book's `page-progression-direction`); Hebrew
  text blocks stay right-to-left. Never infer page-turn direction from the first
  language being Hebrew.
- No paragraph indentation and no inset commentary border.
- **Sizes:** English bodies 1em; Hebrew verse and Hebrew commentary 1.1em; verse
  heading 1.15em; note title 0.8em. Do not silently change body sizes.
- **Verse heading:** one compact bold line, "Verse 1" on the left and "פסוק א׳" on the
  right (Hebrew numerals such as ט״ו, ט״ז). It is a single `h2` with two independently
  directed spans, flex space-between, and a literal space between them. Earlier
  table-cell spans collapsed to the left in the reader, and a two-line heading was
  rejected. EPUB styling alone cannot guarantee the one-row layout, so a custom
  renderer must build a real horizontal row.
- **No edition labels** before or after verses (no "Ruth 3:1 · Koren" prefix or "The
  Koren Jerusalem Bible" suffix). Edition names belong in the translation selector;
  full credits go at the end.
- **Commentary:** one heading per source per verse (such as "Ibn Ezra on Ruth 3:1"),
  followed by separate paragraphs for each comment. Never repeat "…3:1:1", "…3:1:2"
  as visible headings; original references stay as metadata.

## Reader integration

The native reader:

1. Seeds its translation selector with the inline primary translation as a real named
   option (identity from `data-edition`, name from `data-translation-label`),
   defaulting to Metsudah where available and otherwise Koren, with no generic "Book
   default" option.
2. Adds alternate translations from each verse's note index and shows edition names
   only in the selector.
3. On switching, replaces only the alternate aside's direct English div (no navigation
   links or invented labels); switching back restores the original text.
4. Draws the bilingual verse heading as one row, English left and Hebrew right.
5. Shows each grouped commentary title once and keeps comment boundaries.
6. Rebuilds caches when files change, honors an explicit edition choice, and falls
   back to the verse's primary translation when that edition is unavailable.

Import, cache, and search behavior are described in `READER_PLAN.md` (study books).
The exact EPUB format is in `outputs/reader-compatibility.md`.

The latest presentation has **not yet been confirmed on the device**; do not claim the
selector, layout, or label problems are solved there.

## EPUB package limits (not blockers for the reader)

Each EPUB has one XHTML document per chapter, a stylesheet, package file and spine,
`nav.xhtml` (with the legacy `toc.ncx`), a title page, and final credits. It has no
page list for verse-level navigation and minimal package metadata: the "modified"
date is hard-coded to `2026-09-17T00:00:00Z`, and there is no publisher or rights
entry. These could matter for other readers or future distribution.

## Pipeline

Sefaria export discovery and selection → local cache → normalized SQLite → EPUB
generation → validation. Normalization and generation are separate, so presentation
changes use the existing database and need no network. Command reference: `README.md`;
plain-language rebuild guide: `REBUILD-EPUBS.md`.

`work/regenerate.py --book NAME` rebuilds one book and leaves `full-coverage.json`
unchanged. ZIP timestamps make EPUB checksums differ between rebuilds even when the
contents match; compare member contents, then run the packaging scripts to refresh
checksums.

Local runtime notes: PowerShell is the shell; set `PYTHONUTF8=1`. Known runtime paths
on this machine:

```text
C:/Users/levi/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
C:/Users/levi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe
```

For a presentation change: run `regenerate.py`, the heading and grouped-note checks,
`validate.py`, and `visual-check.cjs`; then `package_full.py` and
`package_samples.py` to refresh checksums, guides, and both ZIPs. The pipeline ZIP
alone cannot rebuild offline; keep `work/cache` and `work/tanach.sqlite`, or run the
acquisition and normalization steps again.

## Samples

Nine chapter samples (Genesis 1; Deuteronomy 32; I Samuel 17; Isaiah 40; Jonah 1;
Psalms 23; Job 1; Ruth 3; Daniel 2) cover 283 verses and 4,147 commentary notes in
1,749 groups. They were built 17 Sept and are **stale**: they predate the 22 Sept
rebuild and lack the current qere/ketiv markup. Use the full books in `outputs/books/`
for current testing. Default translations: Metsudah for Genesis 1, Deuteronomy 32,
I Samuel 17, and Ruth 3; Koren for Isaiah 40, Jonah 1, Psalms 23, Job 1, and Daniel 2.
Good device tests: Ruth 3 (qere/ketiv, Metsudah), Isaiah 40 (Koren fallback), Genesis
1 and Deuteronomy 32 (heavy commentary).

## Edition provenance queue

Some commentary translations are withheld until their provenance is clear; the named
commentators are still included through other editions. This is an edition-metadata
review, **not** a question about any commentator's standing. The queue (31 distinct
edition labels as of the 17 Sept sample guide) mostly consists of one-off translations
of Ibn Ezra, Ramban, Radak, Abarbanel, Malbim, and Rashi, plus a very large group
labeled "Sefaria Community Translation" (covering well over a hundred works) and a
few Wikisource and Matan editions. "Ramban Commentary" (a Judaica Press edition with
no exported text) was removed from the queue: Ramban is approved and already included
with Hebrew and English. Only a specific unresolved religious or editorial choice
should come back to Levi. The authoritative list is `outputs/source-selection.json`.

## Performance facts (host measurements, not the device)

- 929 chapter files total 325,739,412 bytes raw and 70,103,259 bytes at gzip level 6
  (4.65:1). Genesis 1: 3,006,495 bytes raw, 819,762 compressed. Decompressing every
  chapter took 1.5–3.4 s across two Windows runs; that excludes database access,
  parsing, projection, and drawing, so it is not a device estimate.
- Level 9 would save only 733,119 bytes (about 1%); keep level 6 unless the device
  shows a different bottleneck.
- The normalized `search_text` column and database overhead are still substantial.
- Cache identity: JSON keys include a full-file SHA-256, and the SQLite metadata checks
  it before reuse, so a content change under the same document ID triggers a
  re-import. The document ID itself is a SHA-1 of the first 64 KiB plus file size, so
  two different files with identical sampled bytes and size could share reading state;
  changing that scheme would need a state migration. Caches are disposable and
  device-local, Android may clear them under storage pressure, and a new device
  re-imports from the EPUBs.
- Commentary projection depends on the sorted commentary sources, commentary language,
  study translation, and publisher CSS. At most three chapters stay in memory with no
  speculative cache of source combinations; measure repeated switching on the device
  before adding one.

## Next work

1. Install the updated reader on the Bigme and test the largest books (Genesis,
   Exodus, Leviticus, Deuteronomy, Numbers, Psalms): cold import, warm reopen,
   pagination, memory pressure, search, and note navigation.
2. Have the owner check the latest formatting on the device before treating the
   presentation as final. Do not revert settled preferences while troubleshooting.
3. Revisit the source limits only if broader edition approval or a different text
   source is wanted.
4. **Build tooling (future):** `work/build.py` is one 450+ line script covering
   database reading, XHTML, packaging, credits, contents, and reporting. Possible
   improvements: split it into modules, automate checks that a rebuild matches
   expected content, and detect upstream Sefaria changes.

## Starting a new session

"Continue the Tanach EPUB project in the `tanach/` segment, starting from
`docs/tanach-epub.md`, `outputs/source-selection.json`, and
`outputs/reader-compatibility.md`. Inspect the existing files first. Preserve the
approved whitelist and revision 5 presentation. The deliverables are
`outputs/books/` (39 books), `outputs/samples/`, and `outputs/tanach-39-epubs.zip`.
Outstanding work is the Bigme check and any reader-side rendering follow-up. Do not
rebuild the whole collection or re-ask settled preference questions before
understanding the current state."
