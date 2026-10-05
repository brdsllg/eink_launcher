# Talmud reader: device findings and scale-up

Findings from testing the pilot Talmud EPUBs (Berakhot, Shabbat, Bava Metzia, Bava
Batra, Sanhedrin, Tamid) in the custom reader on the Bigme, and the analysis of
whether the format can carry *every* commentary. **Owner** shows where a fix lives:
*Builder* (regenerate the EPUBs) or *Reader* (Dart code in `lib/reader`).

## Status of the nine findings (5 Oct 2026)

| # | Item | Owner | Status |
|---|---|---|---|
| 1 | Steinsaltz notes included | Builder | **Closed.** Levi chose to keep them |
| 2 | Bilingual reference headings; wanted English-only | Builder | Fixed and verified on the computer |
| 3 | Doubled commentary titles ("Rashi on Berakhot on Rashi on…") | Builder | Fixed and verified |
| 4 | Page numbers shifted when the keyboard opened | Reader | Fixed (keyboard no longer resizes the reader) |
| 5 | One title per note instead of per commented section | Builder | Fixed and verified (one block per source per segment) |
| 6 | Logcat: "Another exception was thrown: DiagnosticsProperty<void>" | — | **Open: needs the full error text** |
| 7 | Contents-page links ("Daf 3a"…) did nothing | Reader | Fixed (links now load the target chapter first) |
| 8 | Settings said "Verse language" | Reader | Fixed ("Talmud language" / "after each segment") |
| 9 | Berakhot began at Daf 3a (2a and 2b missing) | Builder | Fixed; cause was a one-daf offset, now corrected |

The builder fixes (2, 3, 5, 9) were checked on the pilot rebuild: Berakhot opens at
2a with `Berakhot 2a:1` beginning מאימתי קורין את שמע; headings contain no Hebrew;
commentary blocks are one per source per segment and titled like `Rashi on Berakhot
2a:1`. All six EPUBs pass EPUBCheck and the link audit. **None of this has been
checked on the Bigme** (no Bigme was connected at the time).

### Item 6 (open)

Flutter prints that line when an error's details are empty; the useful part is the
"EXCEPTION CAUGHT BY…" block and stack trace just above it. It may be a layout or
overflow error, possibly connected to the keyboard dialog (item 4, now fixed). To
diagnose: capture the full `adb logcat` text around the error, or reproduce it with
`flutter run` for a clean trace. Do not guess a fix; add a regression test once the
cause is known.

## Bigme checklist for the pilot books

1. **Copy the pilot EPUBs** from `talmud/outputs/` onto the device.
2. **Berakhot start and headings:** open Berakhot. It should begin at **Daf 2a**
   (מאימתי קורין את שמע), and headings should be English-only with no duplicated Hebrew.
3. **Commentary:** tap a segment with Rashi. Notes should be grouped per source per
   segment with clean titles such as `Rashi on Berakhot 2a:1`.
4. **Contents links:** on the book's Contents page, tap "Daf 3a" or "Daf 3b"; it
   should jump straight to that amud.
5. **Settings wording:** the options should read **"Talmud language"** and **"after
   each segment"**.
6. **Page-jump keyboard:** open "Go to page" or "Go to percent". The keyboard should
   appear over the reader without changing page numbers or position.
7. **Commentary picker:** it should list Rashi, Tosafot, and Steinsaltz (kept on
   purpose), plus the Rashi-slot substitutes for Bava Batra and Tamid.

## How the reader treats study books

The study recognizer accepts the Talmud format (`section.segment[data-ref]`, the
`note-index` shape, `data-category="commentary"`, `p.translation`). Recognized books
go into the per-book SQLite cache and their chapters load lazily, so any reader code
that reads a chapter's link targets directly must load the chapter first (which is
what item 7 tripped over). Regenerating EPUBs changes their bytes, so the reader
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

### Findings

| | Finding | Owner | Status |
|---|---|---|---|
| A | One note per comment (own id, four data attributes, back-links) plus one index link per comment; with many sources the wrapper markup could rival the commentary text | Builder | Grouping per source per segment is done (items 3, 5). Still to do: drop back-links the reader strips anyway; one index link per source is in place |
| B | Opening an amud parses the whole document, every installed commentary included, before filtering to the chosen sources | Reader / format | Open |
| C | First open sends every amud's XHTML through parsing, compression, and search-text building before anything shows. The main risk for the biggest tractates (Shabbat, Bava Batra, Bava Metzia, Zevachim, Chullin) with full commentary | Reader | Open; must be tested on the device |
| D | Search scans every amud's text including unselected commentary, then fully projects every candidate; a common Hebrew word matches nearly every amud | Reader | Open |
| E | Build script: the link-attachment loop rescans every comment of a source for each link row (roughly links × comments); all comments sit in memory at once; `inventory.py` downloads every non-merged edition including other languages | Builder | Open |
| F | Source discovery may be incomplete: the manifest lists only 13 non-pilot titles "pending review", far fewer than exist, and `inventory.py` skips any category containing both `Talmud` and `Bavli` as base text, which would silently drop commentaries filed there. The rule to implement is "labeled a commentary by Sefaria's category", not "linked to the Bavli" | Builder | Unverified. `books.json` and `table_of_contents.json` are now cached (5 Oct), so it can be checked |
| G | Amud offset (arrays assumed to start at 2a) | Builder | **Resolved**: see the plan document |

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
   search box; finish picker ordering.
6. Log the blacklist decision and measured budget in `talmud-epub-plan.md`.

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

- **Levi's question:** could the memory- and processor-heavy first-open work be done
  on a laptop and the result saved when importing to the device? *Unanswered in the
  notes. The SQLite option above is the practical form of this idea.*
- How large are the full-commentary EPUBs and `talmud.sqlite`, and what are the
  Bigme's RAM and free storage? (The Sefaria cache was re-synced on 5 Oct, so sizes
  can now be measured.)
- Any commentaries to blacklist from the start (duplicates, wrong-language editions,
  works with little text)? Currently none.
