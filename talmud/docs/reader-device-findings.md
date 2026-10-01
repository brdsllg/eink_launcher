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
