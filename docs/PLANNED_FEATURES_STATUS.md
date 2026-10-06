# Planned-features status (Oct 2026 pass + 6 Oct fix pass)

Source: full `docs/` sweep. Items 1–21 from that sweep; this file records what
this pass built and what remains. Fixes below are code-complete and
host-tested 6 Oct; device rechecks still needed.

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
   annotations stay anchored, Talmud settings show Hidden/Shown. Device 6 Oct:
   no visible change on Talmud text (likely unpointed — inconclusive, recheck
   on a pointed Tanach verse).
3. **Paragraph-vs-continuous** — `ReaderSettings.studyContinuous`, persisted,
   projection/pagination keys include it, `mergeContinuousBlocks` joins
   consecutive body paragraphs (headings/amud boundaries stay), Talmud settings
   show Paragraphs/Continuous with the `Berakhot 2a:1` heading kept. Fix 6 Oct:
   single-span Talmud `segment-heading` divs are now parsed as headings (not
   paragraphs), merges break on direction/style change and chunk at 4000 chars
   / 200 runs, anchors remapped after merge. Root cause of the Berakhot
   Continuous crash (entire amud merged into one TextPainter). Needs HiBreak
   recheck; `adb logcat` still wanted if it recurs.
5. **Search respects selection + picker ordering** — SQLite v6 adds
   `base_search_text`/`commentary_search_text` (translations stay in base;
   only commentary asides split out); with no source selected only base is
   scanned, otherwise full text with exact projection filter. Picker order is
   Rashi/Rashbam/Mefaresh, Tosafot, then rest
   (`TanachLayoutService.orderedStudySources`), device-verified 6 Oct for the
   picker. Fix 6 Oct: projected reading order now sorts by the same rank, so
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
  multi-ranges.
- **Bidirectional selection handles:** built 6 Oct (either handle drags either
  direction with cross-flip, modern-phone style; 48 dp targets already
  device-verified grabbable). Needs HiBreak recheck.
- Picker grouping/search box for dozens of sources; auto-default to
  Rashi+Tosafot (left as opt-in); full per-source full-text index (current
  split is base vs all-commentary).
- **Commentary display order:** fixed 6 Oct in code (sort by
  `orderedStudySources` rank). Needs HiBreak recheck with multi-source reading.
- **Berakhot Continuous crash:** fixed 6 Oct in code (see item 3). Needs HiBreak
  recheck + `adb logcat` if it recurs, plus regression coverage in
  `test/reader/planned_features_test.dart`.
- **Tanach parsha/aliyah:** builder order fixed 6 Oct (Miketz before Vayigash/
  Vayechi; Leviticus restored to canonical Vayikra→Bechukotai; generator
  `derive_parshiyot.py` now sorts by start so it won't regress). Reader
  `_applyHeadingMode` now hides chapter `h1` whenever parsha/aliyah headings
  exist (was top-level `body h1` in dual chapters only). Rebuild EPUBs +
  sidecars, then recheck 5th-aliyah landing (want Gen 4:19), parsha-only
  headings, Chapters/Parshiyot exclusivity. Escaped markup (`span`/`class`/
  `nbsp`) still needs exact book/verse examples before builder-vs-reader call.
- **Tanach sidecars:** `tool/build_study_index.dart` verified 6 Oct on
  `18-obadiah.epub` (wrote 0.3 MB `.study.sqlite`); works for Tanach. Still
  need to build + copy all `<book>.study.sqlite` pairs after the parsha-order
  rebuild, verify fingerprints (Genesis cold 1m 45s → ~2s warm expected).
- Talmud scale-up: other 31 tractates; builder one-tractate-at-a-time +
  per-source indexing; source-discovery audit fixed 6 Oct in code
  (`inventory.py` checked commentary markers before the Talmud+Bavli base-text
  skip — was dropping most commentaries filed under Talmud/Bavli; do NOT rerun
  `inventory.py` over an edited `source-selection.json`, run `plan.py`/
  `sync` instead); big-tractate measurements (2 → ~5 → all) and EPUB-vs-SQLite gate; Bava Batra 29a slot,
  large-tractate splits, commentary budget, addressing verification;
  Yerushalmi/Mishnah-only/cross-refs/daf>amud nesting.
- Tanach tooling split + auto-checksum + Sefaria-change detection; EPUB
  page-list/publisher metadata.
- Bigme refresh bridge (needs documented API); renderer/timing/battery
  measurements; Item 6 logcat; browser-quirk repro; all device rechecks
  (48 dp handles, vowels, continuous, search, study books, tabs/layouts).
