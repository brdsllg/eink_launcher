# Planned-features status (Oct 2026 pass)

Source: full `docs/` sweep. Items 1–21 from that sweep; this file records what
this pass built and what remains.

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
   show Paragraphs/Continuous with the `Berakhot 2a:1` heading kept. Device
   6 Oct: Berakhot → Continuous **crashed the launcher** (open crash bug).
5. **Search respects selection + picker ordering** — SQLite v6 adds
   `base_search_text`/`commentary_search_text` (translations stay in base;
   only commentary asides split out); with no source selected only base is
   scanned, otherwise full text with exact projection filter. Picker order is
   Rashi/Rashbam/Mefaresh, Tosafot, then rest
   (`TanachLayoutService.orderedStudySources`), device-verified 6 Oct for the
   picker — but *reading* order still follows builder index order (open:
   sort projected notes by source rank). Picker grouping/search box for
   dozens of sources still to do. Old caches re-import automatically.
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
- **Bidirectional selection handles (new request 6 Oct, device-verified 48 dp
  targets grabbable):** either handle drags either direction, modern-phone
  style, replacing fixed forward/back roles.
- Picker grouping/search box for dozens of sources; auto-default to
  Rashi+Tosafot (left as opt-in); full per-source full-text index (current
  split is base vs all-commentary).
- **Commentary display order (device-verified 6 Oct):** picker order is
  Rashi → Tosafot → rest, but projected reading order follows builder
  index-link order (Steinsaltz before Tosafot). Sort appended notes by
  `orderedStudySources` rank.
- **Berakhot Continuous crash (device-verified 6 Oct):** switching to
  Continuous crashed the launcher. Needs logcat + regression test.
- **Tanach parsha/aliyah (device-verified 6 Oct):** Miketz-after-Vayechi order
  bug in `tanach/work/build.py`; aliyah landing mapping; chapter headings
  retained in parsha mode (`_applyHeadingMode` only strips top-level `h1`);
  escaped markup (`span`/`class`/`nbsp`) needing exact examples.
- **Tanach sidecars:** `tool/build_study_index.dart` works for any study EPUB
  but no Tanach sidecars were built; Genesis cold import is 1m 45s without
  one. Build + copy `<book>.study.sqlite` pairs, verify fingerprints.
- Talmud scale-up: other 31 tractates; builder one-tractate-at-a-time +
  per-source indexing; source-discovery audit (Finding F); big-tractate
  measurements (2 → ~5 → all) and EPUB-vs-SQLite gate; Bava Batra 29a slot,
  large-tractate splits, commentary budget, addressing verification;
  Yerushalmi/Mishnah-only/cross-refs/daf>amud nesting.
- Tanach tooling split + auto-checksum + Sefaria-change detection; EPUB
  page-list/publisher metadata.
- Bigme refresh bridge (needs documented API); renderer/timing/battery
  measurements; Item 6 logcat; browser-quirk repro; all device rechecks
  (48 dp handles, vowels, continuous, search, study books, tabs/layouts).
