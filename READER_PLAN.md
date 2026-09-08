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
session can survive navigation and tab switches. At most four sessions are
active. App backgrounding, memory pressure, and the active-session cap suspend
sessions, retaining position and metadata while releasing PDFium handles and
page images. Back cancels pending reader work but retains the tab, its session,
and caches. Selecting another tab explicitly suspends the hidden sessions.
Backgrounding releases sessions even when the file browser is on screen.

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
values are starting points. The [HiBreak ADB measurements](DEVICE_VALIDATION_2026-09-02.md)
recorded about 332 MiB total PSS after sequential PDF use and about 148 MiB after
memory-pressure recovery; graphics allocations account for much of the difference.

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

## Tabs

Implemented in version 1.0.3 (build 4). The behavior below is covered by registry,
persistence, widget, and reader integration tests. Device validation of this tab
UI remains separate from the completed version 1.0.2 reader validation.

### Session and persistence model

- `ReaderSessionRegistry` owns the ordered list of open tabs (one `DocRef` per
  tab) and which tab is selected, in addition to the four-active-session cap and
  LRU suspension it already implements. The same recency tracking that drives
  suspension also determines "most recently read" for the close-tab fallback
  below.
- Open tabs and the selected tab persist in `library.json` as a `tabs` block
  alongside `books`. `DocRef` already round-trips to JSON, so this is a thin
  addition, not new plumbing.
- Restoring tabs at launch is metadata-only: titles come from persisted `DocRef`
  values and last positions/percent from `BookState`. No session opens and no
  PDFium handle is created until the user actually switches to that tab.
- Opening a file that already has an open tab switches to that tab; it never
  creates a duplicate.
- The reader's Back control and a tab's Close are different actions. Back
  leaves the reader UI and keeps the tab, and its session, open in the
  background. Switching to another tab suspends the hidden session. Close (the
  X on a tab) evicts the session and removes the tab from persisted order.
- Closing the tab currently being read lands on the most-recently-read
  remaining tab, still inside the reader. It falls back to the file browser
  only when no other tab is open.
- Switching tabs happens inside the single reader route: obtain the target
  session from the registry and rebuild, with no navigation push and no
  transition, matching the zero-animation rule elsewhere in the reader.

### Tab strip

A second horizontal bar sits directly above the existing top bar, inside the
same menu overlay, and shows or hides with it on a centre tap. Version 1.0.4
(build 5) trials the user's compact design sketch: all four control rows are 56
logical pixels high, including borders. The strip fills the screen width and has
no outer padding or gaps between tabs. Edge arrows and small action cells share
a 64-pixel width; rotation and Settings align with the right arrow. Titles use
the same font size and action icons and labels use shared sizing.

Layout is a large left arrow, three equal-width rectangular tabs, and a large
right arrow. The arrows page
the window three tabs at a time and clamp at both ends, the same pattern as
page navigation elsewhere in the app. Opening, selecting, or changing the tab
list reveals the current tab. Arrow paging can browse the other windows without
changing the selected document.

Each tab shows a larger single-line book title, ellipsized to fit, with a boxed
X beside it. There is no thumbnail or format icon. The current tab is shown
inverted (black background, white
text), the same convention used for a selected file-browser row. A small
close control has its own full-height touch target. There is no separate
tab-list screen; the strip is the entire tab UI. The previous square-tab design
remains available in the version 1.0.3 APK for comparison.

The trial also adds full-height vertical dividers between Back, Bookmarks,
document title, and rotation; between the PDF page controls and Settings; and
between all three PDF mode cells. The selected mode fills its entire cell.
Version 1.0.5 (build 6) ensures the tab dividers paint above every tab background,
including unselected tabs and both arrow boundaries. Back, Bookmarks, and
Settings are icon-only, retaining their tooltips and accessibility labels.
Tab paging arrows are grey and disabled when their direction has no further tabs.

Version 1.0.6 (build 7) makes Contents icon-only and changes the return-to-browser
control to a Home icon, including the reader error screen. Home returns to the
file browser while retaining open tabs. The page-count row includes boxed live
clock and battery displays. Search, Contents, and percentage controls move into
an additional equal-cell row when needed to keep the page count legible.

The file browser now uses the same permanent black dividers for Home, clock,
folder title, battery, and the plus button. These columns align with the first,
previous, page-count, next, and last cells in its paging bar. Browser band heights
are preserved. Plus-menu options have equal-height rectangular cells with an
outer border and permanent separators. The browser and reader share one native
battery subscription so opening or closing the reader preserves live updates.

Version 1.0.7 (build 8) replaces fixed reader action widths with proportional
cells. The page-count bar stays in one row: battery 1/9, clock 2/9, page count
3/9, percentage 1/9, Contents 1/9, and Settings 1/9, in that order. Missing
Contents or percentage actions remain disabled in their cells, preserving the
grid. The PDF modes each occupy exactly 1/3, aligned with the page-count cell.
Dividers paint inside cells so differing divider counts do not offset the grid.

The top arrows each use 1/9; three equal tabs share the remaining 7/9. The title
row gives Home, Bookmarks, and rotation 1/9 each and the title 6/9. Text search
moves to an icon in this row and uses 1/9 of the title's space when available.
The file browser retains its previous layout. The new reader layout passes 17
focused widget, integration, and portrait/landscape visual checks.

Version 1.0.8 (build 9) retains ninths only for the bottom status row that aligns
with the three PDF modes. Top reader controls use bounded icon widths of 56px
(48px below 360px screen width), a flexible title, and a wider 96px rotation cell
(88px on narrow screens). The tab strip uses the same bounded arrow widths and
three equal remaining tracks. Permanent dividers and disabled grey arrows remain.

The same visual language now covers all app screens with local layouts:
content-first browser/Apps headers, bounded paging arrows, equal selection cells,
single-column menus, aligned settings groups, fixed-action/flexible-text lists,
search inputs and scope choices, and responsive form/recovery actions. Detailed
dimensions and alternatives are recorded in [LAYOUT_DESIGN.md](LAYOUT_DESIGN.md).
The full suite passes 279 tests including native PDFium stress, with one external
PDF check skipped. Device installation and physical validation remain pending.

Version 1.0.9 (build 10) adds route-aware physical page-button input. Page Up,
Left, and Volume Up invoke previous; Page Down, Right, and Volume Down invoke
next. The reader uses the existing session navigation, preserving PDF ordered
turns, fit-width screenful steps, and viewport steps in Zoom / Scroll. A button
press hides the reader menu. Paginated lists share the same handler. Repeats and
synthesized downs do not navigate; focused editors, inactive routes, loading,
and file-search overlays are excluded. Details and references are in
[BUTTON_SUPPORT.md](BUTTON_SUPPORT.md). Physical B751C verification is pending.

### Opening and loading

Opening a document — a fresh tap in the file browser, switching to a
suspended tab, or the new browser entry point below — shows a medium-
resolution first-page preview immediately, with a small non-animated loading
indicator on top, and the menu overlay, tab strip included, already visible
underneath it. Switching to a tab that is already active skips this
entirely; there is nothing to load.

- PDF: reuses the existing 320-pixel cached coarse preview, stretched to fill
  the screen, rather than rendering a new higher-resolution preview at open
  time. This adds no new PDF rendering or higher-resolution preview work.
- If no cached first-page preview exists, the filename placeholder is used.
  A bounded disk index locates existing preview PNGs without opening PDFium or
  rendering additional pages. The preview remains until initial content is ready.
- EPUB, TXT, and Markdown: a blank page showing the file name, with the same
  loading indicator. These formats have no page-thumbnail system today and
  none is being added for this.

### Entry points

- File browser: opening any readable file behaves as above.
- The file browser's add/action menu gains a "Tabs" item that opens the
  reader directly on the most-recently-read tab, using the same
  opening/loading behavior.

### Out of scope

Close-others and reopen-last-closed are not part of this design; the strip
only supports switch and close-one. A persistent, always-visible tab bar for
wider or landscape devices was considered and dropped in favor of the
overlay-only strip above.

## Remaining work

The pre-tabs implementation phases, ADB device-validation pass, and physical-screen
confirmation are complete. On 2026-09-02 the user reported no ghosting or white
flashes in the observed test conditions. See
[the device report](DEVICE_VALIDATION_2026-09-02.md) for measurements, generated
test documents, and the limits of screenshot-based evidence.

1. Exercise the implemented tabs on the HiBreak: open and close mixed formats,
   switch during loading, restore after process restart, and check the strip in
   portrait and landscape. The previous device validation covers version 1.0.2.
2. If a symptom recurs with another book, capture precise preview/sharpen timing
   or traces as needed to diagnose it.
3. Tune caches or renderer policy only for a repeatable measured improvement.

Version 1.0.3 software verification was **277 passing Flutter tests** with the generated
native PDFium check enabled and clean static analysis. Host tests verify state,
geometry, scheduling, cancellation, caches, and image continuity; they do not
establish what an e-ink panel will display during extreme motion. Tab coverage
includes restart restoration without opening documents, deduplication, MRU close
fallback, pending-open cancellation, background/resume, retained Back behavior,
cached-preview handoff/disposal, and portrait/landscape strip sizing.
The compact version 1.0.4 trial passes 17 targeted UI/integration/screenshot
checks, including equal row heights, aligned action columns, and portrait and
landscape rendering with real fonts. Static analysis is clean.
Version 1.0.6 passes 278 Flutter tests with native PDFium stress enabled (one
external-PDF test skipped), clean static analysis, and four reader/browser visual
checks in portrait and landscape. Coverage includes shared battery updates and
subscription lifetime while the browser and reader coexist. Device trial remains
pending.
