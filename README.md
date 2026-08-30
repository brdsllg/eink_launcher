* this file is ai generated, so skepticism is allowed and even encouraged 


# E-Ink Launcher & File Manager

An Android home launcher and file manager built with Flutter, designed specifically for E-Ink devices (such as the Bigme B751C).

---

## 📖 Overview & Design Principles

Standard Android launchers and file explorers rely heavily on smooth animations, kinetic flings, vibrant colors, and rapid screen updates. On electronic paper displays (E-Ink), these behaviors cause severe ghosting, visual stutter, and battery drain.

This project is tailored for E-Ink displays around five core architectural pillars:
1. **High-Contrast Monochrome UI:** Pure black-and-white theme (`#000000` / `#FFFFFF`) with crisp borders and inverse highlighting. No gradients, shadows, or gray-on-gray elements.
2. **Zero Animation / Instant Transitions:** Standard route animations, splash effects, ripple feedback, and sliding snackbars are completely disabled (`Duration.zero`, `NoSplash.splashFactory`, `noTransitionRoute`).
3. **Discrete Pagination over Kinetic Scrolling:** Lists (file browser, app drawer) compute exact row fits and paginate screen-by-screen using explicit First/Previous/Next/Last controls, eliminating smooth scrolling ghosting.
   - The file browser and app drawer use 15 equal-height horizontal bands in portrait and 12 in landscape, including their structural top and bottom bars.
   - The one deliberate exception is the reader's Zoom / Scroll PDF mode, where continuous panning and momentum are the entire point of the mode; see the reader section below.
4. **Isolate-Based Background I/O:** Heavy filesystem listings, recursive searches, and metadata statting run on long-lived background isolates to keep the UI thread responsive.
5. **Minute-Aligned Timers:** UI timers (such as the clock readout) align strictly to minute boundaries to prevent unneeded per-second display refreshes.

---

## 🗂️ Project Directory & File Guide

Below is an exhaustive description of every significant file and directory in this project.

```
eink_launcher/
├── ANDROID_HARDENING_PLAN.md             # Practical Android-only optimization roadmap
├── README.md                              # Project documentation & file guide
├── READER_PLAN.md                        # Blueprint & implementation plan for built-in reader
├── analysis_options.yaml                 # Dart static analysis & lint rules
├── pubspec.yaml                          # Package metadata, assets & dependencies
├── lib/
│   ├── main.dart                         # Application entry point, pdfrx init & theme configuration
│   ├── constants.dart                    # Shared global constants, reader constants & route utilities
│   ├── controllers/
│   │   └── file_browser_controller.dart  # Business logic & state management for file browser
│   ├── models/
│   │   ├── clipboard_state.dart          # In-memory clipboard state (copy/cut operations)
│   │   ├── file_entry.dart               # File/directory entity model with lazy stats
│   │   └── launcher_app.dart             # Minimal native launcher-app record
│   ├── reader/
│   │   ├── controllers/
│   │   │   ├── pdf_reader_session.dart   # PDF reader lifecycle, navigation, tiling & rendering
│   │   │   ├── reader_session.dart       # Shared reader session contract & view models
│   │   │   ├── reader_session_registry.dart # Open-session lifecycle registry
│   │   │   └── text_reader_session.dart  # EPUB/TXT/Markdown parsing, pagination & position lifecycle
│   │   ├── models/
│   │   │   ├── bookmark.dart             # Reader bookmark data model
│   │   │   ├── book_state.dart           # Per-document persisted state model
│   │   │   ├── content_block.dart         # Semantic text blocks and styled inline runs
│   │   │   ├── doc_ref.dart              # Document format enum & identity model
│   │   │   ├── laid_out_page.dart         # Exact page block-slice geometry
│   │   │   ├── parsed_book.dart           # Parsed spine, resources, TOC & char counts
│   │   │   ├── pdf_continuous_layout.dart # Exact PDF scroll extents & offset mapping
│   │   │   ├── reader_settings.dart      # Typography, display & fit settings model
│   │   │   ├── reading_position.dart     # Logical reading position (Pdf / Text)
│   │   │   └── toc_entry.dart            # Table of Contents hierarchy model
│   │   ├── services/
│   │   │   ├── bidi_service.dart          # Unicode first-strong block direction
│   │   │   ├── book_store_service.dart   # library.json atomic persistence service
│   │   │   ├── doc_identity_service.dart # SHA-1 content fingerprinting service
│   │   │   ├── epub_parser_service.dart   # Isolate-backed ZIP/OPF/nav/NCX parser
│   │   │   ├── html_block_parser.dart     # Isolate-backed XHTML semantic DOM walker
│   │   │   ├── hyphenation_service.dart  # Latin-only discretionary hyphenation
│   │   │   ├── page_bitmap_cache.dart    # Memory-bounded LRU for rendered PDF bitmaps
│   │   │   ├── pagination_cache_service.dart # Disk cache for text page geometry
│   │   │   ├── pdf_crop_service.dart     # Isolate-backed PDF ink-bound detection
│   │   │   ├── pdf_document_service.dart # pdfrx document open/render/outline wrapper
│   │   │   ├── epub_paginator_service.dart # Exact TextPainter line-boundary pagination
│   │   │   └── text_block_parser.dart    # TXT encodings and Markdown semantic parsing
│   │   ├── screens/
│   │   │   ├── reader_screen.dart        # Full-bleed reader shell & lifecycle hooks
│   │   │   ├── reader_bookmarks_screen.dart # Add, list, navigate to & delete bookmarks
│   │   │   ├── reader_settings_screen.dart # Mode-scoped PDF and typography settings
│   │   │   └── reader_toc_screen.dart    # Paginated PDF/text table of contents
│   │   └── widgets/
│   │       ├── block_slice_view.dart      # Clip-and-translate semantic block slice renderer
│   │       ├── pdf_page_view.dart        # Fit-mode bitmaps & the continuous zoom surface
│   │       ├── reader_menu_overlay.dart  # E-ink reader controls and page status
│   │       ├── tap_zone_layer.dart       # Invisible equal-thirds tap zones and swipes
│   │       └── text_page_view.dart       # Full-bleed laid-out EPUB/TXT/Markdown page
│   ├── screens/
│   │   ├── app_drawer_screen.dart        # Paginated application drawer & search screen
│   │   └── file_browser_screen.dart      # Main home file manager screen
│   ├── services/
│   │   ├── app_list_service.dart         # Installed app discovery & launch service
│   │   ├── file_mime_type_service.dart   # Precise MIME mapping for common file formats
│   │   ├── file_operations_service.dart  # File mutation logic (create, rename, delete, paste)
│   │   ├── folder_loader_service.dart    # Isolate-backed folder listing & lazy stat loader
│   │   ├── open_with_service.dart        # Android app-chooser bridge for selected files
│   │   └── search_service.dart           # Isolate-backed streaming filesystem search
│   └── widgets/
│       ├── battery_status.dart           # Live percentage, level, and charging indicator
│       ├── clock_text.dart               # Minute-aligned e-ink digital clock widget
│       ├── file_action_dialogs.dart      # Modal dialogs for new folder, rename, & delete
│       ├── file_entry_tile.dart          # High-contrast file/folder list item row
│       ├── page_nav_bar.dart             # First/previous/next/last pagination footer
│       ├── paginated_list.dart           # Generic height-calculated paginated list container
│       └── search_overlay.dart           # Floating filename search bar with streaming matches
├── test/
│   ├── app_list_service_test.dart        # Native app-channel mapping and cache tests
│   ├── file_action_dialogs_test.dart     # Widget tests for input dialog validation
│   ├── file_mime_type_service_test.dart  # Common and fallback MIME mapping tests
│   ├── file_operations_service_test.dart # Unit tests for filesystem mutations & edge cases
│   ├── page_nav_bar_test.dart            # Boundary pagination control widget tests
│   ├── widget_test.dart                  # Basic UI smoke tests
│   └── reader/
│       ├── book_store_service_test.dart  # Unit tests for library.json persistence & reload
│       ├── bidi_service_test.dart        # English/Hebrew first-strong direction tests
│       ├── doc_identity_service_test.dart# Unit tests for SHA-1 docId generation
│       ├── epub_parser_service_test.dart # In-memory EPUB parse and error tests
│       ├── epub_paginator_service_test.dart # Exact line splits and widow/orphan tests
│       ├── html_block_parser_test.dart   # XHTML blocks, styling, lists & images
│       ├── hyphenation_service_test.dart # Latin/Hebrew soft-hyphen tests
│       ├── page_bitmap_cache_test.dart   # Unit tests for PDF bitmap LRU eviction
│       ├── pdf_continuous_layout_test.dart # Exact scroll geometry mapping tests
│       ├── pdf_crop_service_test.dart    # Unit tests for crop bounds & noise filtering
│       ├── pdf_document_service_test.dart# PDF service unit tests & opt-in native smoke test
│       ├── pdf_reader_session_test.dart  # PDF navigation, tiling, momentum & lifecycle tests
│       ├── pagination_cache_service_test.dart # Text page cache round-trip tests
│       ├── phase2_verification_test.dart # Bilingual font/layout/resize verification
│       ├── reader_menu_overlay_test.dart # Reader menu controls widget tests
│       ├── reader_toc_screen_test.dart   # Nested TOC selection widget test
│       ├── reader_session_registry_test.dart # Reader session registry lifecycle tests
│       ├── reader_settings_test.dart     # Settings persistence and migration tests
│       ├── reader_settings_screen_test.dart # Mode-scoped settings widget tests
│       ├── text_block_parser_test.dart   # TXT encoding and Markdown parser tests
│       ├── text_page_view_test.dart      # Clip-and-offset text page widget test
│       ├── text_reader_session_test.dart # Text navigation, persistence & repagination tests
│       ├── text_reader_settings_screen_test.dart # Typography settings widget test
│       └── tap_zone_layer_test.dart      # Tap boundary and swipe-direction tests
├── assets/fonts/                         # Bundled OFL Latin and Hebrew fonts
│   └── licenses/                         # One OFL license copy per font family
└── android/                              # Native Android platform configuration
```

---

### Root Configuration & Documentation

- **[`ANDROID_HARDENING_PLAN.md`](ANDROID_HARDENING_PLAN.md)**: Prioritized, measurement-driven steps for hardening the Flutter launcher as an Android-only e-ink application.
- **[`README.md`](README.md)**: The primary project documentation file (this document), explaining the app's architecture, listing all files and their roles, and providing maintenance instructions.
- **[`READER_PLAN.md`](READER_PLAN.md)**: Architectural design blueprint and phased implementation plan for the integrated native document reader (PDF, EPUB, TXT, Markdown) with bidi Hebrew/English support.
- **[`analysis_options.yaml`](analysis_options.yaml)**: Configures Dart analyzer rules and linter options based on `package:flutter_lints`.
- **[`pubspec.yaml`](pubspec.yaml)**: Defines Flutter dependencies (including `pdfrx`, `archive`, `xml`, `html`, and `hyphenatorx` for the reader), SDK constraints, and bundled font families.

---

### Core Source Code (`lib/`)

#### Top-Level
- **[`lib/main.dart`](lib/main.dart)**:
  - Initializes Flutter bindings and native plugins, including `pdfrxFlutterInitialize()`.
  - Applies no global orientation preference; the reader is the only screen that locks orientation, and only through its manual portrait/landscape toggle (never sensor-driven).
  - Enables `SystemUiMode.immersiveSticky` to keep Android system status and navigation bars hidden.
  - Builds the root `MaterialApp` with an E-Ink-optimized theme (monochrome color scheme, zero splash factory, square outlined buttons, custom popup menus) and boots `FileBrowserScreen`.
- **[`lib/constants.dart`](lib/constants.dart)**:
  - `kStorageRoot`: Fallback home directory and Android shared internal storage root (`/storage/emulated/0`).
  - `kRowHeight`: Default row height (`60.0` px) for generic paginated views; the file browser derives an exact shared height from its orientation band count.
  - `kNavBarHeight`: Default navigation height (`56.0` px); the file browser bottom bar instead matches its file and Up rows exactly.
  - `kPortraitBarCount` / `kLandscapeBarCount`: Total equal-height launcher bands in each orientation (`15` / `12`).
  - `noTransitionRoute()`: Custom `PageRouteBuilder` helper that wraps route transitions with `Duration.zero` to eliminate slide/fade animations.
  - `kReadableExtensions`: Set of supported extensions for the built-in reader (`.pdf`, `.epub`, `.txt`, `.md`).
  - `kTapZoneEdgeWidthRatio` / `kTapZoneCenterWidthRatio`: Tap-zone proportions, three equal thirds in every mode and format.
  - `kPdfDefaultSplitOverlap`: Default vertical slice overlap (6%) for Fit Width sub-screen turns; unused by Zoom / Scroll.
  - `kPdfMaxRenderDimension`: Longest-edge pixel ceiling (`2048.0` px) for whole-page fit-mode renders.
  - `kPdfMaxZoomScale` / `kPdfMinZoomScale`: Zoom / Scroll pinch ceiling (`5.0`) and the floor used when zooming out past the page is disabled (`1.0`).
  - `kPdfZoomOutPageSpan` / `kPdfMinZoomScaleBeyondFit`: Target number of pages visible when fully pinched out (`2.0`) and the absolute hard floor (`0.2`).
  - `kPdfZoomRenderScales`: Discrete zoom rungs at which pages are re-rasterised through PDFium, so zoomed vector content stays crisp instead of being magnified.
  - `kPdfTileSidePixels` / `kPdfMaxTileDimension`: Target and hard-cap device-pixel side lengths for one Zoom / Scroll tile; tiles are built to stay under the target so the cap never silently downscales output.
  - `kPdfFlingFriction` / `kPdfMinFlingVelocity`: Momentum tuning for the Zoom / Scroll fling. Friction is fed to `ClampingScrollSimulation`, where **lower means a longer glide**; releases slower than the velocity threshold are treated as a stop.
  - `kPdfBitmapCacheBytes`: Memory budget for rendered PDF bitmaps (`96 MB`), sized for a zoomed tile grid plus look-ahead.
  - `kPdfInkLuminanceThreshold`: Bounding box detection ink luminance cutoff (`245`).
  - `kReaderFontSizeSteps` / `kReaderMarginSteps`: Step tables for typography and margin configuration.

#### Reader Module (`lib/reader/`)

PDF, EPUB, TXT, and Markdown now open end-to-end in the built-in full-screen
reader. The text formats share exact `TextPainter` line-boundary pagination,
logical position persistence, progressive per-chapter pagination, a disk page
cache, bundled Latin/Hebrew fonts, bidi block direction, optional Latin
hyphenation, and discrete typography controls. EPUB 3 nav, EPUB 2 NCX, PDF
outlines, and Markdown headings feed the paginated Table of Contents screen;
page and percent jumps are available from the reader overlay. Bookmarks work
the same way for every format: each is a label plus the same logical
`ReadingPosition` used for persistence, so a bookmark survives font-size,
margin, rotation, and PDF-fit-mode changes exactly like the saved reading
position does, and jumping to one reuses the Table of Contents' own
navigation path.

PDFs offer three per-document display modes. **Fit Height** and **Fit Width** are
purely tap-driven, with optional per-page auto-crop and (for Fit Width) an
overlapping sub-screen split. **Zoom / Scroll** is the one continuous surface:
always pinch-zoomable, two-axis pannable, and momentum-flinging, with a
document-uniform crop so page extents are exact before anything renders. It owns
its own transform rather than using `InteractiveViewer`, pushes the quantised
zoom level down into PDFium through a two-dimensional tile grid so zoomed vector
content is genuinely re-rasterised, and defers re-rasterisation until a gesture
and its fling have both finished so a glide never blanks the screen.

Phase 2's automated verification covers every bundled font, English and Hebrew
with nikud, mixed first-strong directions, exact portrait/landscape slice
coverage, and logical-anchor retention through viewport resize. A release APK
build also confirms all nine font files are packaged. Visual verification on the
target Bigme B751C remains outstanding when the device is connected, for both the
bilingual text pipeline and the Zoom / Scroll zoom/momentum behaviour.

##### Controllers

- **[`lib/reader/controllers/reader_session.dart`](lib/reader/controllers/reader_session.dart)**:
  - Defines the shared reader-session lifecycle, navigation, settings, and suspend/resume contracts.
- **[`lib/reader/controllers/pdf_reader_session.dart`](lib/reader/controllers/pdf_reader_session.dart)**:
  - Implements PDF session loading, fit-mode navigation and sub-screens, continuous layout and offset mapping, per-page and document-uniform crop resolution, neighbour prefetching, persistence, cached whole-page rendering, and cached per-tile rendering at an explicit zoom density.
  - Exposes a `navigationEpoch` that increments only on *programmatic* moves, so the continuous view can tell a TOC jump apart from the user's own pan and never fights an in-flight fling.
  - Deliberately throws from `renderCurrentView` in Zoom / Scroll, so no code path can fall back to magnifying one whole-page bitmap.
- **[`lib/reader/controllers/reader_session_registry.dart`](lib/reader/controllers/reader_session_registry.dart)**:
  - Tracks open document sessions and coordinates suspension, resumption, and disposal.
- **[`lib/reader/controllers/text_reader_session.dart`](lib/reader/controllers/text_reader_session.dart)**:
  - Implements shared EPUB/TXT/Markdown loading, progressive cached pagination, logically ordered chapter publication, pending TOC/percent targets, typography re-pagination, persistence, suspension, and resumption.

##### Models and Services

- **[`lib/reader/models/doc_ref.dart`](lib/reader/models/doc_ref.dart)**:
  - `DocFormat` enum (`pdf`, `epub`, `txt`, `markdown`).
  - `DocRef` model representing document identity, location, format, title, and size.
- **[`lib/reader/models/reading_position.dart`](lib/reader/models/reading_position.dart)**:
  - Sealed `ReadingPosition` hierarchy (`PdfReadingPosition` with fractional page offset and `TextReadingPosition` with spine, block, and character offsets).
- **[`lib/reader/models/content_block.dart`](lib/reader/models/content_block.dart)**:
  - Rendering-independent semantic blocks and inline runs with direction, alignment, list depth, links, and image references.
- **[`lib/reader/models/laid_out_page.dart`](lib/reader/models/laid_out_page.dart)**:
  - Defines paginator output as clip-and-offset block slices bounded by stable logical text positions.
- **[`lib/reader/models/parsed_book.dart`](lib/reader/models/parsed_book.dart)**:
  - Holds parsed spine chapters, anchor maps, resources, hierarchical TOC entries, and cumulative character counts.
- **[`lib/reader/models/pdf_continuous_layout.dart`](lib/reader/models/pdf_continuous_layout.dart)**:
  - Calculates exact fit-width page heights, cumulative offsets, logical-position conversions, maximum scroll offset, and the page occupying most of the viewport.
- **[`lib/reader/models/reader_settings.dart`](lib/reader/models/reader_settings.dart)**:
  - Reader configuration model encompassing fonts, font size steps, margins, line height, hyphenation, justification, `ParagraphMode`, `PdfFitMode`, auto-crop, Fit Width overlap, `allowZoomOutBeyondFit` (with the derived `minZoomScale` floor), and orientation.
  - Tolerates legacy `library.json` values: older `continuousScroll` / `freeZoom` fit modes map onto `zoom`, and documents saved before `allowZoomOutBeyondFit` existed default it to on.
- **[`lib/reader/models/bookmark.dart`](lib/reader/models/bookmark.dart)**:
  - Document bookmark entity mapping creation time and label to a logical `ReadingPosition`.
- **[`lib/reader/models/toc_entry.dart`](lib/reader/models/toc_entry.dart)**:
  - Hierarchical Table of Contents tree entry with nesting support.
- **[`lib/reader/models/book_state.dart`](lib/reader/models/book_state.dart)**:
  - Comprehensive document persistence state holding reading progress, timestamp, document overrides, bookmarks, per-page crops, and the continuous-mode uniform crop.
- **[`lib/reader/services/doc_identity_service.dart`](lib/reader/services/doc_identity_service.dart)**:
  - Generates stable `sha1(first 64 KB + fileSize)` document keys so moved/renamed files retain reading positions.
- **[`lib/reader/services/book_store_service.dart`](lib/reader/services/book_store_service.dart)**:
  - Manages `library.json` using atomic write-to-temp-then-rename and 2-second debounced background flushing.
- **[`lib/reader/services/bidi_service.dart`](lib/reader/services/bidi_service.dart)**:
  - Applies Unicode P2/P3 first-strong scanning to choose each block's LTR or RTL base direction.
- **[`lib/reader/services/hyphenation_service.dart`](lib/reader/services/hyphenation_service.dart)**:
  - Inserts discretionary soft hyphens into eligible Latin words while preserving Hebrew text and inline semantics.
- **[`lib/reader/services/html_block_parser.dart`](lib/reader/services/html_block_parser.dart)**:
  - Walks XHTML on a background isolate and emits semantic headings, paragraphs, lists, quotes, preformatted text, images, inline styles, and safe publisher alignment.
- **[`lib/reader/services/epub_parser_service.dart`](lib/reader/services/epub_parser_service.dart)**:
  - Parses EPUB ZIP containers directly with `archive` and `xml`, extracting metadata, OPF manifest/spine, resources, EPUB 3 nav or EPUB 2 NCX, and anchor positions without the incompatible `epubx` dependency.
- **[`lib/reader/services/page_bitmap_cache.dart`](lib/reader/services/page_bitmap_cache.dart)**:
  - Owns rendered Flutter images in a least-recently-used cache bounded by `kPdfBitmapCacheBytes` (96 MB) and disposes replaced or evicted bitmaps. Zoom / Scroll widgets hold `clone()`s, so an eviction can never dispose a bitmap that is still on screen.
- **[`lib/reader/services/pagination_cache_service.dart`](lib/reader/services/pagination_cache_service.dart)**:
  - Atomically caches text page geometry by document, chapter, fractional viewport geometry, and typography settings using versioned entries and collision-free temporary writes.
- **[`lib/reader/services/epub_paginator_service.dart`](lib/reader/services/epub_paginator_service.dart)**:
  - Uses the renderer's `TextPainter` geometry for exact line-boundary block slices with widow/orphan protection and stable source offsets through soft hyphenation.
- **[`lib/reader/services/text_block_parser.dart`](lib/reader/services/text_block_parser.dart)**:
  - Decodes UTF-8, UTF-16, and Windows-1255 TXT files and converts Markdown into the shared semantic block model.
- **[`lib/reader/services/pdf_crop_service.dart`](lib/reader/services/pdf_crop_service.dart)**:
  - Detects padded ink bounds on a background isolate, distinguishes blank samples, and unions up to ten spread page samples for stable document-uniform cropping.
- **[`lib/reader/services/pdf_document_service.dart`](lib/reader/services/pdf_document_service.dart)**:
  - Owns the `pdfrx` document handle and provides page geometry, PDF-outline conversion, and crop-rect rendering with a caller-supplied dimension cap (2048 px for whole pages, a tile-specific cap for Zoom / Scroll).

##### Screens and Widgets

- **[`lib/reader/screens/reader_screen.dart`](lib/reader/screens/reader_screen.dart)**:
  - Obtains long-lived sessions from the registry, subscribes to them through a `ListenableBuilder`, presents a full-bleed page, hosts the tap-zone layer and menu overlay, coordinates app pause/resume persistence, and applies manual portrait/landscape locks.
  - Pushes `ReaderBookmarksScreen` and, when a bookmark is selected, jumps to it by wrapping its label and position as a one-off `TocEntry` and calling the session's existing `goToToc`.
- **[`lib/reader/screens/reader_bookmarks_screen.dart`](lib/reader/screens/reader_bookmarks_screen.dart)**:
  - Reads and mutates bookmarks directly through the live `ReaderSession` (add, list, delete) so changes appear immediately via the session's own `ChangeNotifier`, discretely paginated like the file browser and TOC screen.
  - Prompts for a label defaulting to the current page number, confirms before deleting, and returns the tapped `Bookmark` to the caller.
- **[`lib/reader/screens/reader_settings_screen.dart`](lib/reader/screens/reader_settings_screen.dart)**:
  - Shows only the controls the current mode honours, and never repeats the fit-mode selector that already lives in the menu overlay: crop for Fit Height, crop plus overlap for Fit Width, and the zoom-out toggle for Zoom / Scroll. Text formats get the full typography panel instead.
- **[`lib/reader/screens/reader_toc_screen.dart`](lib/reader/screens/reader_toc_screen.dart)**:
  - Flattens nested document outlines into an indentation-preserving, discretely paginated navigation screen.
- **[`lib/reader/widgets/pdf_page_view.dart`](lib/reader/widgets/pdf_page_view.dart)**:
  - Presents tap-driven Fit Height/Width bitmaps, or the continuous Zoom / Scroll surface.
  - That surface owns its transform as a `scale` plus a scene-space `origin`, handles pans and pinches through a single scale `GestureDetector`, clamps exactly (centring content smaller than the viewport), and flings with per-axis `ClampingScrollSimulation` — Flutter's port of the AOSP `OverScroller` curve — driven from a bare `Ticker` so no rebuild can cancel momentum.
  - `InteractiveViewer` was removed deliberately: it fires `onInteractionEnd` *before* starting its fling (so reacting to the gesture blanked every tile exactly as the glide began), its `FrictionSimulation` curve decayed within a few frames on a ~30 fps panel, and its scale floor ignored `minScale` unless given `boundaryMargin` slack that then allowed panning into empty space.
  - Builds a two-dimensional tile grid bounded by `kPdfTileSidePixels`, positions tiles in screen pixels, requests each at the quantised zoom density, and settles the render scale only after both the gesture and any fling finish. Tiles awaiting bitmaps paint plain white at the correct size, never a spinner.
- **[`lib/reader/widgets/reader_menu_overlay.dart`](lib/reader/widgets/reader_menu_overlay.dart)**:
  - Supplies title, bookmarks, page status, page and percent jumps, contents, fit-mode selection, orientation, settings, and exit controls in high-contrast top and bottom bars.
- **[`lib/reader/widgets/tap_zone_layer.dart`](lib/reader/widgets/tap_zone_layer.dart)**:
  - Implements three equal-thirds tap zones — left/back, centre/menu, right/forward — with the right side always forward regardless of text direction, plus horizontal swipe page turns. In Zoom / Scroll it keeps the same tap thirds but registers no swipe recognizer, so pans and pinches reach the PDF surface below.
- **[`lib/reader/widgets/block_slice_view.dart`](lib/reader/widgets/block_slice_view.dart)** and **[`lib/reader/widgets/text_page_view.dart`](lib/reader/widgets/text_page_view.dart)**:
  - Render exact clipped semantic block slices and their embedded resources without scroll or transition animation.

#### Launcher Models (`lib/models/`)
- **[`lib/models/file_entry.dart`](lib/models/file_entry.dart)**:
  - Data model representing a file or directory with lazy stat caching.
- **[`lib/models/clipboard_state.dart`](lib/models/clipboard_state.dart)**:
  - Value object representing the in-memory clipboard state (copy/cut mode and source paths).
- **[`lib/models/launcher_app.dart`](lib/models/launcher_app.dart)**:
  - Minimal launchable-app record returned by Android, containing the label, package name, and system-app flag.

#### Controllers (`lib/controllers/`)
- **[`lib/controllers/file_browser_controller.dart`](lib/controllers/file_browser_controller.dart)**:
  - Central state manager for the file manager interface, handling navigation, selections, and filesystem mutations.

#### Services (`lib/services/`)
- **[`lib/services/app_list_service.dart`](lib/services/app_list_service.dart)**:
  - Queries and launches applications through the launcher-owned Android `PackageManager` channel, with separately cached user-only and system-inclusive lists.
- **[`lib/services/file_mime_type_service.dart`](lib/services/file_mime_type_service.dart)**:
  - Maps common document, ebook, text, media, archive, font, and interchange extensions to precise MIME types so Android only offers relevant apps.
- **[`lib/services/file_operations_service.dart`](lib/services/file_operations_service.dart)**:
  - Handles filesystem mutations (`dart:io`), recursive cloning, and collision-safe auto-renaming.
- **[`lib/services/folder_loader_service.dart`](lib/services/folder_loader_service.dart)**:
  - Persistent background `Isolate` for directory scanning and lazy stat fetching.
- **[`lib/services/open_with_service.dart`](lib/services/open_with_service.dart)**:
  - Opens Android's app chooser for a selected file, even when the device has a default app for its type.
- **[`lib/services/search_service.dart`](lib/services/search_service.dart)**:
  - Persistent background `Isolate` streaming filesystem search results.

#### Screens (`lib/screens/`)
- **[`lib/screens/file_browser_screen.dart`](lib/screens/file_browser_screen.dart)**:
  - Primary equal-band file browser with inverted opening feedback, live clock/battery status, MIME-aware opening, and a responsive selection bar that shows only applicable actions and expands to two rows when needed.
- **[`lib/screens/app_drawer_screen.dart`](lib/screens/app_drawer_screen.dart)**:
  - Application drawer with the same equal-band styling as the file browser, discrete pagination, and live as-you-type search.

#### Widgets (`lib/widgets/`)
- **[`lib/widgets/battery_status.dart`](lib/widgets/battery_status.dart)**:
  - Shows Android's live battery percentage with discrete level bars and a charging indicator, updating only on system battery broadcasts.
- **[`lib/widgets/clock_text.dart`](lib/widgets/clock_text.dart)**:
  - Minute-aligned digital clock widget.
- **[`lib/widgets/file_action_dialogs.dart`](lib/widgets/file_action_dialogs.dart)**:
  - Modal dialog builders and validators for folder creation, renaming, and deletion.
- **[`lib/widgets/file_entry_tile.dart`](lib/widgets/file_entry_tile.dart)**:
  - Stateless list row item representing a file/folder, with inverted selection and opening feedback.
- **[`lib/widgets/page_nav_bar.dart`](lib/widgets/page_nav_bar.dart)**:
  - Pagination navigation footer with first, previous, next, and last-page controls (`Page X of Y`).
- **[`lib/widgets/paginated_list.dart`](lib/widgets/paginated_list.dart)**:
  - Configurable height-calculated paginated container with fixed page sizes, optional empty-row filling, and no scroll physics.
- **[`lib/widgets/search_overlay.dart`](lib/widgets/search_overlay.dart)**:
  - Floating filename search panel.

---

### Test Suite (`test/`)

- **[`test/app_list_service_test.dart`](test/app_list_service_test.dart)**: Unit tests for native app-channel mapping, sorting, caching, query flags, and launch payloads.
- **[`test/file_action_dialogs_test.dart`](test/file_action_dialogs_test.dart)**: Widget tests verifying validation handling in dialogs.
- **[`test/file_mime_type_service_test.dart`](test/file_mime_type_service_test.dart)**: Unit tests for precise common types, case-insensitive extensions, and the non-wildcard fallback.
- **[`test/file_operations_service_test.dart`](test/file_operations_service_test.dart)**: Unit tests for filesystem mutations.
- **[`test/page_nav_bar_test.dart`](test/page_nav_bar_test.dart)**: Widget tests for first/previous/next/last controls and boundary-page jumps.
- **[`test/widget_test.dart`](test/widget_test.dart)**: Smoke tests verifying base UI rendering.
- **[`test/reader/doc_identity_service_test.dart`](test/reader/doc_identity_service_test.dart)**: Unit tests for docId computation.
- **[`test/reader/book_store_service_test.dart`](test/reader/book_store_service_test.dart)**: Unit tests for `library.json` persistence.
- **[`test/reader/page_bitmap_cache_test.dart`](test/reader/page_bitmap_cache_test.dart)**: Unit tests for memory budgeting and LRU eviction.
- **[`test/reader/pdf_continuous_layout_test.dart`](test/reader/pdf_continuous_layout_test.dart)**: Unit tests for exact extents, offset mapping, dominant-page selection, and boundary clamping.
- **[`test/reader/pdf_crop_service_test.dart`](test/reader/pdf_crop_service_test.dart)**: Unit tests for ink bounds, blank pages, alpha compositing, and noise filtering.
- **[`test/reader/pdf_document_service_test.dart`](test/reader/pdf_document_service_test.dart)**: Unit tests for PDF lifecycle/rendering and an opt-in native PDFium smoke test.
- **[`test/reader/pdf_reader_session_test.dart`](test/reader/pdf_reader_session_test.dart)**: Unit and widget tests for fit-mode navigation and sub-screens, whole-page cache reuse and physical-pixel sizing, the refusal to render whole pages in Zoom / Scroll, per-density and per-region tile re-rasterisation, navigation-epoch semantics, persistence, suspension/resumption, bookmark add/remove/cross-session persistence, and a fling that keeps gliding after release while respecting the end of the document.
- **[`test/reader/reader_bookmarks_screen_test.dart`](test/reader/reader_bookmarks_screen_test.dart)**: Widget tests for adding a bookmark with the default label, listing, tap-to-select, and delete-with-confirmation.
- **[`test/reader/reader_menu_overlay_test.dart`](test/reader/reader_menu_overlay_test.dart)**: Widget tests for reader-menu controls, the bookmarks entry point, and mode-specific actions.
- **[`test/reader/reader_session_registry_test.dart`](test/reader/reader_session_registry_test.dart)**: Unit tests for reader-session registry reuse and lifecycle management.
- **[`test/reader/reader_settings_test.dart`](test/reader/reader_settings_test.dart)**: Unit tests for settings persistence and legacy-value migration.
- **[`test/reader/reader_settings_screen_test.dart`](test/reader/reader_settings_screen_test.dart)**: Widget tests asserting each fit mode shows only its applicable controls, that the fit-mode selector is not duplicated, and that the zoom-out setting defaults to on and round-trips through JSON.
- **[`test/reader/reader_toc_screen_test.dart`](test/reader/reader_toc_screen_test.dart)**: Widget tests for flattened nested TOC navigation.
- **[`test/reader/tap_zone_layer_test.dart`](test/reader/tap_zone_layer_test.dart)**: Widget tests for equal-thirds tap boundaries, fixed navigation direction, and swipe callbacks.
- **[`test/reader/bidi_service_test.dart`](test/reader/bidi_service_test.dart)**: Unit tests for English, Hebrew with nikud, mixed text, numbers, and punctuation.
- **[`test/reader/hyphenation_service_test.dart`](test/reader/hyphenation_service_test.dart)**: Unit tests for Latin soft hyphens and preservation of Hebrew/inline styling.
- **[`test/reader/html_block_parser_test.dart`](test/reader/html_block_parser_test.dart)**: Unit tests for background XHTML parsing, block semantics, nested lists, images, bidi, and safe inline publisher styling.
- **[`test/reader/epub_parser_service_test.dart`](test/reader/epub_parser_service_test.dart)**: In-memory EPUB fixture tests covering metadata, spine, resources, nested nav TOC, logical anchors, and malformed containers.
- **[`test/reader/epub_paginator_service_test.dart`](test/reader/epub_paginator_service_test.dart)**: Exact line splitting, source-offset continuity, widow/orphan handling, and publisher-alignment tests.
- **[`test/reader/pagination_cache_service_test.dart`](test/reader/pagination_cache_service_test.dart)**: Versioned atomic cache round-trips, replacement, fractional geometry keys, and stale-entry rejection.
- **[`test/reader/text_block_parser_test.dart`](test/reader/text_block_parser_test.dart)**: Unit tests for TXT decoding and Markdown block parsing.
- **[`test/reader/text_reader_session_test.dart`](test/reader/text_reader_session_test.dart)**: Text navigation, persistence, re-pagination, suspension, logical page ordering, bookmark add/remove/cross-session persistence, and pending TOC-target tests.
- **[`test/reader/text_reader_settings_screen_test.dart`](test/reader/text_reader_settings_screen_test.dart)**: Widget tests for text-format typography controls.
- **[`test/reader/text_page_view_test.dart`](test/reader/text_page_view_test.dart)**: Widget coverage for rendering exact clip-and-offset block slices.
- **[`test/reader/phase2_verification_test.dart`](test/reader/phase2_verification_test.dart)**: Automated bundled-font, bilingual direction, exact slice coverage, portrait/landscape re-pagination, and timing verification.

---

### Native Android Configurations (`android/`)

- **[`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml)**:
  - Declares `MANAGE_EXTERNAL_STORAGE` and `QUERY_ALL_PACKAGES` permissions and registers Home Launcher intent.
- **[`android/app/src/main/kotlin/com/example/eink_launcher/MainActivity.kt`](android/app/src/main/kotlin/com/example/eink_launcher/MainActivity.kt)**:
  - Provides the native Android `Open with` chooser and event-driven battery-status channels.
- **[`android/app/src/main/kotlin/com/example/eink_launcher/InstalledAppsHandler.kt`](android/app/src/main/kotlin/com/example/eink_launcher/InstalledAppsHandler.kt)**:
  - Queries launcher activities and starts selected packages directly through Android `PackageManager`.
- **[`android/app/src/main/res/values/styles.xml`](android/app/src/main/res/values/styles.xml)**:
  - Window theme definitions configuring white background and fullscreen flags.
