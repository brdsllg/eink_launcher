# Tanach EPUB project — conversation handoff

Last updated: 22 September 2026. This is a curated project brief and implementation handoff, not a verbatim transcript. Later decisions below supersede earlier experiments. Read this before changing the project; do not repeat settled preference questions.

## Goal and current status

Create a personal-use Tanach EPUB collection from Sefaria, with Hebrew, Orthodox Jewish English translations, and a restricted whitelist of full direct commentaries. Keep the content pipeline independent of the reader application. The Flutter reader in this repository now implements the Tanach contract and a lazy SQLite import/index cache; physical validation remains on the Bigme B751C.

The full 39-book collection was rebuilt on 22 September 2026 and lives in the `tanach/` segment of the reader repository, under `tanach/outputs/`. The distributable is `outputs/tanach-39-epubs.zip`; individual books are in `outputs/books/`. It contains 23,206 verses and 203,039 unique selected commentary notes. All 39 EPUBs passed EPUBCheck 5.3.0, internal link/anchor validation, database invariants, heading checks, and grouped-note content-preservation checks. The current format remains presentation revision 5, with commentary grouped by source and verse. These checks do not establish on-device performance in every large book.

Two source limitations were preserved rather than filled with invented text: Joshua 21:36–37 have no approved English translation and are Hebrew-only, and 1,645 Sefaria link-index records point to locations with no text in an approved selected export. The latter are retained in the full build report as unresolved pointers. Pending or unapproved editions remain excluded.

## Settled content requirements

- Use 39 book divisions, not the traditional merged count of 24. The precise order is in source-selection.json.
- Hebrew: vowels, no cantillation; the kri (pointed, correct reading) is rendered first in the main text, followed by the bracketed ketiv (written form). Preserve Divine names as in the source.
- English: include approved Orthodox Jewish translations. Prefer Metsudah for each verse; fall back to Koren when Metsudah is unavailable. Do not invent fallback text for missing content.
- Ask about genuinely uncertain translation or modern-commentary provenance. Do not ask whether obviously Orthodox commentators such as Ramban are Orthodox.
- Commentary: full text, Hebrew and available approved English. Missing English must not hide available Hebrew.
- No Targum. No broad cross-citation expansion or loosely related essays. Only direct commentary attachments, including direct supercommentary through its parent Rashi comment.
- Chapter-only table of contents. Entirely offline reading. Source attribution and license credits at the end.
- Personal use. Preserve edition/license metadata; personal use is not a blanket license determination.
- The user once replied “no / none of them / none” to questions not present in the retained conversation. Do not invent what those answers excluded; consult the actual selection configuration.

## Commentary whitelist — only these 23 groups

Rashi; Ramban; Ibn Ezra; Sforno; Rashbam; Radak; Metzudat David; Metzudat Zion; Malbim; Ralbag; Abarbanel; Or HaChaim; Ba'al HaTurim; Kitzur Ba'al HaTurim; Kli Yakar; Chizkuni; Bartenura; Chatam Sofer; Jonathan Sacks (the listed collections); Meiri; Mizrachi; Rabbeinu Bahya; Siftei Chakhamim.

Selected inventory IDs: C001, C002, C003, C004, C005, C006, C007, C008, C009, C011, C013, C014, C015, C016, C017, C019, C030, C035, C061, C076, C083, C098, C116. The explicit named additions included Or HaChaim and Siftei Chakhamim. Do not separately add Malbim Beur Hamilot or other unselected groups.

Jonathan Sacks remains eligible, but no direct qualifying notes were found for the sample passages. Do not include general essay citations merely to populate that source.

A previous review list misleadingly raised “Ramban Commentary” as a decision. Ramban itself was already approved; that separate export edition had empty content. Religious approval and the availability/provenance of a particular exported edition are distinct questions.

## Current presentation and user feedback

- Page progression must be left-to-right. Hebrew text blocks remain right-to-left. Do not infer page-turn direction from the first language being Hebrew.
- No paragraph indentation or inset commentary border.
- Main verse and commentary body text currently use equal 1em sizes. The latest request for a smaller “verse” was interpreted as the verse heading, following the discussion of the “Verse 1 / פסוק א׳” marker. Do not silently change all body text sizes.
- Each verse has one compact bold heading: “Verse 1” left, “פסוק א׳” right, on the SAME row. Current heading size is 1.15em. Hebrew numeral formatting includes ט״ו and ט״ז.
- Earlier side-by-side table-cell spans were concatenated on the left by the user's reader. An attempted two-line heading was also rejected. Revision 5 uses a single h2 with two independently directed spans, flex space-between, and a literal intervening space. A custom native renderer may need to explicitly create a horizontal row; EPUB CSS alone cannot guarantee it.
- Do not print translation edition labels before or after each verse. Remove prefixes such as “Ruth 3:1 · Koren” and suffixes such as “The Koren Jerusalem Bible.” Names belong in the translation selector; full credits belong at the end.
- Commentary should have ONE source/verse heading, e.g. “Ibn Ezra on Ruth 3:1”, followed by separate paragraphs for its comments. Do not repeat “Ibn Ezra on Ruth 3:1:1”, “...:2” as visible headings. Keep the original references as metadata.

## Reader integration status

The user reported that Ruth 3 offered “Book default”, Koren, and Silverstein. Switching to Koren correctly changed the translation, but also displayed a prefix and suffix label.

EPUB-side changes completed: removed alternate-translation note-title prefixes; shortened alternate data-source labels; added data-translation-label and data-primary to the default inline translation. Ruth 3:1 is explicitly marked Metsudah.

The native reader now:

1. Seeds its selector with the inline primary translation as a real named option, using data-edition as identity and data-translation-label as display name. It selects Metsudah by default where available, otherwise Koren, without adding a generic “Book default” option.
2. Adds alternate translations from the verse's note index and shows edition names only in the selector.
3. On switching, renders only the alternate aside's direct English content div, not the whole aside, navigation links, or synthesized attribution labels. Switching back restores the original inline translation.
4. Renders the bilingual verse heading as one row with English left and Hebrew right at the requested size.
5. Renders each grouped commentary title once and preserves comment-segment boundaries without synthesizing titles from individual segment references.
6. Rebuilds import/pagination caches when revised files change and respects explicit edition selection, with per-verse primary fallback when unavailable.

The reader fingerprints each recognized Tanach EPUB and imports its structured content into a disposable per-book SQLite database. Chapter XHTML is gzip-compressed, search uses normalized substring matching (`instr` on a Hebrew-mark-normalized text column) with visibility filters, chapters are projected lazily for the selected translation/commentaries, and at most three projected Tanach chapters remain resident. EPUB remains canonical; `library.json` continues to own positions, settings, bookmarks, and annotations. On 24 September, the current 22 September full rebuild passed the host import, warm reopen, first/last chapter load, and substring-search integration test for all 39 books in 2:43. Its cache databases totaled 208,474,112 bytes (198.8 MiB), below the 768 MiB ceiling. Set TANACH_FULL_BOOKS_DIR to rerun that test. These host checks do not replace physical Bigme performance validation.

Search is normalized substring matching through SQLite `instr(search_text, ?)`, followed by matching against the visible projected blocks. It is not FTS5 and deliberately accepts infixes. Hebrew vowel marks are removed for matching, so vowel-sensitive searches are not supported.

## Architecture and current EPUB contract

Pipeline: Sefaria export discovery/selection → local cache → normalized SQLite → EPUB generation → validation. Normalization and generation are separate; presentation-only revisions read existing SQLite and do not require network access.

Each EPUB has one XHTML resource per included chapter, a stylesheet, OPF/spine, EPUB navigation, NCX compatibility navigation, and final credits. Series metadata groups the samples. The current sample files each contain one selected chapter.

- section.verse has stable v-{book}-{chapter}-{verse} anchors and data-ref.
- .hebrew contains the prepared Hebrew source text.
- .translation contains default English, opaque data-edition, data-primary="true", and a short data-translation-label. It intentionally has no data-source attribute.
- The verse's “Notes & translations” link targets an index aside. Its links target alternate translations or grouped commentaries. Resolve actual hrefs and namespaces rather than guessing IDs.
- Alternate translation asides have epub:type="footnote", data-category="translation", short data-source, and data-edition. They have no visible note-title; their direct English div is the replacement text.
- Commentary asides have class commentary-note, a generated g- anchor, data-source, data-category, and verse-level data-ref. Their note-title occurs once.
- .note-he and .note-en contain separate .comment-segment blocks. Each segment retains original data-note-id, data-ref, data-editions, and full content. Missing languages are omitted.
- Grouping is by source and base verse. A comment attached to multiple verses can occur in multiple groups; deduplicating original IDs must not erase a group's content.
- .backlinks supply navigation. A custom reader may replace them with native Back behavior.
- Credits resolve edition IDs to full titles, source URLs and licenses.

Source switches and translation controls are app features, not executable EPUB behavior. A generic reader can follow the ordinary links to chapter-end asides. Large chapters need careful parsing and lazy note rendering on the Bigme; do not paginate all commentary into the main reading flow by accident.

## Samples and verification

The nine chapter samples (Genesis 1; Deuteronomy 32; I Samuel 17; Isaiah 40; Jonah 1; Psalms 23; Job 1; Ruth 3; Daniel 2) were last built on 17 September 2026 and reflect an earlier normalization pass. They are stale relative to the 22 September full-collection rebuild and do not contain the current qere/ketiv span markup. Use the full books in `outputs/books/` for current-state testing. The samples cover 283 verses and 4,147 original commentary notes, presented in 1,749 source/verse groups. There are 218 Siftei Chakhamim notes.

Latest checks on the full 39-book build verified every index noteref resolves (23,329 verse→index links, 114,443 index→note links, 0 broken), all verse sections have data-ref, all verse headings have exactly two language spans, translation labels are present, and comment segments and g- group asides are present in all 48 EPUBs. The reader's env-gated all-book integration test passed against the current build on 24 September 2026.

The latest presentation changes have not yet been confirmed by the user on the device. Do not claim the native selector, layout or suffix problem is solved there.

## Segment workspace and important files

This pipeline is its own segment of the reader repository: `tanach/`. It was previously
`build/tanach_full/`, which `flutter clean` deletes, and was originally developed in
`C:/Users/levi/Documents/Codex/2026-09-14/i-x20`. Paths below are relative to the `tanach/`
segment root.

| Path | Purpose |
|---|---|
| docs/tanach-epub.md | This brief. `docs/archive/` keeps the superseded 16 September version. |
| outputs/books/ | 39 complete-book EPUBs, revision 5; canonical build output. |
| outputs/samples/ | The nine chapter samples used for reader checks. |
| outputs/tanach-39-epubs.zip (+ .sha256) | Distributable full collection. |
| outputs/tanach-samples.zip | Sample bundle. |
| outputs/tanach-pipeline.zip | Portable scripts/configuration bundle; not the raw cache, SQLite database, validation runtimes, or reader app. |
| outputs/source-selection.json | Authoritative detailed source/edition selection and preferences. |
| outputs/selected-commentaries.md | Human-readable whitelist. |
| outputs/reader-compatibility.md | Reader parser/rendering contract and revision 5 integration notes. |
| outputs/source-review.md | Edition/provenance review queue. Latest sample packaging reports 31 pending commentary edition titles. |
| outputs/sample-guide.md | Sample use guide. |
| outputs/sample-coverage.json | Per-sample counts and coverage. |
| outputs/validation-results.json, outputs/full-validation-results.json | Sample and full-collection validation results. |
| outputs/sample-checksums.json, outputs/full-checksums.json | Sample and full-collection EPUB checksums. |
| outputs/build-report.json | Normalization/attachment diagnostics, including unresolved items. |
| outputs/verse-layout-preview.png | Latest browser verse preview. |
| outputs/commentary-layout-preview.png | Latest browser commentary preview. |
| work/tanach.sqlite | Normalized build database. |
| work/build.py | Normalizer and current EPUB generator/CSS. |
| work/regenerate.py | Rebuild EPUB presentation from the existing SQLite database. |
| work/sync.py, work/plan.py, work/inventory.py | Source discovery, download planning and cache population. |
| work/validate.py | EPUBCheck plus structure/anchor validation. |
| work/test_pipeline.py | Normalization and attachment checks. |
| work/check_heading_presentation.py | Current heading and translation-label checks. |
| work/check_grouped_notes.py | Content-preservation and commentary grouping checks. |
| work/visual-check.cjs | Browser screenshot and navigation checks. |
| work/package_full.py | Checksums and the 39-book distribution ZIP. |
| work/package_samples.py | Regenerates guides, metadata packaging and distribution ZIPs. |
| work/finalize_whitelist.py | Refreshes measured reader-contract facts and some documentation. |
| work/legacy/ | Historical one-shot migrations: revise_*, refine_*, apply_whitelist.py, document_grouped_format.py, update_heading_presentation.py, plus an obsolete coverage snapshot. Not a build sequence; do not rerun them blindly, because some overwrite current preferences or duplicate edits. Make future changes directly to the current generator/config/docs. |

A cleanup on 22 September 2026 deleted the extracted duplicate folder `outputs/tanach-39-epubs/` (byte-identical to the distribution ZIP) and the duplicated guide copies inside the old `outputs/tanach-samples/` folder, which is now `outputs/samples/`.

## Local execution notes

PowerShell is the shell; run the commands from the `tanach/` segment root (`cd tanach`). Set PYTHONUTF8=1 for Unicode output. The scripts derive their root from their own file location, so no path configuration is needed. Known bundled runtime paths on this machine:

```text
C:/Users/levi/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
C:/Users/levi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe
```

For presentation changes, run work/regenerate.py, the relevant presentation checks, work/validate.py, and work/visual-check.cjs. After successful validation and documentation updates, run work/package_full.py and work/package_samples.py to refresh checksums, the guides, and both distribution ZIPs. The Java runtime and EPUBCheck 5.3.0 are extracted under work/tools (the downloaded archives were removed on 22 September 2026; work/get_validation_tools.py re-downloads them if needed). New environments may need to install or locate their own dependencies.

Do not assume the pipeline ZIP alone reproduces the build offline: retain work/cache and work/tanach.sqlite, or run the documented acquisition/normalization pipeline to recreate them. Keep deliverables under outputs.

## Next work

1. Install the updated reader on the Bigme and test the largest full books, especially Genesis, Exodus, Leviticus, Deuteronomy, Numbers, and Psalms; measure cold import, warm reopen, pagination, memory pressure, FTS search, and note navigation.
2. Let the user check the latest formatting on-device before treating the presentation as final. Do not revert settled preferences during troubleshooting.
3. Review the explicitly reported source limitations only if broader edition approval or a different textual source is desired. Do not invent replacements for missing source text.

Work autonomously on authorized changes, preserve full source text, and explain clearly which fixes belong in the EPUB versus the reader. Ask concise questions when a real content/provenance decision or missing reader location is needed; do not re-open obvious Orthodox-source approvals.

## Open items tracked in this doc

Host compression audit (`python work/audit_chapter_compression.py --level 6`) of the current 39 EPUBs: 929 chapter XHTML files total 325,739,412 bytes raw and 70,103,259 bytes in level-6 gzip (4.65:1). Genesis 1 is 3,006,495 bytes raw and 819,762 bytes compressed. Decompression alone took 1.5–3.4 seconds across all chapters in two Windows runs under different host load; this excludes SQLite I/O, HTML parsing, projection, and device rendering, so it is not a Bigme load-time estimate. The uncompressed normalized `search_text` column and SQLite overhead remain substantial; measure on-device open latency and peak memory before changing the format.
Level-9 gzip reduced the same chapters to 69,370,140 bytes, saving only 733,119 bytes (about 1% of the compressed XHTML) against level 6. Raising the gzip level is unlikely to change total cache pressure enough to justify a format change.

The projection depends on sorted commentary sources, commentary language, study translation, and publisher CSS. The reader now keeps loaded Tanach chapter blocks when only typography changes; changes to those four projection inputs still re-project the current chapter. At most three chapters remain resident, and there is no speculative cache of source combinations. Measure repeated switching on the Bigme before adding another memory cache.

Cache review: the app checks the Tanach SQLite database before the JSON parse cache. A current SQLite hit returns immediately. A legacy JSON hit can seed SQLite if the database is missing or stale; newly parsed Tanach books are not written to JSON. Ordinary EPUBs continue to use JSON. The SQLite cache stores compressed XHTML and normalized search text; projected chapters live in session memory. The app places its Tanach database directory beneath the parsed-cache directory, but the JSON eviction pass only counts `.json` files. The separate 64 MiB and 768 MiB limits therefore serve different data, and normal Tanach opens do not duplicate a full parsed book on disk.

Pipeline maintenance: `work/regenerate.py --book NAME` now rebuilds one book from the normalized database and leaves `full-coverage.json` unchanged. The generator remains one large script. ZIP member timestamps make raw EPUB checksums vary across rebuilds even when all contents match; compare member contents for an equivalence check, then run the packaging scripts to refresh distribution checksums after accepting a rebuild. Detecting upstream Sefaria source changes and splitting the generator remain future maintenance work.

Cache identity: JSON keys include a full-file SHA-256 fingerprint, and the SQLite database path uses the document ID but its metadata checks the full-file fingerprint before reuse. Thus a same-ID content change triggers re-import rather than returning stale chapters. The document ID itself is SHA-1 of the first 64 KiB plus file size; two files with identical sampled bytes and size can still share reading state, so changing that identity scheme would require a state migration. Caches are disposable and device-local; Android may clear the cache directory under storage pressure, and new devices must import from the EPUBs.

## Suggested opening instruction for a new project

“Continue this Tanach EPUB project in the `tanach/` segment of the reader repository, starting from `tanach/docs/tanach-epub.md`, `tanach/outputs/source-selection.json`, and `tanach/outputs/reader-compatibility.md`. Inspect the existing files first. Preserve the approved whitelist and revision 5 presentation. The current deliverables are `tanach/outputs/books/` (39 books), `tanach/outputs/samples/` (nine samples), and `tanach/outputs/tanach-39-epubs.zip`. Outstanding work is the on-device check on the Bigme plus any reader-side rendering follow-up. Do not rebuild the full collection or repeat settled preference questions before understanding the current state.”
