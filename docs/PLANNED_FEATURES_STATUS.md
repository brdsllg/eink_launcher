# Planned-features status

Current status: this file records what is built and what remains. Fixes below
are code-complete and host-tested; device rechecks are noted per item.

## Built in this pass

1. **Multi-paragraph selection** — `Annotation` now carries an optional end block
   (`endBlockIndex/Id/DocumentPath/Offset`), `matchesBlock`/`rangeForBlock`
   cover start/middle/end blocks, painting and tap targets underline every
   covered paragraph, and the toolbar **More** button extends the current
   selection through the next readable paragraph. Drag across blocks, cross-
   chapter ranges, and multi-block Copy/Dictionary are still single-block.
   Tests: `test/reader/planned_features_test.dart`, existing annotation tests.
2. **Hide vowel points** — `ReaderSettings.hideVowelPoints` (+
   `StudyProjectionSettings`), persisted JSON, pagination v8 and projection keys
   include it, display strips U+0591–05C7 with source-offset mapping so
   annotations stay anchored, Talmud settings show Hidden/Shown. On device the
   toggle shows no change on Talmud text (likely unpointed — inconclusive);
   recheck on a pointed Tanach verse before calling it a bug.
3. **Paragraph-vs-continuous** — `ReaderSettings.studyContinuous`, persisted,
   projection/pagination keys include it, `mergeContinuousBlocks` joins
   consecutive body paragraphs (headings/amud boundaries stay), Talmud settings
   show Paragraphs/Continuous with the `Berakhot 2a:1` heading kept. Single-span Talmud `segment-heading` divs are
   parsed as headings (not paragraphs), merges break on direction/style change
   and chunk at 4000 chars / 200 runs, anchors remapped after merge — this was
   the root cause of the Berakhot Continuous crash (entire amud merged into one
   TextPainter). Continuous no longer crashes but visibly does nothing; open
   decision below (owner suggests removing the setting).
5. **Search respects selection + picker ordering** — SQLite v6 adds
   `base_search_text`/`commentary_search_text` (translations stay in base;
   only commentary asides split out); with no source selected only base is
   scanned, otherwise full text with exact projection filter. Picker order is
   Rashi/Rashbam/Mefaresh, Tosafot, then rest
   (`TanachLayoutService.orderedStudySources`); the picker order is verified on
   device and the projected reading order sorts by the same rank, so
   Rashi → Tosafot → rest in the text (was builder index-link order with
   Steinsaltz before Tosafot). Picker grouping/search box for
   dozens of sources still to do. Old caches re-import automatically.
   Vowel range unified to U+0591–05C7 everywhere (was missing 05BE/05C0/05C3/
   05C6 in paginator/search/cache).
6. **Docs: removed `READER_PLAN.md` Tabs “Out of scope” line** — close-others,
   reopen-last-closed, always-visible wide tab bar no longer listed as
   out-of-scope (feature work itself not built).
13. **Builder back-links removed** — `talmud/work/build.py` and
   `tanach/work/build.py` no longer emit `<p class="backlinks">` (reader
   already stripped them at display). Regenerate books to take effect; old
   EPUBs still open (reader strips).

## Not yet built/fixed (still open)

- Direct drag-across-blocks gesture; multi-block Copy/Dictionary; cross-chapter
  multi-ranges. Owner correction: the **More** button as built
  ("underline the rest of this paragraph") is not what was asked — it should
  let the *selection* extend across multiple paragraphs, then apply
  Copy/Dictionary/Note/Underline to the whole range.
- **Bidirectional selection handles (open):** either handle drags either
  direction with cross-flip, modern-phone style; 48 dp targets grabbable on
  device. Retest findings: flipping jumps the stationary handle a few
  letters/word; Hebrew handles pull each other before flipping; mixed
  Hebrew + English in one paragraph behaves strangely.
- Picker grouping/search box for dozens of sources; auto-default to
  Rashi+Tosafot (left as opt-in); full per-source full-text index (current
  split is base vs all-commentary).
- **Commentary display order (open — fixed in code):** projected reading order
  sorts by `orderedStudySources` rank. Needs device recheck with multi-source
  reading.
- **Berakhot Continuous (open decision):** crash fixed (see item 3) but the mode
  visibly does nothing; owner suggests removing the Paragraphs/Continuous
  setting. Open decision: keep/fix vs remove.
- **Tanach parsha/aliyah (done — verified on device):** parsha order
  (Miketz before Vayigash/Vayechi; Leviticus Vayikra→Bechukotai;
  `derive_parshiyot.py` sorts by start), reader `_applyHeadingMode` hides
  chapter `h1` whenever parsha/aliyah headings exist, 5th-aliyah landing
  (Gen 4:19), parsha-only headings, Chapters/Parshiyot exclusivity.
- **Tanach markup words (open — fixed in source, needs rebuilt books):**
  `span`/`class`/`nbsp` words visible in Hebrew verses (`span` search returns
  **202 matches** in Genesis, all books affected). `hebrew()` in
  `tanach/work/build.py` escaped raw source markup; now strips to clean text
  (section markers kept), host-verified over 23,206 verses. Rebuild EPUBs +
  sidecars, then recheck verses clean and `span` search 0.
- **Tanach sidecars (separate `study` subfolder):** the reader checks
  `<books-dir>/study/<book>.study.sqlite` first and falls back to a sidecar
  next to its EPUB. Build with
  `dart run tool/build_study_index.dart <books-dir> --out <books-dir>/study`.
  Device (Tanach): EPUBs at
  `/sdcard/books/3. nigleh/tanach/tanach w meforshim HE/`, sidecars in its
  `study/` subfolder. Genesis cold import 1m 45s → ~2s warm expected once the
  sidecar matches.
- Talmud scale-up: other 31 tractates; builder one-tractate-at-a-time +
  per-source indexing; source-discovery audit fixed in code
  (`inventory.py` checked commentary markers before the Talmud+Bavli base-text
  skip — was dropping most commentaries filed under Talmud/Bavli; do NOT rerun
  `inventory.py` over an edited `source-selection.json`, run `plan.py`/
  `sync` instead); big-tractate measurements (2 → ~5 → all) and EPUB-vs-SQLite gate; Bava Batra 29a slot,
  large-tractate splits, commentary budget, addressing verification;
  Yerushalmi/Mishnah-only/cross-refs/daf>amud nesting.
- Tanach tooling split + auto-checksum + Sefaria-change detection; EPUB
  page-list/publisher metadata.
- Bigme refresh bridge (needs documented API); renderer/timing/battery
  measurements; Item 6 logcat; browser-quirk repro; remaining device rechecks
  (selection fixes, vowels on Tanach, study books). Tabs/layouts skipped per
  owner — already tested several times.
