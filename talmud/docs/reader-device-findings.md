# Talmud reader — device findings and diagnosis

Findings from testing the generated Talmud EPUBs (pilot: Berakhot, Shabbat,
Bava Metzia, Bava Batra, Sanhedrin, Tamid) in the custom reader on the Bigme,
after the reader gained shared Tanach/Talmud "study text" support.

Each item records: **Symptom**, **Evidence**, **Cause**, **Suggested fix**, and
**Owner** (Builder = regenerate the EPUBs; Reader = Dart code in `lib/reader`).

Summary: 

| # | Item | Owner |
|---|---|---|
| 1 | "Steinsaltz on X" commentary is included but not wanted | Builder |
| 2 | Reference headings are bilingual; want English-only | Builder |
| 3 | Commentary titles duplicated ("Rashi on Berakhot on Rashi on …") | Builder |
| 4 | Page numbers/percent recalculated when the keyboard opens | Reader |
| 5 | One title per commentary note instead of per commented section | Builder |
| 6 | Logcat: "Another exception was thrown: DiagnosticsProperty<void>" | Needs data |
| 7 | Contents-page links ("Daf 3a" …) do nothing | Reader |
| 8 | Settings say "Verse language" for Talmud | Reader |
| 9 | Berakhot EPUB starts at Daf 3a (2a/2b missing) | Builder |

---

## 1. "Steinsaltz on <tractate>" commentary is shown but not wanted

- **Symptom:** the commentary source picker lists "Steinsaltz on Berakhot" and
  its notes render.
- **Evidence:** `talmud/work/inventory.py` `PILOT_COMMENTARY_ORDER = ['Rashi',
  'Tosafot', 'Steinsaltz']`; `_commentary_status()` returns `include` for
  `Steinsaltz on {m}`; `talmud/outputs/source-selection.json` records the same.
  At runtime `book.studySources = [Rashi on Berakhot, Steinsaltz on Berakhot,
  Tosafot on Berakhot]`.
- **Cause:** the pilot commentary policy includes Steinsaltz's study notes.
- **Suggested fix (Builder):** remove `'Steinsaltz'` from `PILOT_COMMENTARY_ORDER`
  and from the per-masechta `include` rule, re-run `inventory.py`, then rebuild.
  Keep the *translation* "William Davidson (Steinsaltz)" — a separate source that
  should stay. Assert the picker shows only Rashi/Tosafot (plus the Rashi-slot
  aliases for Bava Batra and Tamid).

## 2. Reference headings are bilingual; want English-only

- **Symptom:** every paragraph shows "Berakhot 3a:1" and the same label in
  Hebrew; the amud title shows "Daf 3a" and Hebrew "דף ג׳ עמוד א׳".
- **Evidence:** `talmud/work/build.py` emits two spans: the segment heading
  (≈ lines 382–390) and the amud heading (≈ lines 337–340). The reader treats
  headings as labels and never rewrites them, so the language setting cannot
  remove the Hebrew.
- **Cause:** the builder emits a bilingual reference heading for each paragraph
  and amud (the plan called for an English-only segment heading such as
  `Berakhot 2a:1`).
- **Suggested fix (Builder):** emit English-only segment headings and make the
  amud heading English-only (or drop the Hebrew span). Rebuild.

## 3. Commentary titles duplicated ("Rashi on Berakhot on Rashi on Berakhot 3:1:1")

- **Symptom:** each note title repeats the source name.
- **Evidence:** `talmud/work/build.py` ≈ lines 468–472:
  `note_title = source + " on " + ref`, where `ref` already begins with the
  source name (e.g. `Rashi on Berakhot 3:1:1`).
- **Cause:** concatenating the source name with a reference that already
  contains it.
- **Suggested fix (Builder):** build the title from the source plus the base
  section being commented on (e.g. `Rashi on Berakhot 3a:1`), or strip the
  `source` prefix from `ref` before appending. Rebuild.

## 4. Page numbers / percent recalculated when the keyboard opens

- **Symptom:** opening "Go to page (1–N)" or "Go to percent" pops the keyboard
  and the page numbers/percent shift.
- **Evidence:** the reader `Scaffold` (`lib/reader/screens/reader_screen.dart`
  ≈ line 546) does not set `resizeToAvoidBottomInset: false`. `text_page_view.dart`
  reports the `LayoutBuilder` viewport to `TextReaderSession.updateViewport` →
  `prepareViewport` → `_repaginate` (`text_reader_session.dart` lines 417–447).
- **Cause:** the on-screen keyboard shrinks the reader body, triggering a full
  repagination; `pageCount` and every page's identity change while the dialog is
  open.
- **Suggested fix (Reader):** set `resizeToAvoidBottomInset: false` on the reader
  `Scaffold` so the keyboard overlays rather than resizes the reader (fits the
  fixed-page e-ink design). Optionally freeze `pageCount`/percent while the
  dialog is open. Verify on device.

## 5. One title per commentary note instead of one per commented section

- **Symptom:** a section with two Rashi comments shows two separate "Rashi …"
  notes, each titled, instead of one grouped block.
- **Evidence:** `talmud/work/build.py` emits one `commentary-note` aside and one
  index link **per Sefaria note** (≈ lines 432–445 for the index, 448–510 for
  the asides), not per (source × commented section). The reader renders one title
  per aside.
- **Cause:** note-level asides rather than source-per-section grouping; the plan
  wanted "one heading per source per segment … separate paragraphs for each
  comment underneath".
- **Suggested fix (Builder):** group by source per commented section — one aside,
  one title, all comment segments as paragraphs. Rebuild.

## 6. Logcat: "Another exception was thrown: Instance of 'DiagnosticsProperty<void>'"

- **Symptom:** repeated error in logcat while reading.
- **Cause:** not determinable from that line alone. Flutter prints this when a
  widget/layout exception's diagnostic payload is void; the useful text is the
  preceding "EXCEPTION CAUGHT BY …" block with its stack trace (often a layout
  or overflow error, possibly related to item 4's dialog/keyboard path).
- **Suggested fix (needs data):** capture the full `adb logcat` block around the
  error (lines immediately above it and the stack trace), or reproduce with
  `flutter run` for a clean stack, then fix and add a regression test. Do not
  guess-fix.

## 7. Contents-page links ("Daf 3a", "Daf 3b", …) do nothing

- **Symptom:** on the book's Contents page, the links labelled "Daf 3a",
  "Daf 3b", … do not navigate.
- **What that page is:** the built EPUB spine order is `title.xhtml`,
  **`nav.xhtml`**, then `amud-3a.xhtml`, `amud-3b.xhtml`, …. So `nav.xhtml` is
  rendered as the second reading document, and its `<ol>` of
  `<a href="amud-3a.xhtml#amud-3a">Daf 3a</a>` links are the ones that fail.
  (The reader's own ToC/Contents *screen* is fine — all 125 entries carry a
  valid position.)
- **Evidence (reproduced):**
  - Plain parse: `spine[2]` (amud-3a) `lazy=false loaded=true anchors=57
    has3a=true`.
  - Cache path (what the device uses): `spine[2]` `lazy=true loaded=false
    anchors=0 has3a=false`.
  - `TextReaderSession.openLink` (`text_reader_session.dart` ≈ lines 530–551)
    resolves the href to `EPUB/amud-3a.xhtml`, finds the spine item, then reads
    `book.spine[spineIndex].anchors['amud-3a']`. For a lazy study chapter that
    map is empty, so `block == null` and the method returns `false`; the tap is
    silently ignored.
- **Cause:** `openLink` resolves an anchor against the chapter's anchors before
  the lazy chapter is loaded; lazy study chapters expose no anchors until loaded
  (`_ensureChapterLoaded`, lines 1018–1069, is what fills them — already used by
  the percent jump).
- **Suggested fix (Reader):** in `openLink`, when the target chapter is
  `!isLoaded`, first `await _ensureChapterLoaded(spineIndex)` (then re-read
  `_book`), and only then look up the anchor; keep the `block == null → block 0`
  fallback for fragment-less links. This restores the Contents-page links (and any
  other link into a not-yet-loaded chapter). Add a regression test using the
  cached/lazy path, not the eager parse.

## 8. Settings say "Verse language" for Talmud

- **Symptom:** the dropdown reads "Verse language" and the help text says
  "after each verse".
- **Evidence:** `lib/reader/screens/reader_settings_screen.dart` hardcodes
  `'Verse language'` (≈ line 90) and the help text (≈ lines 86–88); the screen
  has no notion of Tanach versus Talmud.
- **Cause:** the study controls were written for Tanach only.
- **Suggested fix (Reader):** add a study-unit label to `ParsedBook`
  (`verse` for `section.verse`, `segment` for `section.segment`), detected in the
  parser/layout, and pass it to the settings screen so Talmud shows
  "Talmud language" and "after each segment".

## 9. Berakhot EPUB starts at Daf 3a (2a/2b missing)

- **Symptom:** the tractate opens at Daf 3a; the true start of Berakhot is
  missing, so any navigation to the beginning lands at 3a.
- **Evidence:** `berakhot.epub` contains 125 amud files, the first being
  `EPUB/amud-3a.xhtml` (no `amud-2a`/`amud-2b`); `talmud/outputs/
  full-coverage.json` reports `amudim: 125` for Berakhot.
- **Cause:** unknown; the normalized `segments` table appears to lack Daf 2 rows
  for Berakhot. Needs investigation in the fetch/normalize/build stages.
- **Suggested fix (Builder):** check `talmud/work/build.py` base-text
  normalization and the Sefaria fetch for Berakhot 2a–2b, and confirm the amud
  range is complete before the next build.

---

## Reader architecture note (why these show up now)

- The reader's study recognizer and projection accept the Talmud dialect
  (`section.segment[data-ref]`, `class="note-index"`, `data-category="commentary"`,
  `p.translation`), so the books now open as structured study text.
- Recognized study books are imported into the per-book SQLite cache; their
  chapters become **lazy** spine items whose blocks and anchors load on demand.
  Any reader code that reads `spine[i].anchors` directly must load the chapter
  first — exactly what item 7 trips over.

## Cache note

Regenerating the EPUBs (items 1, 2, 3, 5, 9) changes their bytes, so the reader's
parsed cache and SQLite cache re-import automatically; no manual cache clearing
is needed.

---

## Commentary scale-up: analysis and suggestions (2026-10-02)

Question asked: can the EPUBs and the reader handle **every** commentary instead
of the Rashi/Tosafot (+Steinsaltz) pilot set, and would SQL or a SQLite-based
format help?

### Decisions from Levi

- Include everything Sefaria labels as a **commentary** on the Bavli, across all
  37 masechtos, not just items that are merely linked/related. This is the
  blacklist approach already preferred in `talmud-epub-plan.md`; the starting
  blacklist is empty.
- The Talmud files only need to work in the custom reader. Leaving the standard
  EPUB format for Talmud is acceptable.

### What was and was not checked

- Read: `work/build.py`, `work/inventory.py`, `lib/reader/services/
  tanach_sqlite_cache_service.dart`, `tanach_layout_service.dart`,
  `tanach_sqlite_search_service.dart`, and `tanach/outputs/reader-compatibility.md`.
- **Not measured.** The generated EPUBs, `talmud.sqlite`, the Sefaria cache and
  `build-report.json` are gitignored and were not on the machine used for this
  analysis. Every performance statement below is reasoning from the code and the
  Tanach figures (Genesis 1 = 3,006,495 bytes of XHTML with only a whitelist of
  commentaries), not a Talmud measurement.
- Unknown: the Bigme's RAM and free storage.

### Conclusion

The pilot EPUBs are fine for Rashi + Tosafot but are not yet built to carry
everything. The reader architecture already helps: one gzipped document per
amud, lazy chapter loading, only the *selected* sources become render blocks
(`settings.commentarySources`), and a 768 MB cache cap. The weak points are the
EPUB packaging, first-open import, search, and the build script, and most can be
fixed in the builder.

### Findings

**A. Per-comment packaging (Owner: Builder).** `build.py` emits one `aside` per
Sefaria comment (own id, four `data-*` attributes, title, back-links) plus a
per-segment index aside with one `noteref` link per comment. Tanach revision 5
already groups one aside per source per verse; Talmud does not (this is findings
3 and 5). With many sources the wrapper markup could rival the commentary text.

**B. Amud open cost scales with installed, not selected, commentary (Owner:
Reader/format).** `TanachLayoutService.layout` runs `html.parse` over the whole
amud document, every aside included, before filtering to the chosen sources.

**C. First-open import (Owner: Reader).** `TanachSqliteCacheService.import`
receives every amud's XHTML in memory (`studyDocuments`), parses each with
`html.parse`, gzips it, and builds `search_text`, before anything can be shown.
This is the main risk for the largest tractates (Shabbat, Bava Batra, Bava
Metzia, Zevachim, Chullin) with full commentary. Not measured; must be tested on
the device.

**D. Search (Owner: Reader).** `instr(search_text, ...)` scans every amud's text
including unselected commentary, then fully projects (parse + layout) every
candidate amud. A common Hebrew word matches nearly every amud, so search time
grows with the amount of commentary installed.

**E. Build script scaling (Owner: Builder).**
- In the link-CSV attachment loop, each link row iterates over every comment of
  that source (`resolver[nr].items()` filtered by `in_range`), which is roughly
  links x comments and will be very slow at full scale.
- `raw` and `notes` hold every comment in Python memory at once.
- `inventory.py` downloads *all* non-merged editions of each included source
  (including other-language ones, such as the French Rashi/Tosafot warnings on
  Berakhot), while only one edition per language ends up in the output.

**F. Source discovery looks incomplete (Owner: Builder). Unverified.** The
manifest lists only 13 non-pilot titles ("Pending review: 13"), far fewer than
the Bavli commentaries that exist. `inventory.py` skips any TOC node whose
categories contain both `Talmud` and `Bavli` as "base text"; if Sefaria files
commentaries under those categories they are dropped silently. Needs
`books.json` / `table_of_contents.json` to confirm. The rule to implement is
"labeled a commentary by Sefaria's category", not "linked to the Bavli".

**G. Suspected daf offset (Owner: Builder). Unverified, check before any full
build.** `_amud_sequence` in `normalize()` assumes array index 0 is 2a, and
`_amud_from_idx` assumes the same for commentary. If Sefaria's Bavli arrays begin
at 1a (two empty leading entries), every amud is labeled one daf late. That fits
finding 9 (first amud is 3a, 125 amudim, which is Berakhot's real 2a-64a count).
Commentary would shift identically, so EPUBCheck and the anchor audits would not
catch it. Check: look at the first two entries of `d['text']` in the cached
Berakhot Hebrew JSON, and confirm the segment labeled 3a does not actually begin
with the opening of 2a (מאימתי קורין את שמע). Relates to OQ-1, OQ-2, A1, A2.

### Suggested order of work

1. **Verify G and F** on the machine that has the Sefaria cache. Fix the amud
   mapping before anything else, since it affects every output.
2. **Builder, cheap and high value:** group commentary per source per segment
   (findings 3 and 5); with grouping the index needs one link per source instead
   of per comment; consider dropping the back-links the reader strips anyway;
   fix the doubled note titles; one Hebrew and one English edition per source.
3. **Builder scaling:** pre-index comments per source (sorted list or dict by
   address) instead of rescanning; process one masechta at a time; avoid holding
   all sources in memory.
4. **Measure** one big tractate (for example Shabbat or Bava Batra) built with 2
   sources, then about 5, then everything. Record EPUB size, largest amud XHTML
   size, first-open import time, peak memory, page-turn speed, and a search for a
   common word. Add the numbers to this file.
5. **Decision gate:** if import time or memory is unacceptable at "everything",
   change the Talmud format (next section) rather than trimming sources.
6. **Reader, independent of the format:** restrict search candidates to the
   selected sources; default the picker to Rashi and Tosafot only; with dozens of
   sources the picker needs grouping or a search box; finish the picker ordering
   (Rashi, Tosafot, rest).
7. **Plan doc:** record the blacklist decision and the measured budget in
   `talmud-epub-plan.md` once step 4 is done.

### Option if EPUB packaging is not enough: Talmud as a SQLite file

Since Talmud only needs to open in this reader, the Python pipeline could write a
SQLite file directly, and the reader would open it without the import step.

- Rough shape: `segments(masechta, amud, seg, he, en)`; `commentary(source,
  amud, seg, position, he, en)`; `sources`; `toc`; plus a search index.
- Benefits: no first-open import; per amud the reader queries only the selected
  sources, so open and page-turn cost follow what is selected, not what is
  installed; search can be limited to selected sources with a real index.
- Costs: a second loading path in the reader (Tanach can stay on the EPUB path or
  both can later share the study-text contract); the files no longer open in
  other apps such as KOReader. Keeping the EPUB export from the same database
  would cover that.
- Before relying on a full-text index, confirm the bundled `sqlite3` package in
  the Flutter app includes FTS5. Not verified.
- A cheaper middle option: stay on EPUB but put each source's commentary in its
  own XHTML file inside the book (also noted in `reader-compatibility.md`
  section 9), so an amud load parses only what is needed.

### Open questions

- Where do the generated EPUBs, `talmud.sqlite` and the Sefaria cache live, and
  what are their sizes?
- Bigme B751C RAM and free storage.
- Any commentaries to blacklist from the start (duplicates, wrong-language
  editions, works with little text)?
- user here, i have a question: would it be a practical possibility to do the memory and cpu intensive work on first open on a laptop and save the data when importing to the device? 
