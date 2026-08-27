* this file is ai generated, so skepticism is allowed and even encouraged 

# E-Ink Reader — Implementation Blueprint

A native PDF / EPUB / TXT / Markdown reader inside `eink_launcher`.

**Target device:** Bigme B751C (7" Android e-ink). The device manages its own e-ink
refresh modes and contrast, so no vendor refresh SDK is used. Distribution is
personal sideload only.

**Environment (verified):** Flutter 3.47.1 stable, Dart 3.13.1, `compileSdk = 37`.
Native-asset build hooks are already active in this project's build pipeline.

---

## 0. Decisions locked in

| Area | Decision |
|---|---|
| PDF engine | `pdfrx` (PDFium, MIT). Use the **document API**, not its viewer widget. |
| EPUB engine | `epubx` for container/OPF/TOC parsing + `html` for XHTML + **our own paginator**. |
| Formats | PDF, EPUB, TXT, Markdown. No CBZ, no MOBI. |
| Page turns | Invisible tap zones (left = back, right = forward, centre = menu) **+** swipe. |
| RTL | Right side is **always** forward, in every book. Text itself is still bidi-correct. |
| EPUB pagination | Exact: block packing with mid-paragraph splitting at real line boundaries. |
| PDF display | Four modes, remembered **per document**: fit-height, fit-width (split into sub-screens), **continuous vertical scroll**, free pinch-zoom. |
| PDF margins | Auto-crop **on by default**, per-document toggle. Per-page in the tap-driven modes; **document-uniform** in continuous scroll — see §4.1. |
| Scroll physics | Momentum/fling **off by default** (drag moves, release stops). Tap zones still jump one screen. Momentum is a setting. |
| Reading chrome | None. Full-bleed page; centre tap reveals a menu overlay. |
| Typography | Font size, line height, margins, justify + hyphenation, paragraph style, publisher-CSS toggle. |
| Paragraph default | Blank-line spacing (not first-line indent). |
| Publisher CSS default | Honour a **safe subset** (bold / italic / headings / alignment); ignore fonts, sizes, colours. |
| Fonts | Bundle several Latin + several Hebrew faces, user-selectable, per book. |
| Storage | One atomic `library.json` in app documents dir. |
| Entry point | File browser only. Tapping a readable file opens the reader. |
| Escape hatch | "Open with…" in the long-press selection menu → `OpenFilex`. |
| In-document features | TOC + jump to page/percent, bookmarks, text search (**EPUB only**). |
| Not building | Highlights, notes, dictionary, TTS, PDF text search. |
| Rotation | Manual toggle in the reader menu only. **Never** sensor-driven. Always single-column. |
| Android intents | Designed for, but wired up in a later phase. |
| Sequence | Shell + PDF → Continuous Scroll → EPUB → TXT/MD → TOC/bookmarks/search → Polish. |
| Future | Tab system — architecture below is built to accept it. |

---

## 1. Why the architecture looks the way it does

Three constraints drive every structural choice.

**A. Tabs are coming.** Reader state therefore cannot live inside a `Navigator`
route that is destroyed on pop. It lives in a `ReaderSessionRegistry` — a
long-lived `docId → ReaderSession` map — and screens are pure views over it.
This is the same controller pattern `FileBrowserController` already uses, just
with a longer lifetime. Every session implements a **suspend/resume contract**:
when hidden, it frees page bitmaps and closes its PDFium handle but keeps
position, TOC and pagination results. Without this, four open PDFs will OOM the
device.

**B. Positions must survive everything.** A stored position is never a page
number. Page numbers change when you change font size, margins, rotation, or
crop mode. Positions are *logical*:

- PDF → `(pageIndex, withinPage)`, where `withinPage` is a fraction in `[0, 1)`
- EPUB/TXT/MD → `(spineIndex, blockIndex, charOffset)`

The PDF fraction is what lets all four view modes share one position type:
fit-height always stores `0.0`; fit-width-split stores `0.0` or `~0.5`;
continuous scroll stores wherever the viewport top actually sits; free-zoom
stores the pan offset's vertical fraction. Because they agree on a
representation, **switching view mode mid-document keeps your place** instead of
dropping you at the top of the current page.

Percent-read is derived from cumulative character counts, computed once at parse
and cached.

**C. Documents must be identifiable after being moved.** `docId` is
`sha1(first 64 KB of file + fileSize)` — not the path. Rename or move a book and
your position, bookmarks and per-book settings follow it. The last-known path is
stored alongside, for display only.

---

## 2. File layout

The launcher's existing flat `lib/{models,services,controllers,screens,widgets}`
stays untouched. The reader is a self-contained module under `lib/reader/` using
the same internal folder names, so the convention is consistent but the two
features don't tangle.

```
lib/
  constants.dart                          MODIFY  add reader constants
  main.dart                               MODIFY  pdfrxFlutterInitialize()
  screens/file_browser_screen.dart        MODIFY  route readable files; "Open with…"
  reader/
    models/
      doc_ref.dart                        document identity + format enum
      reading_position.dart               logical position (sealed: Pdf / Text)
      reader_settings.dart                typography + view settings, JSON round-trip
      bookmark.dart                       user bookmark model
      book_state.dart                     one document's persisted record
      toc_entry.dart                      table of contents entry item
      content_block.dart                  THE layout primitive (blocks + inline runs)
      laid_out_page.dart                  a page = ordered list of BlockSlice
      parsed_book.dart                    spine items, resources, TOC, char counts
    services/
      doc_identity_service.dart           sha1 fingerprint
      book_store_service.dart             library.json, atomic write, debounced
      pagination_cache_service.dart       disk cache keyed by geometry+typography
      page_bitmap_cache.dart              in-memory LRU of rendered PDF pages
      pdf_document_service.dart           pdfrx wrapper: open / render / outline
      pdf_crop_service.dart               ink-bbox detection (isolate)
      epub_parser_service.dart            epubx wrapper → ParsedBook (isolate)
      html_block_parser.dart              XHTML → List<ContentBlock> (isolate)
      text_block_parser.dart              .txt and .md → List<ContentBlock>
      bidi_service.dart                   per-block direction detection
      hyphenation_service.dart            hyphenatorx wrapper, Latin only
      epub_paginator_service.dart         blocks + geometry → pages (UI isolate)
      text_search_service.dart            EPUB search, nikud-insensitive
    controllers/
      reader_session.dart                 abstract base
      pdf_reader_session.dart             PDF-specific session controller
      text_reader_session.dart            EPUB + TXT + MD share this
      reader_session_registry.dart        docId → session, LRU suspend
    screens/
      reader_screen.dart                  format-agnostic shell
      reader_settings_screen.dart         typography and layout settings dialog/screen
      reader_toc_screen.dart              table of contents navigation screen
      reader_bookmarks_screen.dart        saved bookmarks screen
      reader_search_screen.dart           in-book text search screen (EPUB)
    widgets/
      tap_zone_layer.dart                 invisible zones + swipe
      reader_menu_overlay.dart            in-book floating control overlay
      pdf_page_view.dart                  single/split PDF page renderer
      text_page_view.dart                 renders a LaidOutPage
      block_slice_view.dart               the clip-and-offset renderer
assets/fonts/                             bundled Latin + Hebrew faces
```

---

## 3. Dependencies to add

```yaml
dependencies:
  pdfrx: ^2.4.7          # PDFium, MIT. PdfDocument.openFile / PdfPage.render / outline
  epubx: ^4.0.0          # EPUB container + OPF + NCX + nav parsing, MIT
  html: ^0.15.4          # XHTML → DOM
  markdown: ^7.2.2       # .md → HTML, then reuse the HTML block parser
  path_provider: ^2.1.4  # app documents dir for library.json
  crypto: ^3.0.5         # sha1 for docId
  hyphenatorx: ^1.0.0    # TeX hyphenation patterns, pure Dart
```

---

## 4. The two rendering pipelines

### 4.1 PDF

```
file path
  → PdfDocument.openFile()                        pdfrx / PDFium
  → per page: crop rect?                          pdf_crop_service (cached)
  → PdfPage.render(width, height)  → RGBA         UI isolate
  → ui.Image → RawImage widget                    pdf_page_view
```

**Crop detection.** Render the page small (~200 px wide, ~5–15 ms), then ship the
**byte array** to a background isolate to scan for the bounding box of non-white
pixels (luminance < 245), with a minimum-run filter so scanner specks and stray
marks don't defeat the crop. Detection runs off the UI isolate; PDFium rendering
stays *on* it — FFI handles are not safely shared across isolates. Crop rects are
cached in memory and persisted per document as a compact array.

Crop has **two strategies**, chosen by view mode, not by the user:

- *Per-page* (the tap-driven modes) — every page gets its own crop rect,
  detected lazily as you reach it. Maximum text size on every page.
- *Document-uniform* (continuous scroll) — sample ~10 pages spread through the
  document, take the union of their ink boxes, apply it everywhere. One cheap
  up-front pass, and page geometry is fully known before any rendering. See
  §4.1.1 for why continuous scroll requires this.

**The four fit modes.**

- **fit-height** — the cropped page scaled to fit the screen height. One page =
  one screen. Simplest, unambiguous position.
- **fit-width** — scaled so cropped width equals screen width. The result is
  taller than the screen, so it is split into `ceil(h / screenH)` sub-screens
  (usually 2) with a **6 % overlap** by default, so a line straddling the split is
  fully readable in both halves.
- **continuous scroll** — one uninterrupted vertical strip of pages at
  fit-width. See §4.1.1.
- **free-zoom** — `InteractiveViewer` over a higher-resolution render. Tap zones
  shrink to 12 %-width screen *edges* so the middle stays free for panning.

#### 4.1.1 Continuous scroll mode

A `ListView.builder` of variable-height page tiles inside a `CustomScrollView`,
each tile sized to `screenWidth × (croppedAspect × screenWidth)`.

**Why this mode forces uniform crop.** A scrollable needs each tile's extent
before it can compute total scroll extent and honour `jumpTo`. Per-page crop
rects are only known *after* that page has been rendered, so with per-page crop
the tile heights would keep changing as you scrolled — the content under your
finger would shift and the scrollbar would lurch. Uniform crop makes every tile
height derivable from `PdfPage.width/height` (which pdfrx exposes from the
document structure without rendering anything) times one shared crop ratio. So
in continuous mode, crop becomes document-uniform automatically, and the reader
menu says so rather than silently changing behaviour.

**Exact extents.** With heights known up front, use `ListView.builder`'s
`itemExtentBuilder` to return each page's height. That gives an exact total
scroll extent, no estimation, no jumping, and O(1) `jumpTo` for any page — which
is what makes TOC navigation and jump-to-page work correctly in this mode.

**Physics — the important part for e-ink.** Fling scrolling is the single worst
thing you can do to an e-ink panel: dozens of full-frame repaints chasing a
decaying velocity, each one ghosting over the last. So the default is a custom
`ScrollPhysics` subclass that overrides `createBallisticSimulation` to return
`null`: dragging moves the page, releasing stops it dead. No momentum, no
overscroll bounce. Momentum is available as a setting for anyone who wants it,
off by default.

**Tap zones still work.** Left/right taps `jumpTo` one viewport height minus the
6 % overlap — never `animateTo`, which would smooth-scroll and reintroduce
exactly the repaint storm we just eliminated. Centre still toggles the menu. So
this mode gives you the page-turn rhythm you already have *plus* free dragging
when a figure or table straddles a boundary, which is the actual reason to want
continuous scroll.

**Tile rendering.** Render requests are queued for the visible tiles ± 2, and
cancelled when a tile scrolls out of the window. A tile with no bitmap yet paints
a plain white box of the correct size — never a spinner, since spinners animate.
Because extents are known, an unrendered tile costs nothing and leaves layout
untouched, so nothing shifts when its bitmap arrives.

**Current page.** In this mode "current page" is whichever page occupies the most
viewport area, computed from the scroll offset against the cumulative height
table. That feeds the menu overlay, percent-read, and position persistence.

**Scope boundary:** continuous scroll is fit-width only, with no pinch-zoom.
Combining a nested scrollable with an `InteractiveViewer` means two-axis panning
and gesture-arena conflicts for very little gain — free-zoom mode already covers
"I need to magnify this one page".

**Resolution and memory.** Render at native device pixels, capped at 2048 px on
the long edge. One page at ~1264×1680 RGBA ≈ 8.5 MB, so the LRU cache holds 3–5
pages ≈ 25–40 MB. After displaying page N, pre-render N+1 and N−1 in the
background — this is what makes turns feel instant on e-ink.

### 4.2 EPUB / TXT / Markdown

```
.epub → epubx        → spine items (HTML strings) + resources + TOC
.md   → markdown pkg → HTML                        ┐
.txt  → blank-line split                           ┴→ same block parser
  → html pkg DOM walk → List<ContentBlock>          isolate, per chapter
  → direction detection per block                   bidi_service
  → soft-hyphen insertion (Latin runs only)         hyphenation_service
  → paginate: TextPainter measure + block packing   UI isolate
  → LaidOutPage(List<BlockSlice>)
  → render each slice via clip-and-offset           block_slice_view
```

---

## 5. The reader shell

`ReaderScreen` knows nothing about PDF or EPUB. It asks the session for a page
count, a current page, and a widget:

```dart
abstract class ReaderSession extends ChangeNotifier {
  DocRef get doc;
  bool get isReady;
  String? get error;
  int get pageCount;            // may grow while background pagination runs
  int get currentPage;
  double get percent;
  ReadingPosition get position; // logical — this is what gets persisted
  List<TocEntry> get toc;
  ReaderSettings get settings;

  Future<void> open();
  Future<void> nextPage();
  Future<void> prevPage();
  Future<void> goToPage(int page);
  Future<void> goToToc(TocEntry entry);
  Future<void> goToPercent(double pct);
  Future<void> applySettings(ReaderSettings s);

  Widget buildPage(BuildContext context, Size viewport);

  void suspend();               // free bitmaps, close native handles, keep position
  Future<void> resume();
}
```

---

## 6. Settings model

Global defaults plus per-document overrides, both living in `library.json`.

```dart
class ReaderSettings {
  // text formats
  String latinFontFamily;      // Literata | EB Garamond | Inter
  String hebrewFontFamily;     // Frank Ruhl Libre | Noto Serif Hebrew | David Libre | Heebo
  int    fontSizeStep;         // 0..7, mapped to pt via a table
  double lineHeight;           // 1.2 .. 2.0
  int    marginStep;           // tight | normal | wide | extra
  bool   justify;
  bool   hyphenate;
  ParagraphMode paragraphMode; // blankLine (default) | firstLineIndent
  bool   honorPublisherCss;    // default true — safe subset

  // pdf
  PdfFitMode fitMode;          // fitHeight | fitWidth | continuousScroll | freeZoom
  bool   autoCrop;             // default true
  double splitOverlap;         // default 0.06 — also the tap-jump overlap in scroll mode
  bool   scrollMomentum;       // default false — fling is brutal on e-ink

  // shared
  bool   landscape;            // manual toggle only
  int    flashEveryNTurns;     // 0 = off
}
```

---

## 7. Changes to existing files

| File | Change |
|---|---|
| `pubspec.yaml` | Add dependencies (`pdfrx`, `epubx`, `html`, `markdown`, `path_provider`, `crypto`, `hyphenatorx`); declare fonts assets. |
| `lib/main.dart` | `await pdfrxFlutterInitialize()` after `ensureInitialized()`. |
| `lib/constants.dart` | Add `kReadableExtensions`, tap zone ratios, font size tables, crop constants. |
| `lib/screens/file_browser_screen.dart` | Intercept readable files on tap → push `ReaderScreen`; add "Open with…" in selection bar. |

---

## 8. Build Sequence & Actionable Steps

### Phase 0 — De-risk & Native Verification
**Objective:** Prove `pdfrx` and PDFium build and render cleanly on target hardware.
- [x] **Step 0.1: Add dependencies & init pdfrx**
  - Add `pdfrx: ^2.4.7`, `path_provider: ^2.1.4`, `crypto: ^3.0.5` to `pubspec.yaml`.
  - Add `await pdfrxFlutterInitialize();` in `lib/main.dart`.
  - Add `kReadableExtensions` and reader constants in `lib/constants.dart`.
- [ ] **Step 0.2: Smoke test PDF render on device**
  - Create minimal verification widget/test calling `PdfDocument.openFile` and rendering page 0.
  - Run release build on the Bigme B751C device to confirm native asset loading.
  - Automated service coverage and an opt-in native PDFium smoke test are now present; the Bigme release-device run is still required.

---

### Phase 1 — Core Architecture & Tap-Driven PDF Reader
**Objective:** End-to-end PDF reading with tap zones, auto-crop, settings, and persistence.

- [x] **Step 1.1: Models & Document Identity**
  - Create `lib/reader/models/doc_ref.dart` (format enum, document reference).
  - Create `lib/reader/models/reading_position.dart` (sealed logical position: `PdfReadingPosition`, `TextReadingPosition`).
  - Create `lib/reader/models/reader_settings.dart` (JSON serialisation, enums for fit mode, font steps, margins).
  - Create `lib/reader/models/bookmark.dart` and `lib/reader/models/toc_entry.dart`.
  - Create `lib/reader/models/book_state.dart` (per-book persisted state).
  - Create `lib/reader/services/doc_identity_service.dart` (`sha1(first 64KB + fileSize)`).
  - Add unit tests in `test/reader/doc_identity_service_test.dart`.

- [x] **Step 1.2: Persistence Storage (`library.json`)**
  - Create `lib/reader/services/book_store_service.dart`:
    - Atomic JSON disk write (write to `.tmp` then rename).
    - In-memory cache + 2-second debounced save.
    - Global defaults + per-document override lookup.
  - Add unit tests in `test/reader/book_store_service_test.dart`.

- [x] **Step 1.3: PDF Services & Auto-Crop**
  - Create `lib/reader/services/pdf_document_service.dart` (pdfrx open, page count, outline parser).
  - Create `lib/reader/services/page_bitmap_cache.dart` (LRU memory cache with 25–40MB budget).
  - Create `lib/reader/services/pdf_crop_service.dart` (isolate-backed ink bbox detection, minimum-run filtering).
  - Add unit tests in `test/reader/pdf_crop_service_test.dart`.

- [ ] **Step 1.4: Session Management & Suspend Contract**
  - Create `lib/reader/controllers/reader_session.dart` (abstract session base with lifecycle contract).
  - Create `lib/reader/controllers/pdf_reader_session.dart`:
    - Implement page navigation (`nextPage`, `prevPage`, `goToPage`, `goToPercent`).
    - Sub-screen calculations for fit-width (with 6% overlap).
    - Background pre-fetching for pages $N+1$ and $N-1$.
    - Logical position mapping.
  - Create `lib/reader/controllers/reader_session_registry.dart` (singleton session pool, max 4 active, auto-suspend).

- [ ] **Step 1.5: UI Layer (Tap Zones, Menu, PDF View)**
  - Create `lib/reader/widgets/tap_zone_layer.dart` (30% left / 40% centre / 30% right zones + swipe handling).
  - Create `lib/reader/widgets/pdf_page_view.dart` (handles fit-height, fit-width sub-screen slices, and free-zoom `InteractiveViewer`).
  - Create `lib/reader/widgets/reader_menu_overlay.dart` (top/bottom bars: page jump, fit mode toggle, crop toggle, rotation, settings entry).
  - Create `lib/reader/screens/reader_settings_screen.dart` (discrete buttons for settings).

- [ ] **Step 1.6: Reader Shell Screen & Lifecycle Hooks**
  - Create `lib/reader/screens/reader_screen.dart` (format-agnostic host with `AppLifecycleListener` position saving).
  - Handle manual landscape/portrait orientation locking.

- [ ] **Step 1.7: Wire File Browser Integration**
  - Update `lib/screens/file_browser_screen.dart`:
    - On file tap: if extension is in `kReadableExtensions`, push `ReaderScreen` via `noTransitionRoute`.
    - In selection action bar: add "Open with…" button using `OpenFilex` when 1 file is selected.
  - Update `lib/controllers/file_browser_controller.dart` if needed.

- [ ] **Step 1.8: Phase 1 Verification**
  - Test on device: open PDF, navigate pages via tap and swipe, switch fit modes (height/width/zoom), toggle auto-crop, change orientation, kill app, verify position restores exactly.

---

### Phase 1b — Continuous Scroll Mode (PDF)
**Objective:** Add continuous vertical scrolling without unneeded screen churn or layout shifts.

- [ ] **Step 1b.1: Uniform Crop & Cumulative Heights Table**
  - Extend `pdf_crop_service.dart` with document-uniform crop sampling (~10 sample pages).
  - Add cumulative height table calculation to `pdf_reader_session.dart`.
  - Add `NoMomentumScrollPhysics` (stops dead on release, no ballistic deceleration).

- [ ] **Step 1b.2: Scrollable PDF View**
  - Implement continuous scroll branch in `pdf_page_view.dart` using `CustomScrollView` + `ListView.builder` with `itemExtentBuilder`.
  - Wire tap zones to jump one viewport height minus overlap.
  - Map scroll offset ↔ `PdfReadingPosition` bidirectionally.

- [ ] **Step 1b.3: Phase 1b Verification**
  - Verify continuous mode on device: dragging stops without momentum ghosting, tap jumps exactly one screen, TOC/percent jumps land accurately, switching fit modes preserves position.

---

### Phase 2 — EPUB Engine & Exact Pagination
**Objective:** High-performance EPUB parsing, bidi paragraph layout, and text pagination.

- [ ] **Step 2.1: Dependencies & Font Assets**
  - Add `epubx: ^4.0.0`, `html: ^0.15.4`, `hyphenatorx: ^1.0.0` to `pubspec.yaml`.
  - Bundle fonts in `assets/fonts/` (Literata, EB Garamond, Inter, Frank Ruhl Libre, Noto Serif Hebrew, Heebo).
  - Declare font families in `pubspec.yaml`.

- [ ] **Step 2.2: Block Model & Parsing Services**
  - Create `lib/reader/models/content_block.dart` (`ContentBlock`, `InlineRun`, `BlockType`).
  - Create `lib/reader/models/laid_out_page.dart` (`LaidOutPage`, `BlockSlice`).
  - Create `lib/reader/models/parsed_book.dart`.
  - Create `lib/reader/services/bidi_service.dart` (Unicode P2/P3 strong character scan).
  - Create `lib/reader/services/hyphenation_service.dart` (soft hyphen insertion for Latin text).
  - Create `lib/reader/services/html_block_parser.dart` (isolate-backed XHTML DOM walk).
  - Create `lib/reader/services/epub_parser_service.dart` (container, manifest, spine extraction).
  - Add unit tests for parser and bidi logic in `test/reader/`.

- [ ] **Step 2.3: Paginator & Disk Cache**
  - Create `lib/reader/services/pagination_cache_service.dart` (keyed by docId, spineIndex, geometry, typography).
  - Create `lib/reader/services/epub_paginator_service.dart`:
    - Immediate UI-isolate pagination for current chapter.
    - Progressive time-sliced background pagination for remaining chapters.
    - Widow/orphan line handling.
  - Add paginator unit tests in `test/reader/epub_paginator_service_test.dart`.

- [ ] **Step 2.4: Text Session Controller & Widgets**
  - Create `lib/reader/controllers/text_reader_session.dart`.
  - Create `lib/reader/widgets/block_slice_view.dart` (clip-and-translate slice renderer).
  - Create `lib/reader/widgets/text_page_view.dart` (renders `LaidOutPage`).

- [ ] **Step 2.5: Typography Settings UI**
  - Wire font picker, font size steps, line spacing, margins, justification, hyphenation, and paragraph mode into `reader_settings_screen.dart`.

- [ ] **Step 2.6: Phase 2 Verification**
  - Verify on device: open English, Hebrew, and mixed bilingual EPUBs; verify paragraph directions, font rendering, flawless page splits without clipped lines, and fast resize re-pagination.

---

### Phase 3 — Plain Text & Markdown Support
**Objective:** Support `.txt` and `.md` using the unified text pipeline.

- [ ] **Step 3.1: Dependencies & Text Block Parser**
  - Add `markdown: ^7.2.2` to `pubspec.yaml`.
  - Create `lib/reader/services/text_block_parser.dart`:
    - Encoding detection (UTF-8, UTF-16, Windows-1255 for Hebrew).
    - Plain text blank-line paragraph chunking.
    - Markdown → HTML conversion → `html_block_parser`.

- [ ] **Step 3.2: Integrate into Text Session**
  - Wire `.txt` and `.md` formats into `TextReaderSession` and `DocIdentityService`.
  - Ensure character offset tracking and persistence match EPUB.

- [ ] **Step 3.3: Phase 3 Verification**
  - Test `.txt` and `.md` files on device with typography changes and bookmarking.

---

### Phase 4 — Navigation, Bookmarks & In-Book Search
**Objective:** Rich in-document navigation for all formats.

- [ ] **Step 4.1: Table of Contents Screen**
  - Create `lib/reader/screens/reader_toc_screen.dart`.
  - Wire EPUB NCX/nav hierarchy and PDF outline into TOC screen.
  - Implement direct jump from TOC entries in both PDF and Text sessions.

- [ ] **Step 4.2: Page & Percent Jump Dialogs**
  - Add discrete number-input jump-to-page dialog.
  - Add percent jump slider/buttons to menu overlay.

- [ ] **Step 4.3: Bookmarks Management**
  - Create `lib/reader/screens/reader_bookmarks_screen.dart`.
  - Allow adding, viewing, navigating, and deleting bookmarks.

- [ ] **Step 4.4: In-Book Text Search (EPUB)**
  - Create `lib/reader/services/text_search_service.dart` (nikud-insensitive Hebrew normalisation, isolate-backed).
  - Create `lib/reader/screens/reader_search_screen.dart` with paginated search results.

- [ ] **Step 4.5: Phase 4 Verification**
  - Test chapter jumping, bookmark round-trips across font size changes, and Hebrew search queries with/without vowel points.

---

### Phase 5 — Polish, E-Ink Optimisations & Edge Cases
**Objective:** Final hardening, memory management, and display tuning.

- [ ] **Step 5.1: Ghost-Clearing Flash**
  - Add full-black/full-white flash widget triggered every $N$ page turns (configurable setting, default off).
- [ ] **Step 5.2: Error Boundaries & Fallback UI**
  - Handle corrupt PDFs, malformed EPUBs, missing files, and memory warnings gracefully.
- [ ] **Step 5.3: Update Documentation & Tests**
  - Update `README.md` with new file listings and architectural details.
  - Run full test suite (`flutter test`, `flutter analyze`).

---

## 9. Tests

- `doc_identity_service_test.dart` — same file at two paths yields same id; modified file yields new id.
- `book_store_service_test.dart` — JSON round-trip; atomic write robustness; corrupt file recovery.
- `bidi_service_test.dart` — English, Hebrew, Hebrew-with-nikud, mixed RTL/LTR, numbers, punctuation.
- `html_block_parser_test.dart` — nested lists, blockquotes, inline tags, images, safe CSS filtering.
- `epub_paginator_service_test.dart` — block packing, line splits, widow/orphan protection.
- `pdf_crop_service_test.dart` — bbox bounding math, noise filtering, uniform crop sampling.
- `reading_position_test.dart` — JSON round-trips, cross-view-mode conversion consistency.
- `continuous_scroll_test.dart` — offset-to-page and page-to-offset mapping correctness.
- `tap_zone_layer_test.dart` — tap-zone callback boundaries and direction invariants.

---

## 10. Known risks & Mitigations

1. **`epubx` staleness:** Validate against real library in Phase 2 Step 2.1. Fallback: custom 300-line `archive` + `xml` parser.
2. **UI-isolate pagination load:** Mitigated via current-chapter priority pagination + progressive frame slicing + disk caching.
3. **Hebrew fonts & nikud:** Multiple bundled OFL fonts selectable per-book.
4. **Memory pressure:** Hard 4-session cap + LRU bitmap cache (25–40MB max) + session suspend contract.
5. **Continuous scroll ghosting:** Momentum disabled by default + discrete tap-jump support.
