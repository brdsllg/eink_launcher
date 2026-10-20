# Talmud reader: device findings and scale-up

Findings from testing the pilot Talmud EPUBs (Berakhot, Shabbat, Bava Metzia, Bava
Batra, Sanhedrin, Tamid) in the custom reader on the Bigme, and the analysis of
whether the format can carry *every* commentary. **Owner** shows where a fix lives:
*Builder* (regenerate the EPUBs) or *Reader* (Dart code in `lib/reader`).

> **Whether a problem is fixed is recorded in one place only:** the issue tracker in
> [DEVICE_TESTING.md](../../DEVICE_TESTING.md). This file keeps the Talmud-specific
> detail behind each ID and never repeats the status. Follow the writing rules in
> that file when you add anything here.

## Talmud issues and their detail

| ID | Item | Owner | Detail |
|---|---|---|---|
| TAL-001 | Steinsaltz notes included | Builder | Levi chose to keep them. |
| TAL-002 | Bilingual reference headings; English-only wanted | Builder | |
| TAL-003 | Doubled commentary titles ("Rashi on Berakhot on Rashi on…") | Builder | |
| TAL-004 | Page numbers shifted when the keyboard opened | Reader | |
| TAL-005 | One title per note instead of per commented section | Builder | |
| TAL-006 | Log line: "Another exception was thrown: DiagnosticsProperty<void>" | Unknown | See "TAL-006 detail" below. |
| TAL-007 | Contents-page links ("Daf 3a"…) did nothing | Reader | |
| TAL-008 | Settings said "Verse language" | Reader | Now "Talmud language". The line "Selected commentary appears after each segment…" is a helper sentence above the selectors, not a control label. |
| TAL-009 | Berakhot began at Daf 3a (2a and 2b missing) | Builder | |
| TAL-010 | Commentary reading order: with all sources selected, Steinsaltz came before Tosafot | Reader | The picker was already ordered Rashi, Tosafot, rest. The fix sorts projected notes by the same rank (`orderedStudySources`). Standing order requested: Rashi, then Tosafot, then the rest. |
| TAL-011 | Switching Berakhot to Continuous crashed the launcher | Reader | Cause: the whole amud was merged into one block. Fixed in source 6 Oct. If a crash ever recurs, capture `adb logcat` around the switch. |
| TAL-012 | Continuous (the **Talmud layout** setting) changes nothing visible | Reader | **Paragraphs** keeps each body paragraph separate. **Continuous** (`mergeContinuousBlocks`) joins consecutive body paragraphs into flowing text, keeping headings and amud boundaries as breaks. Decision (Levi, 6 Oct 2026): remove the setting. |
| TAL-013 | Vowel marks and punctuation do not show in Talmud text | Builder / Sefaria data | See "TAL-013 detail" below. |
| TAL-014 | First open of Berakhot took 21 s | Builder / Reader | Suggests a stale or missing sidecar, so the reader fell back to importing on the device. Check the sidecar fingerprints. Full timings: DEVICE_TESTING.md, study-book measurements. |
| TAL-015 | "App not responding" when opening or reading Talmud books | Unknown until the cause is established | The owner confirmed on 18 Oct that every Talmud EPUB is affected. Only Tamid has been measured so far; the other tractates still need testing to see whether the cause is the same. Evidence and test steps: [the ANR investigation](reader-ANR-investigation.md). |

Device log of each pass: [DEVICE_TESTING.md](../../DEVICE_TESTING.md).

### TAL-006 detail

Flutter prints that line when an error's details are empty; the useful part is the
"EXCEPTION CAUGHT BY…" block and stack trace just above it. It may be a layout or
overflow error, possibly connected to the keyboard dialog (TAL-004). To diagnose:
capture the full `adb logcat` text around the error, or reproduce it with
`flutter run` for a clean trace. Do not guess a fix; add a regression test once the
cause is known.

### TAL-013 detail

What the owner reported (6 Oct 2026): showing or hiding vowels and punctuation makes
no visible change on Talmud text, yet the Sefaria website shows vowels and
punctuation on all of Talmud.

What is known:

- The pipeline asks Sefaria for vowels for Tanach (`hebrew.vowels=True`) and the
  builder removes cantillation marks only (`strip_trop`, U+0591–U+05AF). The reader
  keeps vowel marks unless **Vowel points** is set to Hidden.
- Whether Sefaria's data feed (as opposed to its website) supplies vowels and
  punctuation for Talmud has **not been checked**. The website may add them from
  another source.
- "Pointed" simply means Hebrew text that carries vowel marks.

Decision (Levi, 6 Oct 2026): there is no vowel setting for Tanach and there should
not be one. The earlier idea of checking the setting on a Tanach verse therefore does
not apply.

To do: look at the raw Talmud text the pipeline downloads (for example Berakhot 2a)
and see whether vowels and punctuation are present. If they are, the builder or
reader is dropping them. If they are not, find out where the website gets them.

## Bigme checklist for the pilot books

1. **Copy the pilot EPUBs** from `talmud/outputs/` onto the device:
   `/sdcard/books/3. nigleh/talmud/talmud w meforshim HE/`.
2. **Copy the `study` folder with them** (built with
   `dart run tool/build_study_index.dart talmud/outputs/books --out talmud/outputs/books/study`,
   so the device has `.../talmud w meforshim HE/study/<tractate>.study.sqlite`).
   First opens should be instant with no import wait; if a sidecar is stale the reader
   falls back to importing on the device. (Verify fingerprints if a first
   open still takes ~20s; see TAL-014.)
3. **Berakhot start and headings:** open Berakhot. It should begin at **Daf 2a**
   (מאימתי קורין את שמע), and headings should be English-only with no duplicated Hebrew.
4. **Commentary:** tap a segment with Rashi. Notes should be grouped per source per
   segment with clean titles such as `Rashi on Berakhot 2a:1`.
5. **Contents links:** on the book's Contents page, tap "Daf 3a" or "Daf 3b"; it
   should jump straight to that amud.
6. **Settings wording:** the language option should read **"Talmud language"**;
   the helper sentence above the selectors reads **"Selected commentary appears
   after each segment…"**.
7. **Page-jump keyboard:** open "Go to page" or "Go to percent". The keyboard should
   appear over the reader without changing page numbers or position.
8. **Commentary picker:** it should list Rashi, Tosafot, and Steinsaltz (kept on
   purpose), plus the Rashi-slot substitutes for Bava Batra and Tamid.
   With several sources selected, reading order should keep Rashi then Tosafot
   first (TAL-010).

## How the reader treats study books

The study recognizer accepts the Talmud format (`section.segment[data-ref]`, the
`note-index` shape, `data-category="commentary"`, `p.translation`). Recognized books
go into the per-book SQLite cache and their chapters load lazily, so any reader code
that reads a chapter's link targets directly must load the chapter first (which is
what TAL-007 tripped over). Regenerating EPUBs changes their bytes, so the reader
re-imports automatically; no manual cache clearing is needed.

## Can the format carry every commentary?

**Decisions (Levi, 2 Oct 2026):** include everything Sefaria labels a *commentary* on
the Bavli, across all 37 tractates, not merely items linked to it (blacklist
approach, starting empty). Talmud files need only work in the custom reader, so
leaving the standard EPUB format is acceptable.

**Not measured.** The analysis came from reading the code and the Tanach figures
(Genesis 1 is 3,006,495 bytes of XHTML with only a whitelist of commentaries). Talmud
sizes were unavailable on the machine used. The Bigme's RAM and free storage are
unknown.

**Conclusion.** The pilot EPUBs suit Rashi plus Tosafot but are not yet built to carry
everything. The reader already helps (one gzipped document per amud, lazy chapter
loading, only *selected* sources become display blocks, a 768 MiB cache limit). The
weak spots are packaging, first-open import, search, and the build script, and most
can be fixed in the builder.

### Scale-up work items

These are project work items, not device problems, so they are not in the issue
tracker. They use the same status words as DEVICE_TESTING.md. **FIX BUILT** here means
the code change exists and passes computer tests.

| | Finding | Owner | Status |
|---|---|---|---|
| A | One note per comment (own id, four data attributes, back-links) plus one index link per comment; with many sources the wrapper markup could rival the commentary text | Builder | **OPEN.** Grouping per source per segment is done (TAL-003, TAL-005). Builder back-links removed Oct 2026 (`talmud/work/build.py`, `tanach/work/build.py` no longer emit `<p class="backlinks">`; reader already stripped them). One index link per source is in place. Remaining: the one-note-per-comment wrapper size |
| B | Opening an amud parses the whole document, every installed commentary included, before filtering to the chosen sources | Reader / format | **OPEN** |
| C | First open sends every amud's XHTML through parsing, compression, and search-text building before anything shows. The main risk for the biggest tractates (Shabbat, Bava Batra, Bava Metzia, Zevachim, Chullin) with full commentary | Reader | **OPEN.** Must be tested on the device |
| D | Search scans every amud's text including unselected commentary, then fully projects every candidate; a common Hebrew word matches nearly every amud | Reader | **FIX BUILT** (partial, Oct 2026): SQLite v6 splits `base_search_text`/`commentary_search_text`; with no source selected only base is scanned. With sources selected the final projection still applies the exact filter. A full per-source index is still future work |
| E | Build script: the link-attachment loop rescans every comment of a source for each link row (roughly links × comments); all comments sit in memory at once; `inventory.py` downloads every non-merged edition including other languages | Builder | **OPEN** |
| F | Source discovery may be incomplete: the manifest lists only 13 non-pilot titles "pending review", far fewer than exist, and `inventory.py` skips any category containing both `Talmud` and `Bavli` as base text, which would silently drop commentaries filed there. The rule to implement is "labeled a commentary by Sefaria's category", not "linked to the Bavli" | Builder | **FIX BUILT** (6 Oct): commentary markers are now checked before the Talmud+Bavli base-text skip (most commentaries live under Talmud/Bavli). Do NOT rerun `inventory.py` over an edited `source-selection.json`; verify by re-running inventory on a copy and comparing counts |
| G | Amud offset (arrays assumed to start at 2a) | Builder | **CLOSED** (resolved; see the plan document) |

### Order of work

1. **Builder scaling:** index comments per source (a sorted list or dictionary by
   address) instead of rescanning; process one tractate at a time; avoid holding all
   sources in memory; one Hebrew and one English edition per source.
2. **Investigate F** now that the catalog files are on this machine.
3. **Measure** one big tractate (Shabbat or Bava Batra) with 2 sources, then about 5,
   then everything: EPUB size, largest amud, first-open import time, peak memory,
   page-turn speed, and a search for a common word. Record the numbers in the plan
   document.
4. **Decision gate:** if import time or memory is unacceptable at "everything",
   change the Talmud format (below) rather than trimming sources.
5. **Reader, independent of format:** limit search to selected sources; default the
   picker to Rashi and Tosafot; with dozens of sources the picker needs grouping or a
   search box; finish picker ordering. Owner decision Oct 2026: commentary
   downloads and builds are English + Hebrew only (French, German, and other
   languages are skipped at inventory time).
6. Log the blacklist decision and measured budget in `talmud-epub-plan.md`.
   Device for sizing: Bigme HiBreak, 4 GB RAM (owner, Oct 2026).

### Option: Talmud as a SQLite file

Since Talmud only needs to open in this reader, the Python pipeline could write a
SQLite file directly, so the reader opens it with no import step. This is also the
answer to Levi's question below: the heavy work would happen on the computer, once.

- **Rough shape:** tables for `segments(masechta, amud, seg, he, en)`,
  `commentary(source, amud, seg, position, he, en)`, `sources`, `toc`, plus a search
  index.
- **Benefits:** no first-open import; per amud the reader queries only the selected
  sources, so cost follows what is selected, not what is installed; search can be
  limited to selected sources with a real index.
- **Costs:** a second loading path in the reader (Tanach could stay on EPUB, or both
  could later share the study-text contract); the files stop opening in other apps
  such as KOReader (an EPUB export from the same database would cover that).
- Confirm the app's bundled `sqlite3` includes FTS5 before relying on a full-text
  index. Not verified.
- **Cheaper middle option:** stay on EPUB but put each source's commentary in its own
  XHTML file inside the book (also noted in Tanach's `reader-compatibility.md`), so an
  amud load parses only what it needs.

## Open questions

- **Levi's question (answered Oct 2026): can the laptop do the heavy first-open
  work? Yes — and SQLite is the best answer, but not the only one.** In plain
  words: today the phone/computer-book arrives as an EPUB and the device itself
  has to unpack, read, and index it on first open, which is the slow step. The
  laptop can do that work once and hand the device a ready-made index file.
  Options, best first:
  1. **Ready-made SQLite index (best).** The pipeline on the laptop builds a
     small database per book (chapters + commentary + search index) and you copy
     it into the `study` subfolder beside the EPUBs; the reader opens it
     instantly with no import step.
     This is exactly how Tanach already works on the device
     (`tanach_sqlite_cache_service.dart`, `instr`-based search, no FTS5 needed),
     so Talmud would reuse a proven path. Cost: the reader gains a second
     loading path, and the index files stop opening in other apps (keep an EPUB
     export from the same database for KOReader).
  2. **Split-commentary EPUB (cheaper middle option).** Stay on EPUB but put
     each commentary in its own file inside the book, so opening a page reads
     only what you asked for. Less code, still parses on the device.
  3. **Bigger EPUB + bigger reader limit (simplest, weakest).** Just raise the
     size cap and hope 4 GB RAM absorbs it. No new code, but first opens stay
     slow and large tractates may still choke.
  With 4 GB RAM the current pilot sizes (largest pilot EPUB Shabbat 3.4 MB,
  `talmud.sqlite` 83 MB for pilot content) are comfortable; the risk is only the
  full-commentary build, which is why we measure Shabbat with 2, ~5, then all
  sources before deciding.
- How large are the full-commentary EPUBs and `talmud.sqlite`, and what are the
  Bigme's RAM and free storage? (The Sefaria cache was re-synced on 5 Oct, so sizes
  can now be measured. Device: 4 GB RAM, owner Oct 2026.)
- Any commentaries to blacklist from the start (duplicates, wrong-language editions,
  works with little text)? Currently none.
