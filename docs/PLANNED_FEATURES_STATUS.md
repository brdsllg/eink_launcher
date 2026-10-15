# Planned-features status (Oct 2026 pass + 6 Oct fix pass)

Developer-facing build log. It says what was **built in code** and what is still to
build. It does **not** say whether something works on the device: that lives only in
the issue tracker in [DEVICE_TESTING.md](DEVICE_TESTING.md), and this file refers to
its IDs (SEL-003, TAN-002, and so on) instead of repeating status words.

Source: full `docs/` sweep. Items 1–21 from that sweep. Everything under "Built"
passes the computer tests (host-tested 6 Oct, plus 11 Oct vowel/markup/sidecar
fixes below); none of it counts as fixed until the tracker says so.

## Built

1. **Multi-paragraph selection** (tracker: SEL-002). `Annotation` carries an optional
   end block (`endBlockIndex/Id/DocumentPath/Offset`), `matchesBlock`/`rangeForBlock`
   cover start/middle/end blocks, painting and tap targets underline every covered
   paragraph, and the toolbar **More** button extends the current selection through
   the next readable paragraph (repeatable, 11 Oct rebuild): the start paragraph
   highlights to its end, every covered following paragraph highlights in full, and
   Copy/Note/Underline apply to the combined range (Dictionary stays word-based).
   Not built: drag across blocks, cross-chapter ranges (these stay single-block;
   needs a cross-widget gesture/layout rewrite; More-chain is the pattern). The
   owner reports **More** does not behave as wanted; the older notes also described
   it as "underline the rest of the paragraph", so check the source for what it
   really does before reworking. Tests: `test/reader/planned_features_test.dart`,
   existing annotation tests.
2. **Hide vowel points** (tracker: TAL-013). `ReaderSettings.hideVowelPoints` (+
   `StudyProjectionSettings`), persisted JSON, pagination v8 and projection keys
   include it, display strips U+0591–05C7 with source-offset mapping so annotations
   stay anchored, Talmud settings show Hidden/Shown. The vowel range is the same
   U+0591–05C7 everywhere (it was missing 05BE/05C0/05C3/05C6 in the paginator,
   search and cache). On the device the setting showed no change on Talmud text
   because the pipeline picked Sefaria's unpointed Aramaic edition — fixed 11 Oct:
   inventory prefers Vocalized Aramaic, download-plan swapped for all 37, Berakhot
   cache verified (227k marks, 0 cantillation). Rebuild EPUBs + sidecars, then
   recheck the toggle on Berakhot 2a.
3. **Paragraph-vs-continuous** (tracker: TAL-011, TAL-012).
   `ReaderSettings.studyContinuous`, persisted, projection/pagination keys include
   it, `mergeContinuousBlocks` joins consecutive body paragraphs (headings and amud
   boundaries stay). Fix 6 Oct for the crash: single-span Talmud `segment-heading`
   divs are now parsed as headings, merges break on direction/style change and
   chunk at 4000 chars / 200 runs, anchors are remapped after merge. Root cause of
   the Berakhot crash: the entire amud was merged into one `TextPainter`. Owner
   decision (6 Oct 2026): remove the setting, so this item is to be removed, not
   extended.
5. **Search respects selection, and picker ordering** (tracker: TAL-010). SQLite v6
   adds `base_search_text`/`commentary_search_text` (translations stay in base; only
   commentary asides split out). With no source selected only base is scanned;
   otherwise full text with the exact projection filter. Picker order is
   Rashi/Rashbam/Mefaresh, Tosafot, then the rest
   (`TanachLayoutService.orderedStudySources`). Projected reading order now sorts by
   the same rank (it used builder index-link order, which put Steinsaltz before
   Tosafot). Old caches re-import automatically.
6. **Docs:** removed the `READER_PLAN.md` Tabs "Out of scope" line. Close-others,
   reopen-last-closed and an always-visible wide tab bar are no longer listed as out
   of scope (the feature work itself is not built).
13. **Builder back-links removed.** `talmud/work/build.py` and `tanach/work/build.py`
    no longer emit `<p class="backlinks">` (the reader already stripped them at
    display). Regenerate books to take effect; old EPUBs still open.

Also built, outside the sweep's numbering:

- **Bidirectional selection handles** (tracker: SEL-001, SEL-003, SEL-004,
    SEL-005). Either handle drags either direction with a cross-flip, modern-phone
    style. The 48 dp touch targets work; the flip behavior still has the problems
    listed in SEL-003 to SEL-005.
- **Tanach parsha/aliyah fixes** (tracker: TAN-001, TAN-002, TAN-003).
    - Builder order: Miketz now before Vayigash/Vayechi; Leviticus restored to the
      canonical Vayikra to Bechukotai order; the generator `derive_parshiyot.py` now
      sorts by start so it will not regress.
    - Reader: `_applyHeadingMode` now hides chapter `h1` whenever parsha/aliyah
      headings exist (it only removed top-level `body h1` in dual chapters before).
    - Reader (5 Oct): aliyah anchors resolve after the lazy chapter loads. This did
      not cure TAN-001 on the 6 Oct pass.
- **Tanach sidecar tool** (tracker: TAN-005). `tool/build_study_index.dart` was
    verified 6 Oct on `18-obadiah.epub` (wrote a 0.3 MB `.study.sqlite`) and works for
    Tanach. Not yet done: build and copy all `<book>.study.sqlite` files after the
    rebuild.
- **Talmud source discovery** (scale-up Finding F in
    [reader-device-findings.md](talmud/docs/reader-device-findings.md)). `inventory.py`
    checked commentary markers after the Talmud+Bavli base-text skip, which dropped
    most commentaries; fixed in code. Do NOT rerun `inventory.py` over an edited
    `source-selection.json`; run `plan.py` or `sync` instead.

## Not yet built

- **Selection:** the **More** rework (SEL-002); direct drag-across-blocks;
  multi-block Copy/Dictionary; cross-chapter multi-ranges; fixes for the handle
  problems (SEL-003 to SEL-005).
- **Talmud settings:** remove the Paragraphs/Continuous setting (TAL-012, decided).
- **Vowels and punctuation for Talmud:** investigate what Sefaria's data supplies
  (TAL-013). There is no vowel setting for Tanach and none is wanted.
- **Tanach:** cause of the literal `span`/`class`/`nbsp` text found 11 Oct (tracker:
  TAN-004): `hebrew()` in `tanach/work/build.py` escaped raw source markup; now
  strips to clean text (section markers kept), host-verified over 23,206 verses
  (`span` search was 202 matches in Genesis, all books affected). Rebuild EPUBs +
  sidecars into `study/`, then recheck verses clean and `span` search 0. Sidecars
  in a separate `study/` subfolder (tracker: TAN-005, TAN-006): the reader checks
  `<books-dir>/study/<book>.study.sqlite` first with next-to-EPUB fallback; build
  with `dart run tool/build_study_index.dart <books-dir> --out <books-dir>/study`.
  Device (Tanach): EPUBs at `/sdcard/books/3. nigleh/tanach/tanach w meforshim HE/`,
  sidecars in its `study/` subfolder. Genesis cold import 1m 45s → ~2s warm expected
  once the sidecar matches.
- **Commentary picker:** grouping and a search box for dozens of sources;
  auto-default to Rashi+Tosafot (left as opt-in); a full per-source full-text index
  (the current split is base versus all commentary).
- **Talmud scale-up:** the other 31 tractates; builder one tractate at a time with
  per-source indexing; big-tractate measurements (2, then about 5, then all sources)
  and the EPUB-versus-SQLite decision gate; Bava Batra 29a slot, large-tractate
  splits, commentary budget, addressing verification; Yerushalmi, Mishnah-only,
  cross-references, daf-greater-than-amud nesting.
- **Tanach tooling:** split the tooling, add auto-checksum and Sefaria-change
  detection; EPUB page-list and publisher metadata.
- **Other:** Bigme refresh bridge (needs a documented API); renderer, timing and
  battery measurements; the logcat error (TAL-006); the file browser quirk
  (BRW-001). Tabs and layouts are skipped by owner decision; they were tested
  several times.
