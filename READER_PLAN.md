* this file is ai generated, so skepticism is allowed and even encouraged 

# E-Ink Reader — Implementation Blueprint

A native PDF / EPUB / TXT / Markdown reader inside `eink_launcher`.

**Target device:** Bigme B751C (7" Android e-ink, roughly 30 fps panel refresh).
The device manages its own e-ink refresh modes and contrast, so no vendor refresh
SDK is used. Distribution is personal sideload only.

**Environment (verified):** Flutter 3.47.1 stable, Dart 3.13.1, `compileSdk = 37`.
Native-asset build hooks are already active in this project's build pipeline.

**Latest device findings (2026-08-31):** the current manual run is on a Bigme
**HiBreak, Android 14**, not the B751C. The user reports all eight manual tests
complete, with all other checks passing apart from three open PDF issues: rapid
next-page taps leave Fit Height / Fit Width unresponsive; Zoom / Scroll taps and
fast scrolling reach unloaded white pages; zoom release causes a brief white
interval (usually just under one second), followed by content loading segment by
segment. All PDFs tested are affected, including small files. See
[the device test log](BIGME_TEST_LOG.md). PDF issue resolution and advanced device
profiling/fault-injection checks remain outstanding. No fix is included here.

---

## 0. Decisions locked in

| Area | Decision |
|---|---|
| PDF engine | `pdfrx` (PDFium, MIT). Use the **document API**, not its viewer widget. |
| EPUB engine | Direct `archive` + `xml` container/OPF/TOC parsing + `html` for XHTML + **our own paginator**. (`epubx` conflicts with `pdfrx` through incompatible `image` versions.) |
| Formats | PDF, EPUB, TXT, Markdown. No CBZ, no MOBI. |
| Page turns | Invisible tap zones (left = back, right = forward, centre = menu) **+** swipe. |
| Tap zones | Three **equal thirds**, in every mode and every format. Zoom / Scroll keeps the same thirds for taps but disables swipe, so pans and pinches reach the PDF surface. |
| RTL | Right side is **always** forward, in every book. Text itself is still bidi-correct. |
| EPUB pagination | Exact: block packing with mid-paragraph splitting at real line boundaries. |
| PDF display | Three modes, remembered **per document**: fit-height, fit-width (split into sub-screens), and **Zoom / Scroll** (always continuous, always pinch-zoomable, always momentum-enabled). |
| PDF margins | Auto-crop is configurable in fit-height and fit-width. Zoom / Scroll always uses a **document-uniform** automatic crop and exposes no crop toggle — see §4.1. |
| Zoom / Scroll transform | Owned by our own widget as a `scale` + scene-space `origin`. **Not** `InteractiveViewer` — see §4.1.1 for the two reasons that were unfixable from outside. |
| Scroll physics | Releases are animated with `ClampingScrollSimulation`, Flutter's port of the AOSP `OverScroller` fling curve, driven from a bare `Ticker`. Momentum is always on and is not user-configurable. |
| Zoom range | Pinch ceiling 5×. Pinching out below fit-width is **on by default** (one setting to disable) and bottoms out at roughly **two pages** on screen, derived from real page geometry. |
| Reading chrome | None. Full-bleed page; centre tap reveals a menu overlay. |
| Typography | Font size, line height, margins, justify + hyphenation, paragraph style, publisher-CSS toggle. |
| Paragraph default | Blank-line spacing (not first-line indent). |
| Publisher CSS default | Honour a **safe subset** (bold / italic / headings / alignment); ignore fonts, sizes, colours. |
| Fonts | Bundle several Latin + several Hebrew faces, user-selectable, per book. |
| Settings visibility | The settings screen shows **only** controls the current mode honours, and never repeats the fit-mode selector that already lives in the menu overlay. See §6. |
| Storage | One atomic `library.json` in app documents dir. |
| Entry point | File browser only. Tapping a readable file opens the reader. |
| Escape hatch | "Open with…" in the long-press selection menu → `OpenFilex`. |
| In-document features | TOC + jump to page/percent, bookmarks, text search (EPUB, TXT, and Markdown). |
| Not building | Highlights, notes, dictionary, TTS, PDF text search. |
| Rotation | Manual toggle in the reader menu only. **Never** sensor-driven. Always single-column. |
| Android intents | Designed for, but wired up in a later phase. |
| Sequence | Shell + PDF → Zoom / Scroll → EPUB → TXT/MD → TOC/bookmarks/search → Polish. |
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

The PDF fraction is what lets all three view modes share one position type:
fit-height always stores `0.0`; fit-width-split stores `0.0` or `~0.5`; and
Zoom / Scroll stores wherever the transformed viewport top actually sits.
Because they agree on a
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
  main.dart                               MODIFY  keep PDFium off startup path
  screens/file_browser_screen.dart        MODIFY  route readable files; "Open with…"
  reader/
    models/
      doc_ref.dart                        document identity + format enum
      reading_position.dart               logical position (sealed: Pdf / Text)
      reader_settings.dart                typography + view settings, JSON round-trip
      bookmark.dart                       user bookmark model
      book_state.dart                     one document's persisted record
      reader_exception.dart               ReaderException + EncryptedEpubException
      toc_entry.dart                      table of contents entry item
      content_block.dart                  THE layout primitive (blocks + inline runs)
      laid_out_page.dart                  a page = ordered list of BlockSlice
      parsed_book.dart                    spine items, resources, TOC, char counts
      pdf_continuous_layout.dart          exact Zoom / Scroll extents + offset mapping
    services/
      doc_identity_service.dart           sha1 fingerprint
      book_store_service.dart             library.json, atomic write, debounced
      pagination_cache_service.dart       disk cache keyed by geometry+typography
      page_bitmap_cache.dart              in-memory LRU of rendered PDF bitmaps
      pdf_document_service.dart           pdfrx wrapper: open / render / outline
      pdf_memory_service.dart             lazy Android heap-class query + cache budget
      pdf_runtime_service.dart            shared PDFium initialization on first PDF open
      pdf_crop_service.dart               ink-bbox detection (isolate)
      epub_parser_service.dart            archive/XML EPUB parser → ParsedBook (isolate)
      html_block_parser.dart              XHTML → List<ContentBlock> (isolate)
      text_block_parser.dart              .txt and .md → List<ContentBlock>
      bidi_service.dart                   per-block direction detection
      hyphenation_service.dart            hyphenatorx wrapper, Latin only
      epub_paginator_service.dart         blocks + geometry → pages (UI isolate)
      text_search_service.dart            isolate-backed text search, nikud-insensitive
      reader_error_service.dart           maps IO/OOM/parser failures to safe fallback text
    controllers/
      reader_session.dart                 abstract base
      pdf_reader_session.dart             PDF-specific session controller
      text_reader_session.dart            EPUB + TXT + MD share this
      reader_session_registry.dart        docId → session, LRU suspend
    screens/
      reader_screen.dart                  format-agnostic shell
      reader_settings_screen.dart         mode-scoped display + typography settings
      reader_toc_screen.dart              table of contents navigation screen
      reader_bookmarks_screen.dart        add/list/navigate/delete bookmarks
      reader_search_screen.dart           paginated text search (EPUB/TXT/Markdown)
    widgets/
      tap_zone_layer.dart                 invisible equal-thirds zones + swipe
      reader_menu_overlay.dart            in-book floating control overlay
      pdf_page_view.dart                  fit-mode bitmaps + the continuous zoom surface
      text_page_view.dart                 renders a LaidOutPage
      block_slice_view.dart               the clip-and-offset renderer
assets/fonts/                             bundled Latin + Hebrew faces
```

---

## 3. Dependencies to add

```yaml
dependencies:
  pdfrx: ^2.4.7          # PDFium, MIT. PdfDocument.openFile / PdfPage.render / outline
  archive: ^4.2.0        # EPUB ZIP container
  html: ^0.15.4          # XHTML → DOM
  xml: ^6.5.0            # EPUB container, OPF and NCX documents
  markdown: ^7.2.2       # .md → HTML, then reuse the HTML block parser
  path_provider: ^2.1.4  # app documents dir for library.json
  crypto: ^3.0.5         # sha1 for docId
  hyphenatorx: ^1.0.0    # TeX hyphenation patterns, pure Dart
```

`ClampingScrollSimulation` (the AOSP `OverScroller` fling curve) and `Ticker`
come from the Flutter SDK itself, so Zoom / Scroll momentum needs no extra
dependency.

---

## 4. The two rendering pipelines

### 4.1 PDF

```
file path
  → PdfReaderSession.open() / resume()
  → PdfDocumentService.open()
  → PdfRuntimeService.ensureInitialized()        once, on first real PDF open
  → PdfDocument.openFile()                        pdfrx / PDFium
  → per page: crop rect?                          pdf_crop_service (cached)
  → PdfPage.render(x, y, width, height, full*)    UI isolate
  → ui.Image → RawImage widget                    pdf_page_view
```

**Crop detection.** Render the page small (~200 px wide, ~5–15 ms), then ship the
**byte array** to a background isolate to scan for the bounding box of non-white
pixels (luminance < 245), with a minimum-run filter so scanner specks and stray
marks don't defeat the crop. Detection runs off the UI isolate; PDFium rendering
stays *on* it — FFI handles are not safely shared across isolates. Crop rects are
cached in memory and persisted per document as a compact array.

Crop has **two strategies**, chosen by view mode:

- *Per-page* (fit-height and fit-width, when auto-crop is enabled) — every page
  gets its own crop rect, detected lazily as you reach it. Maximum text size on
  every page.
- *Document-uniform* (Zoom / Scroll, always enabled) — sample ~10 pages spread
  through the document, take the union of their ink boxes, apply it everywhere.
  One cheap up-front pass, and page geometry is fully known before any rendering.
  See §4.1.1 for why the continuous surface requires this.

**The three fit modes.**

- **fit-height** — the cropped page scaled to fit the screen height. One page =
  one screen. Simplest, unambiguous position. Tap-driven only; no zoom.
- **fit-width** — scaled so cropped width equals screen width. The result is
  taller than the screen, so it is split into `ceil(h / screenH)` sub-screens
  (usually 2) with a **6 % overlap** by default, so a line straddling the split is
  fully readable in both halves. Tap-driven only; no zoom.
- **Zoom / Scroll** — one uninterrupted vertical strip of pages, always
  pinch-zoomable, two-axis pannable, and momentum-flinging. Zoom is *exclusively*
  this mode's job. See §4.1.1.

`PdfReaderSession.renderCurrentView()` serves the two tap-driven modes and
deliberately **throws** in Zoom / Scroll, so nothing can silently fall back to
magnifying a single whole-page bitmap.

**Lazy PDF runtime initialization (implemented).** Launcher startup does not initialize
PDFium. As specified in [Android-Only Hardening Plan §2](ANDROID_HARDENING_PLAN.md#2-defer-pdf-runtime-initialization--implemented-device-verification-pending),
`PdfReaderSession.open()` and `resume()` own the reader lifecycle and call
`PdfDocumentService.open()`. The service's default document opener awaits
the memoized `PdfRuntimeService.ensureInitialized()` immediately before
`PdfDocument.openFile()`. Keeping the check in the default opener means tests
that inject a fake `PdfDocumentOpener` do not try to initialize native PDFium.
Missing files are rejected before initialization. The shared future retains both
success and failure for the app lifetime; an initialization failure reaches the
reader error boundary and requires an app restart to retry native setup.

#### 4.1.1 Zoom / Scroll mode

**Why not `InteractiveViewer`.** It was tried and removed. Two of its behaviours
could not be fixed from outside:

1. It calls `onInteractionEnd` *before* starting its fling. Reacting to the
   gesture there (settling the render scale, publishing the new dominant page)
   rebuilt the tile grid and blanked every tile at the exact moment the glide
   began. Movement across plain white on a ~30 fps panel is indistinguishable
   from no movement at all — which is why momentum appeared to be missing even
   when it was mathematically running.
2. Its fling uses `FrictionSimulation`, whose curve is not what Android users
   expect and which decays within a handful of frames on this hardware.

It also floors the pinch scale at `viewport.width / boundaryRect.width`
independently of `minScale`, so zooming out below fit-width required
`boundaryMargin` slack — which in turn let the user pan into empty space beside
a zoomed-in page.

**What replaced it.** `_ContinuousPdfView` owns the transform directly as a
`scale` plus a scene-space `origin` (the document coordinate sitting at the
viewport's top-left), so `screen = (scene - origin) * scale`. A single
`GestureDetector` handles `onScaleStart/Update/End`, which covers one-finger
pans and two-finger pinches alike and still loses the gesture arena to a
stationary tap, so the enclosing tap zones keep working.

- **Momentum.** On release, per-axis `ClampingScrollSimulation`s are driven from
  a bare `Ticker`. Because the ticker is not tied to the widget tree's animation
  plumbing, **no rebuild can cancel an in-flight fling**. Friction is
  `kPdfFlingFriction` (lower = longer glide; deliberately below Flutter's 0.015
  default because a 30 fps panel shows so few frames). Releases slower than
  `kPdfMinFlingVelocity` are treated as a stop, so resting a finger doesn't
  drift the page.
- **Clamping.** Origin clamping is ours, so it is exact: content larger than the
  viewport is bounded to the document, and content *smaller* than the viewport
  (zoomed out past fit-width) is simply centred. No boundary slack, therefore no
  panning into blank space.
- **Zoom floor.** `minScale` is derived per document as
  `viewportHeight / (kPdfZoomOutPageSpan × currentPageHeight)`, clamped to
  `[kPdfMinZoomScaleBeyondFit, 1.0]`, so "fully zoomed out" means about two
  pages on screen regardless of page aspect ratio. Turning
  `allowZoomOutBeyondFit` off pins the floor back to 1.0 and snaps an
  already-shrunken view back to fit-width.

**Why this mode forces uniform crop.** The tile grid needs each page's extent
before it can compute total document height and map logical positions to
transforms. Per-page crop rects are only known *after* that page has been
rendered, so with per-page crop the page heights would keep changing as you
scrolled — content under your finger would shift. Uniform crop makes every page
height derivable from `PdfPage.width/height` (which pdfrx exposes from the
document structure without rendering anything) times one shared crop ratio. So
in Zoom / Scroll, crop becomes document-uniform automatically and no crop
control is shown for that mode.

**Exact extents.** With heights known up front, `PdfContinuousLayout` gives the
canvas its exact total height and maps logical positions directly to offsets.
There is no estimated extent and no layout shift, so TOC, page, and percent jumps
land deterministically.

**Crisp zoom, and the 2-D tile grid.** The pinch scale is quantised to the rungs
in `kPdfZoomRenderScales` and pushed **into PDFium**, so vector content is
genuinely re-rasterised rather than magnified as a texture. To keep that
affordable, each page is cut into a **two-dimensional** grid of tiles whose sides
are at most `kPdfTileSidePixels` device pixels, and only tiles intersecting the
visible rect (on both axes) are built. Because the number of on-screen device
pixels is constant regardless of zoom, so is the cost and the memory — and no
request ever reaches `kPdfMaxTileDimension`, which is what used to silently
downscale full-width strips and make deep zoom look blurry.

**Deferred re-rasterisation.** The render scale is settled only once the gesture
*and* any subsequent fling have finished. Re-rendering mid-pinch would thrash
PDFium; re-rendering mid-fling would swap every tile for a blank one. During a
pinch the existing bitmaps are scaled (briefly soft, `FilterQuality.low`), then
snap crisp when the gesture settles.

**Tap zones still work.** Left/right taps move by one currently visible viewport
height — so at 2× zoom a tap advances half a base screen. The fit-width overlap
setting does not apply here and is only shown when Fit Width is selected. Centre
still toggles the menu.

**Look-ahead.** Tiles are built for the visible rect plus ~0.75 screens above and
below (and ~0.35 screens each side), so a fling glides over rendered content
instead of running into white. A tile with no bitmap yet paints a plain white box
of the correct size — never a spinner, since spinners animate. Because extents
are known, nothing shifts when its bitmap arrives.

**Current page.** In this mode "current page" is whichever page occupies the most
viewport area, computed from the scroll offset against the cumulative height
table. That feeds the menu overlay, percent-read, and position persistence.
User-driven scrolling deliberately does **not** bump the session's navigation
epoch, so the view never fights the user's own pan; only programmatic moves
(tap jumps, page/percent/TOC jumps, resume) do.

**Resolution and memory.** Tap-driven modes render whole pages at native device
pixels capped at `kPdfMaxRenderDimension` (2048 px) on the long edge; one page at
~1264×1680 RGBA ≈ 8.5 MB, and after displaying page N the session pre-renders
N+1 and N−1 in the background, which is what makes turns feel instant. Zoom /
Scroll instead keeps a grid of tiles plus look-ahead resident, so the shared LRU
budget is selected lazily by `PdfMemoryService`: provisionally 25% of the normal
Android heap class, clamped to 4–128 MiB (32 MiB fallback). The query runs at the
first PDF open, not during launcher startup. These are per-session retained-cache
limits, not a bound on PDFium, in-flight rendering, or widget-owned memory.
Render methods hand out caller-owned image handles, cloned before cache insertion
so even immediate eviction cannot invalidate them. Oversized bitmaps bypass the
cache and are disposed by their UI/prefetch callers. See Step 5.3 for measurement
work that remains before locking in this policy.

### 4.2 EPUB / TXT / Markdown

```
.epub → archive+xml  → spine items (HTML strings) + resources + TOC
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
  bool get isSuspended;
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

  List<Bookmark> get bookmarks;
  Future<void> addBookmark(String label);
  Future<void> removeBookmark(String id);

  void suspend();               // free bitmaps, close native handles, keep position
  Future<void> resume();
}
```

The shell picks the view widget by session type (`PdfPageView` or
`TextPageView`), wraps it in `TapZoneLayer`, and rebuilds through a
`ListenableBuilder` on the session. `PdfReaderSession` additionally exposes
`navigationEpoch`, `continuousLayoutForViewport`, `continuousOffsetForPosition`,
`updateContinuousScrollOffset`, and `renderContinuousTile` for the Zoom / Scroll
surface.

---

## 6. Settings model

Global defaults plus per-document overrides, both living in `library.json`.

```dart
class ReaderSettings {
  // text formats
  String latinFontFamily;      // Literata | EB Garamond | Inter
  String hebrewFontFamily;     // Frank Ruhl Libre | Noto Serif Hebrew | Heebo
  int    fontSizeStep;         // 0..7, mapped to pt via a table
  double lineHeight;           // 1.2 .. 2.0
  int    marginStep;           // tight | normal | wide | extra
  bool   justify;
  bool   hyphenate;
  ParagraphMode paragraphMode; // blankLine (default) | firstLineIndent
  bool   honorPublisherCss;    // default true — safe subset

  // pdf
  PdfFitMode fitMode;            // fitHeight | fitWidth | zoom
  bool   autoCrop;               // default true; fitHeight / fitWidth only
  double splitOverlap;           // default 0.06; fitWidth only
  bool   allowZoomOutBeyondFit;  // default true; zoom only

  // shared
  bool   landscape;            // manual toggle only
}
```

**Visibility rules.** `ReaderSettingsScreen` renders only what the active mode
honours, and never duplicates the fit-mode selector already present in the menu
overlay:

| Control | Fit Height | Fit Width | Zoom / Scroll | Text formats |
|---|---|---|---|---|
| Automatic margin crop | shown | shown | hidden (forced document-uniform) | — |
| Fit-width overlap | hidden | shown | hidden (moves by visible viewport) | — |
| Zoom out past the page | hidden | hidden | shown | — |
| Typography (fonts, size, spacing, margins, justify, hyphenation, paragraph mode, publisher CSS) | hidden | hidden | hidden | shown |

Orientation lives in the menu overlay for every format.

---

## 7. Changes to existing files

| File | Change |
|---|---|
| `pubspec.yaml` | Add dependencies (`pdfrx`, `archive`, `xml`, `html`, `markdown`, `path_provider`, `crypto`, `hyphenatorx`); declare fonts assets. |
| `lib/main.dart` | Do not initialize PDFium during launcher startup; see the hardening plan §2. |
| `lib/reader/services/pdf_runtime_service.dart` | Memoize the one-time `pdfrxFlutterInitialize()` future. |
| `lib/reader/services/pdf_document_service.dart` | In the default (non-injected) opener, await the runtime service immediately before `PdfDocument.openFile()`. |
| `lib/constants.dart` | Add `kReadableExtensions`, equal-thirds tap zone ratios, font size/margin tables, crop constants, and the Zoom / Scroll zoom, tile, fling, and cache constants. |
| `lib/screens/file_browser_screen.dart` | Intercept readable files on tap → push `ReaderScreen`; add "Open with…" in selection bar. |

---

## 8. Build Sequence & Actionable Steps

### Phase 0 — De-risk & Native Verification
**Objective:** Prove `pdfrx` and PDFium build and render cleanly on target hardware.
- [x] **Step 0.1: Add dependencies & init pdfrx**
  - Add `pdfrx: ^2.4.7`, `path_provider: ^2.1.4`, `crypto: ^3.0.5` to `pubspec.yaml`.
  - Initial native verification used `await pdfrxFlutterInitialize();` in `lib/main.dart`. Android hardening §2 now moves it into the default PDF document-opening path through `PdfRuntimeService`, so launcher startup stays lazy. Concurrent opens and resumes share initialization; injected openers bypass it.
  - Add `kReadableExtensions` and reader constants in `lib/constants.dart`.
  - 2026-08-31 lazy-startup verification: the actual app entry point and delayed PDF backend regression pass; all reader tests pass within the full suite (166 passed, one opt-in native smoke test skipped, two existing Windows folder-copy failures). `flutter analyze --no-pub` is clean and the release APK build succeeds. Bigme startup timing and native first-open checks remain pending.
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
  - Create `lib/reader/services/pdf_document_service.dart` (pdfrx open, page count, capped crop-rect rendering, outline parser).
  - Create `lib/reader/services/page_bitmap_cache.dart` (LRU memory cache; runtime budget added in Step 5.3).
  - Create `lib/reader/services/pdf_crop_service.dart` (isolate-backed ink bbox detection, minimum-run filtering).
  - Add unit tests in `test/reader/pdf_crop_service_test.dart`.

- [x] **Step 1.4: Session Management & Suspend Contract**
  - Create `lib/reader/controllers/reader_session.dart` (abstract session base with lifecycle contract).
  - Create `lib/reader/controllers/pdf_reader_session.dart`:
    - Implement page navigation (`nextPage`, `prevPage`, `goToPage`, `goToPercent`).
    - Sub-screen calculations for fit-width (with 6% overlap).
    - Background pre-fetching for pages $N+1$ and $N-1$ (tap-driven modes only).
    - Logical position mapping and a navigation epoch that distinguishes programmatic moves from user scrolling.
  - Create `lib/reader/controllers/reader_session_registry.dart` (singleton session pool, max 4 active, auto-suspend).

- [x] **Step 1.5: UI Layer (Tap Zones, Menu, PDF View)**
  - Create `lib/reader/widgets/tap_zone_layer.dart` (three **equal-thirds** zones: left = back, centre = menu, right = forward, plus horizontal swipe; swipe suppressed in Zoom / Scroll so pan/pinch reach the PDF surface).
  - Create `lib/reader/widgets/pdf_page_view.dart` (fit-height and fit-width cached bitmaps, plus the continuous Zoom / Scroll surface).
  - Create `lib/reader/widgets/reader_menu_overlay.dart` (top/bottom bars: page jump, percent jump, TOC, fit mode toggle, rotation, settings entry).
  - Create `lib/reader/screens/reader_settings_screen.dart` (discrete buttons, mode-scoped per §6).

- [x] **Step 1.6: Reader Shell Screen & Lifecycle Hooks**
  - Create `lib/reader/screens/reader_screen.dart` (format-agnostic host with lifecycle-observer position saving).
  - Handle manual landscape/portrait orientation locking.

- [x] **Step 1.7: Wire File Browser Integration**
  - Update `lib/screens/file_browser_screen.dart`:
    - [x] On PDF tap, push `ReaderScreen` via `noTransitionRoute`.
    - [x] Route EPUB/TXT/Markdown internally through the shared `TextReaderSession`.
    - [x] In the selection action bar, provide "Open with…" for one selected file through the native chooser bridge.
  - Update `lib/controllers/file_browser_controller.dart` if needed.

- [ ] **Step 1.8: Phase 1 Verification**
  - Test on device: open PDF, navigate pages via tap and swipe, switch fit modes (height/width/zoom), toggle auto-crop, change orientation, kill app, verify position restores exactly.

---

### Phase 1b — Zoom / Scroll Mode (PDF)
**Objective:** One continuous, pinch-zoomable, momentum-enabled PDF surface with no layout shifts and no blurry zoom.

- [x] **Step 1b.1: Uniform Crop & Cumulative Heights Table**
  - Extend `pdf_crop_service.dart` with document-uniform crop sampling (~10 sample pages).
  - Add `pdf_continuous_layout.dart`: exact page heights, cumulative offsets, offset ↔ logical position mapping, dominant-page selection, max scroll offset.

- [x] **Step 1b.2: Continuous Zoomable PDF Surface**
  - Implement Zoom / Scroll in `pdf_page_view.dart` with a self-owned `scale` + scene `origin` transform, a single scale/pan `GestureDetector`, and exact clamping (undersized content centred).
  - Fling with per-axis `ClampingScrollSimulation` driven from a `Ticker`, so rebuilds cannot cancel momentum. `InteractiveViewer` was removed for the two reasons recorded in §4.1.1.
  - Push the quantised zoom into PDFium via `renderContinuousTile`, using a 2-D tile grid bounded by `kPdfTileSidePixels`, and settle the render scale only after the gesture *and* fling finish.
  - Derive the pinch floor from real page geometry (~two pages) behind `allowZoomOutBeyondFit`.
  - Wire tap zones to jump one currently visible viewport height; keep overlap out of this mode.
  - Map scroll offset ↔ `PdfReadingPosition` bidirectionally, persisting on page changes and on `suspend()` rather than on every drag pixel.

- [ ] **Step 1b.3: Phase 1b Verification**
  - [x] Automated coverage for exact extents, offset/position mapping, dominant-page selection, uniform crop sampling, per-density tile re-rasterisation, and a fling that keeps gliding after release while respecting the end of the document.
  - Verify Zoom / Scroll on device: pinch zoom stays crisp on vector PDFs; two-axis pan and momentum feel right at ~30 fps; zoom-out bottoms out at about two pages; tap jumps exactly one visible screen; TOC/percent jumps land accurately; switching fit modes preserves position.

---

### Phase 2 — EPUB Engine & Exact Pagination
**Objective:** High-performance EPUB parsing, bidi paragraph layout, and text pagination.

- [x] **Step 2.1: Dependencies & Font Assets**
  - Add `archive: ^4.2.0`, `xml: ^6.5.0`, `html: ^0.15.4`, and `hyphenatorx: ^1.0.0` to `pubspec.yaml`. `epubx` was evaluated and replaced with the documented fallback because its `image` 3.x constraint conflicts with `pdfrx_engine`'s `image` 4.x constraint.
  - Bundle fonts in `assets/fonts/` (Literata, EB Garamond, Inter, Frank Ruhl Libre, Noto Serif Hebrew, Heebo).
  - Declare font families in `pubspec.yaml`.

- [x] **Step 2.2: Block Model & Parsing Services**
  - Create `lib/reader/models/content_block.dart` (`ContentBlock`, `InlineRun`, `BlockType`).
  - Create `lib/reader/models/laid_out_page.dart` (`LaidOutPage`, `BlockSlice`).
  - Create `lib/reader/models/parsed_book.dart`.
  - Create `lib/reader/services/bidi_service.dart` (Unicode P2/P3 strong character scan).
  - Create `lib/reader/services/hyphenation_service.dart` (soft hyphen insertion for Latin text).
  - Create `lib/reader/services/html_block_parser.dart` (isolate-backed XHTML DOM walk).
  - Create `lib/reader/services/epub_parser_service.dart` (container, manifest, spine extraction).
  - Add unit tests for parser and bidi logic in `test/reader/`.
  - Implemented EPUB 3 nav and EPUB 2 NCX hierarchy extraction, anchor-to-logical-position mapping, safe inline publisher styling, resource collection, and malformed-container errors.

- [x] **Step 2.3: Paginator & Disk Cache**
  - Create `lib/reader/services/pagination_cache_service.dart` (keyed by docId, spineIndex, geometry, typography).
  - Create `lib/reader/services/epub_paginator_service.dart`:
    - Immediate UI-isolate pagination for current chapter.
    - Progressive time-sliced background pagination for remaining chapters.
    - Widow/orphan line handling.
  - Add paginator unit tests in `test/reader/epub_paginator_service_test.dart`.
  - Implemented real `TextPainter` line boundaries, stable soft-hyphen source offsets, two-line widow/orphan protection, priority-chapter pagination, progressive yielding, and atomic per-chapter disk caching. Cache keys retain fractional viewport geometry and cache writes use independent temporary files.

- [x] **Step 2.4: Text Session Controller & Widgets**
  - Create `lib/reader/controllers/text_reader_session.dart`.
  - Create `lib/reader/widgets/block_slice_view.dart` (clip-and-translate slice renderer).
  - Create `lib/reader/widgets/text_page_view.dart` (renders `LaidOutPage`).
  - Preserve pending TOC/percent targets and logical spine ordering while chapters are still being paginated; cover session progression and the slice renderer with regression tests.

- [x] **Step 2.5: Typography Settings UI**
  - Wire font picker, font size steps, line spacing, margins, justification, hyphenation, and paragraph mode into `reader_settings_screen.dart`.

- [ ] **Step 2.6: Phase 2 Verification**
  - [x] Automated bilingual coverage parses English, Hebrew-with-nikud, and both LTR-first/RTL-first mixed paragraphs; verifies direction, real line-boundary slice coverage, no height overflow, and portrait/landscape re-pagination.
  - [x] Load and lay out every bundled Latin/Hebrew font asset in Flutter tests; confirm all nine font files are packaged in a successful release APK.
  - [x] Verify viewport resize keeps the previous logical text anchor within the newly laid-out page.
  - [ ] On the Bigme B751C: open representative English, Hebrew, and mixed bilingual EPUBs; visually confirm glyph/font quality, no clipped lines, responsive resize, and acceptable e-ink page-turn behaviour. No Android device was attached during the automated 2026-08-30 verification run.

---

### Phase 3 — Plain Text & Markdown Support
**Objective:** Support `.txt` and `.md` using the unified text pipeline.

- [x] **Step 3.1: Dependencies & Text Block Parser**
  - Add `markdown: ^7.2.2` to `pubspec.yaml`.
  - Create `lib/reader/services/text_block_parser.dart`:
    - Encoding detection (UTF-8, UTF-16, Windows-1255 for Hebrew).
    - Plain text blank-line paragraph chunking.
    - Markdown → HTML conversion → `html_block_parser`.

- [x] **Step 3.2: Integrate into Text Session**
  - Wire `.txt` and `.md` formats into `TextReaderSession` and `DocIdentityService`.
  - Ensure character offset tracking and persistence match EPUB.

- [ ] **Step 3.3: Phase 3 Verification**
  - Test `.txt` and `.md` files on device with typography changes and bookmarking.

---

### Phase 4 — Navigation, Bookmarks & In-Book Search
**Objective:** Rich in-document navigation for all formats.

- [x] **Step 4.1: Table of Contents Screen**
  - Create `lib/reader/screens/reader_toc_screen.dart`.
  - Wire EPUB NCX/nav hierarchy and PDF outline into TOC screen.
  - Implement direct jump from TOC entries in both PDF and Text sessions.

- [x] **Step 4.2: Page & Percent Jump Dialogs**
  - Add discrete number-input jump-to-page dialog.
  - Add percent jump entry to the menu overlay.

- [x] **Step 4.3: Bookmarks Management**
  - Created `lib/reader/screens/reader_bookmarks_screen.dart`: add (with a page-number default label), list (newest first, discretely paginated), tap-to-navigate, and delete-with-confirmation.
  - Extended the `ReaderSession` contract with `bookmarks`, `addBookmark`, and `removeBookmark`; both `PdfReaderSession` and `TextReaderSession` implement them against their own logical `position`, restore the list in `_restorePersistedState`, and `_persistState` now writes the live in-memory list instead of only carrying forward whatever was already on disk.
  - Navigating to a bookmark reuses `goToToc` by wrapping the bookmark's label and position as a one-off `TocEntry`, so no separate navigation path was needed.
  - Wired a "Bookmarks" entry point into `reader_menu_overlay.dart`'s top bar (next to Back) and `reader_screen.dart`.
  - Covered by `pdf_reader_session_test.dart` and `text_reader_session_test.dart` (add/remove and cross-session persistence round-trips) and the new `reader_bookmarks_screen_test.dart` (add/list/navigate/delete); `reader_menu_overlay_test.dart` and `reader_session_registry_test.dart` were updated for the new contract member.

- [x] **Step 4.4: In-Book Text Search (EPUB, TXT, Markdown)**
  - Implemented `lib/reader/services/text_search_service.dart`: isolate-backed search across spine `ContentBlock` lists, case-insensitive matching, Hebrew vowel/cantillation-mark and soft-hyphen removal, whitespace normalization, and exact mapping back to original UTF-16 character offsets. Hebrew punctuation is preserved; phrases cross inline runs but not blocks.
  - Implemented `lib/reader/screens/reader_search_screen.dart`: explicit submission, discrete result pagination, chapter labels and original-text RTL snippets, static loading/empty/error states, and stale-query suppression. One worker runs at a time and only the newest queued query is kept. Results are capped at 1,000 with an explicit refinement notice when truncated.
  - Added a text-only Search menu action. Selecting a result reuses logical TOC navigation and hides the reader overlay. Text navigation now retains exact target offsets rather than snapping to the page start, keeping matches visible through typography changes.
  - Search operates on the shared text blocks for EPUB/TXT/Markdown. PDF search remains out of scope (requires text extraction from PDFium).

- [ ] **Step 4.5: Phase 4 Verification**
  - [x] Automated coverage for chapter navigation, search before pagination, exact match retention through typography/viewport changes, bookmark disk reloads, and Hebrew search queries with/without vowel points.
  - [x] Search service/screen, text session, reader menu, and shared pagination controls: 26 focused tests passed; all 98 reader tests passed (one opt-in native test skipped). `flutter analyze --no-pub` reported no issues on 2026-08-30. The full suite reported 117 passed, one opt-in native test skipped, and two unrelated Windows folder-copy failures in `file_operations_service_test.dart` (unchanged by this feature).
  - [ ] Verify search, chapter jumping, and bookmark/font-size round-trips visually on the Bigme B751C.

---

### Phase 5 — Polish, E-Ink Optimisations & Edge Cases
**Objective:** Final hardening, memory management, and display tuning.
- [x] **Step 5.1: Error Boundaries & Fallback UI**
  - `reader_exception.dart` defines `ReaderException` (a message that's always safe to show) and `EncryptedEpubException`. `reader_error_service.dart`'s `readerErrorMessage()` turns any raised error into one of: the exception's own message, a specific missing-file / access-denied message from `FileSystemException`'s OS error code, an out-of-memory message, or a generic per-format "could not read this document" fallback — never a raw stack trace or parser-internal string.
  - Both `PdfReaderSession.open()`/`resume()` and `TextReaderSession.open()`/`applySettings()`/`_repaginate()` catch failures and surface safe messages via `ReaderSession.error`. The shared `ReaderErrorView` offers Retry and Back to files, including PDF page/layout/tile failures. Failed sessions can be retried without leaving the reader; a failed open never overwrites a previously saved position or bookmarks.
  - `ReaderSession.handleMemoryPressure()` (default `suspend()`, overridden by `TextReaderSession` to additionally drop the parsed book and laid-out pages while retaining `percent`/`pageCount` so the UI doesn't flicker) is wired to the OS: `ReaderMemoryPressureObserver` in `lib/main.dart` is registered for the app's whole lifetime and forwards `WidgetsBindingObserver.didHaveMemoryPressure()` to `ReaderSessionRegistry.instance.handleMemoryPressure()`, reaching every open session regardless of which screen is on top. Covered by `test/reader/reader_memory_pressure_observer_test.dart`.
  - The reader screen handles the visible memory-warning fallback without duplicating the app-wide session release. It clears Flutter image caches and waits for Continue reading before reopening. Generation checks discard late loads, pagination, outlines, crop detection, and PDF renders after suspension/disposal; discarded renders cannot repopulate the bitmap cache. Fit-mode images now hold their own cloned image handles, just like continuous tiles.
  - Serialized `BookStoreService.flush()` requests prevent overlapping pause/disposal/memory-warning writes from racing on `library.json.tmp`.
  - Android hardening follow-up: concurrent library loads now share one initialization. Malformed reader state is preserved in up to three `.corrupt` backups before replacement; backups are never overwritten. If preservation fails or the slots are full, saving is disabled and the source remains untouched. `ReaderScreen` explains recovery or disabled saving before continuing. Launcher startup and its recovery/app-drawer paths never load reader state.
  - Added direct message-mapping tests (`reader_error_service_test.dart`), actual reader-shell Retry/Back/memory-continuation tests (`reader_error_screen_test.dart`), and session/cache/persistence tests for recovery, late completion, cleared image handles, and concurrent saves. Device-level memory-warning and visual recovery checks remain pending; adaptive memory budgets are still Step 5.3.
- [x] **Step 5.2: DRM-Protected EPUB Detection**
  - `epub_parser_service.dart`'s `_checkEncryption()` inspects `META-INF/encryption.xml` when it exists, before any spine document is read. For each `EncryptedData` entry it resolves the container-rooted `CipherReference` path (not relative to `META-INF` or the OPF — see the code comment citing the EPUB 3.3 spec section) and checks whether the algorithm is one of the two font-obfuscation schemes (idpf / Adobe) *and* every manifest item at that path is a font media type *and* the path is not itself a spine document.
  - A match is treated as ordinary font obfuscation, not DRM: the path is added to an `ignoredFonts` set that's threaded back out to the resource-collection loop, which skips it — obfuscated publisher fonts are never used or decoded, since the reader always renders with its own bundled fonts. Anything else (a real encryption algorithm, or *any* algorithm applied to a spine document or non-font resource) throws `EncryptedEpubException(resourcePath:, algorithm:)`, whose fixed message ("This book contains DRM-protected or encrypted content that this reader cannot open.") is what `ReaderScreen`'s error view shows, via `reader_error_service.dart` (Step 5.1).
  - Fixtures for all three cases — no `encryption.xml`, an idpf-obfuscated font excluded from `book.resources` without error, and an encrypted spine document throwing `EncryptedEpubException` with the right path and algorithm — are in `test/reader/epub_parser_service_test.dart`'s `META-INF/encryption.xml` group.
  - Additional fixtures cover Adobe obfuscation, percent-encoded container-root paths, encryption of image/font resources, a font-obfuscation algorithm incorrectly applied to spine content, and malformed encryption metadata.
- [ ] **Step 5.3: Adaptive PDF Bitmap Cache Size**
  - [x] Added `PdfMemoryHandler.kt` and `pdf_memory_service.dart`. The `eink_launcher/pdf_memory` channel queries normal `ActivityManager.getMemoryClass()` only on the first PDF open, with one shared lookup across concurrent sessions, retries, and resumes. Registering the native handler does not query memory. Lazy PDFium initialization itself is implemented separately in Android hardening §2 through `PdfRuntimeService`.
  - [x] Replaced the fixed 96 MiB session cache with a provisional **25% heap-class budget, clamped to 4–128 MiB**. Examples: 64 MiB heap → 16 MiB cache; 256 → 64; 512+ → 128. Invalid/nonpositive replies, missing native handlers, platform failures, non-Android hosts, and a one-second timeout use a **32 MiB fallback**. Clamp before multiplication to avoid overflow on extreme reports.
  - [x] Configure the runtime budget before opening a PDF, preserving explicit injected-cache limits. Generation checks prevent delayed queries from resizing or opening suspended/disposed sessions. `PageBitmapCache.resize()` immediately evicts in LRU order.
  - [x] Make session render methods return caller-owned handles, safe from cache replacement/eviction before the UI sees them. Oversized images bypass the cache without leaking; fit/zoom views and prefetch release handles, including late completions after unmount. Tests cover budget/clamp/fallback cases, query lifecycle, session suspension/resumption, LRU resizing, and image ownership under small budgets.
  - [ ] **Bigme measurement remains pending; fraction and bounds are not yet device-tuned.** No device was attached on 2026-08-31. Connect the Bigme and record `adb shell getprop dalvik.vm.heapgrowthlimit`, `adb shell getprop dalvik.vm.heapsize`, and `adb shell dumpsys meminfo com.example.eink_launcher` at launcher idle, after opening representative scan/vector PDFs, after repeated page turns/zoom/flings, and after leaving the reader. Use the channel's actual `getMemoryClass` result for the chosen budget; the properties only provide context. Compare native/graphics/total PSS and page-turn behaviour, then adjust the policy if needed.
  - The budget covers **retained entries per session**, not the app's total memory. Visible/look-ahead widget handles, in-flight render buffers, and PDFium allocations remain outside it; active-session count also matters. The existing suspend/memory-pressure paths are retained.
  - 2026-08-31 software verification: all **146 reader tests passed** (one opt-in native test skipped), `flutter analyze --no-pub` was clean, and `flutter build apk --release --no-pub` succeeded. Full suite: **165 passed**, one skipped, and the two previously documented Windows folder-copy failures in `file_operations_service_test.dart`.
- [x] **Step 5.4: Update Documentation & Tests**
  - Update `README.md` with new file listings and architectural details.
  - Run full test suite (`flutter test`, `flutter analyze`).
  - 2026-08-31 hardening verification: all 122 reader tests pass (one opt-in native test skipped), and `flutter analyze --no-pub` is clean. Full suite: 141 passed, one opt-in native test skipped, and the same two unrelated Windows folder-copy failures in `file_operations_service_test.dart`.
  - Later 2026-08-31 Android hardening verification supersedes the earlier full-suite failures: **201 Flutter tests pass**, one opt-in native PDFium smoke test is skipped, and **5 native JVM startup-policy tests pass**. The Windows folder-copy failures are fixed. Analysis is clean; debug and release APKs build. Bigme-only reader verification is still outstanding.

---

## 9. Tests

- `doc_identity_service_test.dart` — same file at two paths yields same id; modified file yields new id.
- `book_store_service_test.dart` — JSON round-trip; atomic write robustness; corrupt file recovery.
- `bidi_service_test.dart` — English, Hebrew, Hebrew-with-nikud, mixed RTL/LTR, numbers, punctuation.
- `html_block_parser_test.dart` — nested lists, blockquotes, inline tags, images, safe CSS filtering.
- `epub_parser_service_test.dart` — EPUB metadata, spine, resources, nav hierarchy, logical anchors, malformed containers.
- `hyphenation_service_test.dart` — Latin soft-hyphen insertion without modifying Hebrew or inline styling.
- `epub_paginator_service_test.dart` — block packing, line splits, widow/orphan protection.
- `phase2_verification_test.dart` — bundled fonts, bilingual directions, exact portrait/landscape slice coverage, and re-pagination timing.
- `text_search_service_test.dart` — shared EPUB/TXT/Markdown search, Hebrew marks, original UTF-16 offsets, whitespace and inline boundaries, literal punctuation, bounded results, and previews.
- `reader_search_screen_test.dart` — submission, paginated selection, queued/stale queries, clear/retry/dispose handling, and RTL/narrow-screen layout.
- `pdf_crop_service_test.dart` — bbox bounding math, noise filtering, uniform crop sampling.
- `pdf_memory_service_test.dart` — lazy Android memory lookup, bounded budgets, fallback handling, concurrent callers, and timeout recovery.
- `pdf_runtime_service_test.dart` — actual launcher startup without PDFium, default-opener ordering, shared concurrent initialization, injected/missing-file bypass, and cancellation/reopen cleanup.
- `pdf_continuous_layout_test.dart` — offset-to-page and page-to-offset mapping, dominant page, boundary clamping.
- `pdf_reader_session_test.dart` — fit-mode navigation and sub-screens, whole-page cache reuse, refusal to render whole pages in Zoom / Scroll, per-density tile re-rasterisation, navigation-epoch semantics, and a widget test proving a fling keeps gliding after release.
- `reader_settings_screen_test.dart` — mode-scoped control visibility, no duplicated fit-mode selector, zoom-out default and JSON round-trip.
- `tap_zone_layer_test.dart` — equal-thirds tap boundaries, fixed forward direction, and swipe callbacks.

---

## 10. Known risks & Mitigations

1. **`epubx` dependency conflict (resolved):** Phase 2 validation found incompatible transitive `image` constraints with `pdfrx`; the direct `archive` + `xml` fallback is implemented and covered by an in-memory EPUB fixture.
2. **UI-isolate pagination load:** Mitigated via current-chapter priority pagination + progressive frame slicing + disk caching.
3. **Hebrew fonts & nikud:** Multiple bundled OFL fonts selectable per-book.
4. **Memory pressure:** Hard 4-session cap + suspend contract + adaptive per-session LRU bitmap budgets (`PdfMemoryService`), with 2-D tiling so zoom cost stays flat instead of growing with scale. The cache limit excludes UI-held/in-flight/native allocations and is not a process-wide cap; Step 5.3 Bigme profiling remains required.
5. **Zoom / Scroll on a ~30 fps panel:** A fling only gets a dozen or so frames, so momentum must never be interrupted. Mitigated by owning the transform, driving the fling from a `Ticker` that rebuilds cannot cancel, deferring re-rasterisation until the glide ends, and rendering ~0.75 screens of look-ahead. Tunable via `kPdfFlingFriction` (lower = longer glide) and `kPdfMinFlingVelocity`.
6. **PDF rendering responsiveness:** The earlier 2026-08-30 note described smooth flinging on the B751C. That does not establish acceptable behavior on the HiBreak: the 2026-08-31 user report records rapid-page-tap freezing and white screens during zooming/fast scrolling ([device test log](BIGME_TEST_LOG.md)). Existing bounded tiles, deferred re-rasterisation, and look-ahead do not close these reported issues. Their causes remain unconfirmed; document-specific reproduction and profiling are still needed before selecting a fix.
7. **Custom EPUB parser maintenance:** The direct `archive` + `xml` parser was built because `epubx` had incompatible transitive `image` version constraints with `pdfrx`. If `epubx` or a fork resolves that conflict in the future, consider switching back to reduce the maintenance surface of container/OPF/NCX/nav parsing. The current parser is tested against an in-memory EPUB fixture, but real-world EPUBs vary widely and may expose edge cases over time.
