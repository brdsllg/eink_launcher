# Reader design and remaining work

The built-in reader supports PDF, EPUB, TXT, and Markdown. Most of the original
implementation plan is complete; this document now records current behavior,
architectural constraints, and work that still needs device evidence.

The app has been manually exercised on a Bigme HiBreak running Android 14. See
[BIGME_TEST_LOG.md](BIGME_TEST_LOG.md) for the original observations and
[PDF_RESPONSIVENESS.md](PDF_RESPONSIVENESS.md) for the implemented response work.

## Product decisions

| Area | Current decision |
| --- | --- |
| PDF engine | Use `pdfrx`/PDFium through its document API and render app-owned images. |
| Text engines | Parse EPUB directly with `archive`, `xml`, and `html`; use one custom paginator for EPUB, TXT, and Markdown. |
| Formats | PDF, EPUB, TXT, and Markdown. CBZ and MOBI are out of scope. |
| Page controls | Three equal tap zones: left back, centre menu, right forward. Right is always forward, including RTL books. |
| Gestures | Fit modes and text allow page swipes. PDF Zoom / Scroll reserves drag and pinch gestures for the document surface. |
| Chrome | Reading is full-bleed. A centre tap toggles the menu. |
| Orientation | Manual portrait/landscape toggle only; no sensor rotation. |
| Persistence | Store global defaults and per-document state in one atomic `library.json`. |
| Entry point | Open readable files from the file browser. Keep **Open with** as an escape hatch. |
| Search | EPUB, TXT, and Markdown only. PDF text search is out of scope. |
| Not planned | Highlights, notes, dictionary, TTS, and DRM bypass. |

## Session and position model

`ReaderSessionRegistry` keeps document sessions outside individual routes so a
session can survive navigation and later support tabs. At most four sessions are
active. Hidden sessions suspend: they retain position and parsed metadata while
releasing PDFium handles and page images. Memory pressure suspends sessions and
clears disposable image data.

Positions are logical rather than display page numbers:

- PDF: `(pageIndex, withinPage)`, where `withinPage` is a fraction from 0 to 1.
- Text: `(spineIndex, blockIndex, charOffset)`.

This allows mode, crop, font, margin, and orientation changes to keep the same
reading location. A document ID is derived from the first 64 KiB plus file size,
so state usually follows a file after it is renamed or moved.

`BookStoreService` writes state atomically and debounces ordinary saves. If
`library.json` is malformed, it preserves up to three full corrupt backups before
replacement. If preservation is unsafe, saving is disabled for that launch and
the reader explains why.

## PDF pipeline

PDFium initializes lazily on the first real PDF open. Missing files and injected
test openers do not start it; concurrent opens share the same initialization.

PDF rendering follows this path:

```text
PDF file
  -> logical page/crop geometry
  -> bounded priority scheduler
  -> PDFium crop, preview, or detail render
  -> caller-owned ui.Image
  -> fit page or continuous tiled view
```

Only one native render/crop operation is admitted at a time. Visible coverage
has priority over detail and speculative work. Matching pending requests share
work, obsolete queued demand is cancelled, and rapid fit-mode navigation is
applied in input order. An already running synchronous PDFium call must still
finish before the next one starts.

### Display modes

- **Fit Height** scales a cropped whole page to the screen height. One page is one
  screen.
- **Fit Width** scales to screen width and divides a tall page into overlapping
  screen-height slices. The default overlap is 6%.
- **Zoom / Scroll** is a continuous vertical document with two-axis pan, pinch
  zoom, and Android-style clamped momentum. It uses app-owned scale and origin
  geometry rather than `InteractiveViewer`.

Fit Height and Fit Width can use a crop calculated per page. Zoom / Scroll uses
one document-uniform crop sampled across the book, because stable crop geometry is
required to calculate exact page extents before rendering.

### Zoom / Scroll behavior

- Page extents and logical position mapping are exact, so images arriving later
  do not shift the document.
- Zoom is re-rasterized through PDFium on bounded two-dimensional tiles instead of
  magnifying one page texture.
- Existing useful detail remains during movement and density changes. Sharp
  visible tiles replace it as a group after a 200 ms idle interval.
- Small whole-page previews cover visible and nearby pages. The look-ahead grows
  with signed scroll velocity up to four screens and 16 page requests, then
  returns to one screen when movement settles.
- A 64 MiB disk LRU stores 320-pixel coarse previews by document identity and
  geometry. Corrupt or partial entries are removed. Idle warming yields to visible
  work and stops on touch, suspension, backgrounding, or memory pressure.
- Raw finger-down stops an active fling immediately. Pan or pinch can continue
  from that stopped position.
- Left/right taps move by one currently visible viewport height. The centre tap
  still opens the menu.

First-time pages still require PDFium work. Extreme minimum-zoom scrolling can
cross several unseen pages per second and expose white while the first preview is
created. The persistent cache is intended to make prepared and revisited pages
immediate; it cannot pre-render every page of every new book.

### PDF memory policy

Each session chooses its retained bitmap budget lazily from Android's normal heap
class: 25%, clamped to 4–128 MiB, with a 32 MiB fallback. Visible widget images,
one active native render, PDFium data, and graphics allocations sit outside that
budget. Oversized images bypass the LRU and remain owned by their caller. These
values are safe starting points and still need HiBreak memory measurements.

## Text pipeline

EPUB, TXT, and Markdown converge on semantic blocks and one pagination path:

```text
EPUB XHTML / Markdown HTML / decoded TXT
  -> semantic blocks and inline styles
  -> block direction and optional Latin hyphenation
  -> TextPainter line measurement
  -> exact block slices and paginated pages
```

Parsing uses background isolates where practical. The UI isolate performs final
font measurement because it owns Flutter text layout. Pagination caches are keyed
by document identity, chapter, viewport, and typography.

The text reader supports:

- EPUB 2 NCX and EPUB 3 navigation hierarchies;
- UTF-8, UTF-16, and Windows-1255 TXT input;
- mixed English/Hebrew paragraphs and Hebrew marks;
- bundled selectable Latin and Hebrew fonts;
- font size, line height, margins, justification, Latin hyphenation, paragraph
  spacing/indent, and a safe publisher-style subset;
- logical bookmarks, TOC/percent jumps, and text search with Hebrew-mark
  normalization.

Publisher fonts, sizes, and colors are ignored. Supported font obfuscation is
treated as an unused publisher font; encrypted content produces a clear DRM error.

## UI and settings rules

The menu contains navigation, page/percent jump, TOC, bookmarks, PDF mode,
orientation, and settings. Settings only show controls honored by the active
format and mode:

| Control | Fit Height | Fit Width | Zoom / Scroll | Text |
| --- | --- | --- | --- | --- |
| Automatic crop | Yes | Yes | Forced uniform | — |
| Slice overlap | — | Yes | — | — |
| Zoom out beyond fit | — | — | Yes | — |
| Typography | — | — | — | Yes |

Reader errors show safe messages with Retry and Back controls. Raw parser errors,
file paths from internals, and stack traces are not displayed to the user.

## Future tabs

Tabs are not implemented. When they are added:

1. Put a compact tab-count button in the reader menu. On a narrow HiBreak screen,
   it should open a paginated document list instead of permanently consuming a
   row with visible tabs.
2. Show document name and current page/percentage, with one-tap switching, Close,
   Close others, and Reopen last closed.
3. Persist open-tab order and the selected tab. Restore sessions lazily after
   restart so hidden PDFs do not all open native handles at startup.
4. Skip missing or unreadable files with a clear warning and keep the four-active-
   session limit.
5. Consider an optional visible tab bar only for wider devices.

## Remaining work

The implementation phases are complete except for device confirmation and
measurement. The next useful checks are:

1. Compare first and second fast-scroll passes in version 1.0.2 using one vector
   PDF and one scanned PDF.
2. Confirm zoom-release continuity, pinch repetition, direction reversal, and
   finger-down momentum stopping on the HiBreak.
3. Verify fit-mode navigation, text layout, search, bookmarks, position restore,
   rotation, and mode changes with representative real documents.
4. Record Android heap class and native/graphics/total PSS at idle, after opening
   PDFs, during repeated turns/zoom/flings, and after leaving the reader.
5. Tune preview, cache, or renderer policy only if those measurements identify a
   repeatable problem.

Current software verification is **240 passing Flutter tests** with the generated
native PDFium check enabled and clean static analysis. Host tests verify state,
geometry, scheduling, cancellation, caches, and image continuity; they do not
establish what an e-ink panel will display during extreme motion.
