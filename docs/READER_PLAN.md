# Reader design

The built-in reader supports PDF, EPUB, TXT, and Markdown. This document records how
it behaves, the decisions behind it, and what remains. Device results are in
[DEVICE_TESTING.md](DEVICE_TESTING.md); screen dimensions are in
[LAYOUT_DESIGN.md](LAYOUT_DESIGN.md).

## Product decisions

| Area | Decision |
| --- | --- |
| PDF engine | `pdfrx`/PDFium through its document API; the app renders its own images |
| Text engines | EPUB parsed directly (`archive`, `xml`, `html`); one custom paginator for EPUB, TXT, and Markdown |
| Formats | PDF, EPUB, TXT, Markdown. CBZ and MOBI are out of scope |
| Page controls | Three equal tap zones: left back, centre menu, right forward. Right is always forward, including RTL books |
| Gestures | Fit modes and text allow page swipes. PDF Zoom / Scroll keeps drag and pinch for the document |
| Chrome | Full-bleed reading; a centre tap toggles the menu |
| Orientation | Manual portrait/landscape toggle only; no sensor rotation |
| Saved state | Global defaults and per-document state in one atomic `library.json` |
| Entry point | Open readable files from the file browser; **Open with** stays as an escape hatch |
| Search | EPUB, TXT, Markdown only. PDF text search is out of scope |
| Dictionary | Offline lookup (English, modern Hebrew, Rabbinic Hebrew/Aramaic) for text formats and text-layer PDFs |
| Annotations | Underline plus optional note, for text formats and text-layer PDFs ([annotation_plan.md](annotation_plan.md)) |
| Not planned | Highlight colors, text-to-speech, DRM bypass |

## Sessions and reading position

`ReaderSessionRegistry` keeps document sessions outside individual screens so they
survive navigation and tab switches. At most four sessions are active. Backgrounding
the app, memory pressure, the four-session cap, and switching tabs all suspend
sessions: position and metadata are kept, while PDFium handles and page images are
released. Back cancels pending work but keeps the tab, its session, and its caches.

Positions are logical, not page numbers, so changing font, crop, orientation, or PDF
mode keeps the reader's place:

- **PDF:** `(pageIndex, withinPage)`, where `withinPage` runs from 0 to 1.
- **Text:** `(spineIndex, blockIndex, charOffset)`.

A document's ID comes from its first 64 KiB plus its size, so saved state usually
follows a file when it is renamed or moved. `BookStoreService` saves atomically with
debounce. If `library.json` is malformed, up to three full backups are kept before
replacement; if backing up is unsafe, saving is switched off for that launch and the
reader says why.

## PDF

PDFium starts only when the first PDF opens. Rendering follows this path:

```text
PDF file -> page/crop geometry -> priority scheduler -> PDFium render
         -> app-owned image -> fit page or continuous tiled view
```

### Display modes

- **Fit Height:** a cropped whole page scaled to the screen height; one page per
  screen.
- **Fit Width:** scaled to screen width, with tall pages split into overlapping
  screen-height slices (default overlap 6%).
- **Zoom / Scroll:** a continuous vertical document with two-axis pan, pinch zoom,
  and Android-style momentum, using the app's own scale and origin geometry.

Fit modes can crop per page. Zoom / Scroll uses one crop sampled across the whole
document, because stable geometry is needed to compute exact page extents before
anything renders.

### Staying responsive

- **One render at a time.** A shared scheduler lets one PDFium render or crop run at
  a time. Visible pages come first, then sharp detail, then speculative work.
  Identical pending requests share work, and out-of-date requests are withdrawn. A
  PDFium call already running must still finish.
- **Ordered rapid taps.** Fit Height/Width page turns are applied in input order.
  Closing, suspending, changing mode, or jumping cancels stale work.
- **Pixels during movement.** Small whole-page previews sit under sharp tiles.
  Useful old detail stays until its replacement is ready, and sharp refinement
  starts after 200 ms of stillness. Exact page extents mean late images never shift
  the document.
- **Preview cache.** Previews are 320 px on the longest edge, kept in a 64 MiB disk
  cache keyed by document and geometry. Bad or partial entries are deleted. Idle
  warming yields to visible work and stops on touch, backgrounding, suspension,
  memory pressure, or leaving the reader.
- **Look-ahead.** Preview demand grows in the scroll direction with speed (up to four
  screens or 16 pages), resets on direction change, and returns to one screen when
  scrolling settles.
- **Touch.** Touching the screen stops momentum immediately; pan or pinch continues
  from there. Left/right taps move one visible viewport height.

**Known limit:** a page never seen before still needs its first PDFium render. At
minimum zoom, a very fast fling can pass several new pages per second and briefly
outrun it. The cache helps prepared and revisited pages; it cannot pre-render a new
book at open time.

### PDF memory

Each session sets its image budget from Android's normal heap class: 25%, clamped to
4–128 MiB, or 32 MiB if unknown. Images on screen, the active native render, PDFium
data, and graphics memory sit outside that budget, which is why suspension and
memory-pressure recovery matter. On the HiBreak, total memory after sequential PDF
use was about 332 MiB and fell to about 148 MiB after memory-pressure recovery.

## Text (EPUB, TXT, Markdown)

```text
EPUB / Markdown / TXT -> semantic blocks and styles -> direction and hyphenation
  -> text measurement -> exact block slices -> pages
```

Parsing uses background workers where practical; final measurement happens on the UI
thread, which owns Flutter's text layout. Page caches are keyed by document,
chapter, viewport, and typography.

**Progressive pagination.** The chapter holding the reading position is laid out
first and publishes each page as it finishes. The other chapters follow in the
background, forward first. Page turns, contents and percent jumps, bookmarks, and
setting changes wait only for the pages they show, never a whole chapter or book,
and each chapter is measured once even if requested while still in progress. Until
the page holding the saved position exists, the view shows "laying out pages" rather
than an earlier page, which would move the saved position backwards.

**Supported:** EPUB 2 and 3 navigation; UTF-8, UTF-16, and Windows-1255 TXT; mixed
English/Hebrew with Hebrew marks; bundled Latin and Hebrew fonts; font size, line
height, margins, justification, hyphenation, paragraph spacing and indent; a safe
subset of publisher styles; bookmarks, contents and percent jumps; text search with
Hebrew-mark normalization. Publisher fonts, sizes, and colors are ignored. Encrypted
content shows a clear DRM message.

### Study books (Tanach and Talmud)

Recognized study EPUBs use a bounded-memory variant:

- **First open** builds a disposable per-book SQLite cache: gzip-compressed chapter
  XHTML, navigation, resources, stable verse targets, and a normalized search
  column.
- **Later opens** check the EPUB's SHA-256 and the cache version before reuse.
- **On demand,** chapters are projected for the chosen translation and commentary;
  only three projected chapters stay in memory. Typography-only changes keep them.
  Changing commentary sources, commentary language, translation, or publisher
  styling re-projects the current chapter.
- **Search** uses `instr()` on a Hebrew-mark-normalized column, then matches visible
  blocks. It deliberately accepts partial words. It is not FTS5, and vowel-sensitive
  searches are not supported.
- **Cache order.** The SQLite cache is checked first. A legacy JSON hit can seed it
  if it is missing or stale; new study books are written only to SQLite. Ordinary
  EPUBs still use the JSON cache (64 MiB limit). The SQLite limit is 768 MiB; the
  two limits cover different data, so nothing is duplicated.
- **Ownership.** The EPUB stays the portable original. Reading positions, settings,
  bookmarks, and annotations remain in `library.json`; page geometry stays in the
  page cache.

Measured on a host computer (not the device): importing all 39 Tanach books took
2:43 and produced 208,474,112 bytes (198.8 MiB) of caches, about 569 MiB under the
limit. The 929 chapter files total 310.6 MiB raw and 66.9 MiB compressed; Genesis 1
alone is 3,006,495 bytes raw and 819,762 compressed. Higher compression saves only
about 1%, so the setting stays. Device speed and peak memory still need measuring.

Open reader-side checks for study books:

- Does a commentary note that points to another verse jump to that verse?
- When one note belongs to several verses, is every verse's copy kept?
- Is commentary-source choice remembered per book or per chapter?
- Does a search match inside commentary open the right commentary block?

Talmud-specific reader work is tracked in
`docs/talmud/docs/reader-device-findings.md`.

## Settings shown per mode

Settings show only the controls the current format and mode honor:

| Control | Fit Height | Fit Width | Zoom / Scroll | Text |
| --- | --- | --- | --- | --- |
| Automatic crop | Yes | Yes | Forced uniform | — |
| Slice overlap | — | Yes | — | — |
| Zoom out beyond fit | — | — | Yes | — |
| Typography | — | — | — | Yes |

Reader errors show safe messages with **Retry** and **Home**. Raw parser errors,
internal paths, and stack traces are never shown.

## Tabs

- `ReaderSessionRegistry` owns the ordered list of open tabs and the selected one.
  The same recency tracking that drives suspension decides "most recently read."
- Open tabs and the selection are saved in `library.json`. Restoring tabs at launch
  loads titles and positions only; no document opens until its tab is selected.
- Opening a file that already has a tab switches to it; there are no duplicates.
- **Back** leaves the reader and keeps the tab open in the background. **X** on a
  tab closes it and removes it from the saved order. Closing the current tab lands
  on the most recently read remaining tab, or the file browser if none are left.
- Switching tabs happens inside the single reader screen with no navigation
  transition, matching the no-animation rule. Hidden sessions are suspended.
- **Strip:** a bar above the title bar, shown and hidden with the menu. Large paging
  arrows (greyed out at the ends) flank three equal tabs. Each tab shows a
  single-line title and a boxed X with its own touch target; the current tab is
  inverted. There is no thumbnail and no separate tab-list screen. Exact sizes are
  in [LAYOUT_DESIGN.md](LAYOUT_DESIGN.md).
- **Opening or switching to a suspended tab** shows a first-page preview with a
  static loading indicator and the menu already visible. For PDFs this reuses the
  cached 320 px preview, so it adds no rendering; if none exists, the file name is
  shown instead. EPUB, TXT, and Markdown show the file name on a blank page.
  Switching to an already active tab skips this.
- **Entry points:** opening any file from the browser, and **+ → Tabs**, which opens
  the most recently read tab.
- **Out of scope:** close-others, reopen-last-closed, and an always-visible tab bar
  for wide screens.

## Remaining work

1. Exercise tabs on the device: open and close mixed formats, switch during loading,
   restore after a restart, check portrait and landscape.
2. If a symptom returns with another book, capture preview/sharpen timing or traces.
3. Tune caches or renderer choice only for a repeatable, measured improvement.
4. Reader-side study-book checks (above) and Talmud items.
5. **Tanach build tooling:** `tanach/work/build.py` is one large script with no
   incremental rebuild beyond a single book. Possible improvements: split it into
   smaller parts, verify rebuilt EPUBs against expected checksums automatically, and
   detect Sefaria source changes. Tracked in `docs/tanach/docs/tanach-epub.md`.
