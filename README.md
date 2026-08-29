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
│   │   └── file_entry.dart               # File/directory entity model with lazy stats
│   ├── reader/
│   │   ├── controllers/
│   │   │   ├── pdf_reader_session.dart   # PDF reader lifecycle, navigation & rendering
│   │   │   ├── reader_session.dart       # Shared reader session contract & view models
│   │   │   └── reader_session_registry.dart # Open-session lifecycle registry
│   │   ├── models/
│   │   │   ├── bookmark.dart             # Reader bookmark data model
│   │   │   ├── book_state.dart           # Per-document persisted state model
│   │   │   ├── doc_ref.dart              # Document format enum & identity model
│   │   │   ├── pdf_continuous_layout.dart # Exact PDF scroll extents & offset mapping
│   │   │   ├── reader_settings.dart      # Typography, display & fit settings model
│   │   │   ├── reading_position.dart     # Logical reading position (Pdf / Text)
│   │   │   └── toc_entry.dart            # Table of Contents hierarchy model
│   │   ├── services/
│   │   │   ├── book_store_service.dart   # library.json atomic persistence service
│   │   │   ├── doc_identity_service.dart # SHA-1 content fingerprinting service
│   │   │   ├── page_bitmap_cache.dart    # Memory-bounded LRU for rendered PDF pages
│   │   │   ├── pdf_crop_service.dart     # Isolate-backed PDF ink-bound detection
│   │   │   └── pdf_document_service.dart # pdfrx document open/render/outline wrapper
│   │   ├── screens/
│   │   │   ├── reader_screen.dart        # Full-bleed PDF reader shell & lifecycle hooks
│   │   │   └── reader_settings_screen.dart # Discrete PDF display settings
│   │   └── widgets/
│   │       ├── no_momentum_scroll_physics.dart # Drag-without-fling scroll behavior
│   │       ├── pdf_page_view.dart        # Cached PDF page, zoom & continuous views
│   │       ├── reader_menu_overlay.dart  # E-ink reader controls and page status
│   │       └── tap_zone_layer.dart       # Invisible tap zones and swipe navigation
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
│   ├── file_action_dialogs_test.dart     # Widget tests for input dialog validation
│   ├── file_mime_type_service_test.dart  # Common and fallback MIME mapping tests
│   ├── file_operations_service_test.dart # Unit tests for filesystem mutations & edge cases
│   ├── page_nav_bar_test.dart            # Boundary pagination control widget tests
│   ├── widget_test.dart                  # Basic UI smoke tests
│   └── reader/
│       ├── book_store_service_test.dart  # Unit tests for library.json persistence & reload
│       ├── doc_identity_service_test.dart# Unit tests for SHA-1 docId generation
│       ├── page_bitmap_cache_test.dart   # Unit tests for PDF bitmap LRU eviction
│       ├── no_momentum_scroll_physics_test.dart # No-fling physics unit test
│       ├── pdf_continuous_layout_test.dart # Exact scroll geometry mapping tests
│       ├── pdf_crop_service_test.dart    # Unit tests for crop bounds & noise filtering
│       ├── pdf_document_service_test.dart# PDF service unit tests & opt-in native smoke test
│       ├── pdf_reader_session_test.dart  # PDF session navigation, cache & lifecycle tests
│       ├── reader_session_registry_test.dart # Reader session registry lifecycle tests
│       ├── reader_settings_screen_test.dart # Discrete PDF settings widget tests
│       └── tap_zone_layer_test.dart      # Tap boundary and swipe-direction tests
└── android/                              # Native Android platform configuration
```

---

### Root Configuration & Documentation

- **[`ANDROID_HARDENING_PLAN.md`](ANDROID_HARDENING_PLAN.md)**: Prioritized, measurement-driven steps for hardening the Flutter launcher as an Android-only e-ink application.
- **[`README.md`](README.md)**: The primary project documentation file (this document), explaining the app's architecture, listing all files and their roles, and providing maintenance instructions.
- **[`READER_PLAN.md`](READER_PLAN.md)**: Architectural design blueprint and phased implementation plan for the integrated native document reader (PDF, EPUB, TXT, Markdown) with bidi Hebrew/English support.
- **[`analysis_options.yaml`](analysis_options.yaml)**: Configures Dart analyzer rules and linter options based on `package:flutter_lints`.
- **[`pubspec.yaml`](pubspec.yaml)**: Defines Flutter dependencies (`installed_apps`, `open_filex`, `permission_handler`, `shared_preferences`, `pdfrx`, `path_provider`, `crypto`), SDK constraints, and asset declarations.

---

### Core Source Code (`lib/`)

#### Top-Level
- **[`lib/main.dart`](lib/main.dart)**:
  - Initializes Flutter bindings and native plugins, including `pdfrxFlutterInitialize()`.
  - Leaves screen orientation under Android system control.
  - Enables `SystemUiMode.immersiveSticky` to keep Android system status and navigation bars hidden.
  - Builds the root `MaterialApp` with an E-Ink-optimized theme (monochrome color scheme, zero splash factory, square outlined buttons, custom popup menus) and boots `FileBrowserScreen`.
- **[`lib/constants.dart`](lib/constants.dart)**:
  - `kStorageRoot`: Fallback home directory and Android shared internal storage root (`/storage/emulated/0`).
  - `kRowHeight`: Default row height (`60.0` px) for generic paginated views; the file browser derives an exact shared height from its orientation band count.
  - `kNavBarHeight`: Default navigation height (`56.0` px); the file browser bottom bar instead matches its file and Up rows exactly.
  - `kPortraitBarCount` / `kLandscapeBarCount`: Total equal-height launcher bands in each orientation (`15` / `12`).
  - `noTransitionRoute()`: Custom `PageRouteBuilder` helper that wraps route transitions with `Duration.zero` to eliminate slide/fade animations.
  - `kReadableExtensions`: Set of supported extensions for the built-in reader (`.pdf`, `.epub`, `.txt`, `.md`).
  - `kTapZoneEdgeWidthRatio` / `kTapZoneCenterWidthRatio` / `kTapZoneZoomEdgeRatio`: Proportions for invisible tap-turn and menu zones.
  - `kPdfDefaultSplitOverlap`: Default vertical slice overlap (6%) for fit-width and continuous scroll page turns.
  - `kPdfMaxRenderDimension`: Longest-edge pixel rendering ceiling (`2048.0` px).
  - `kPdfInkLuminanceThreshold`: Bounding box detection ink luminance cutoff (`245`).
  - `kReaderFontSizeSteps` / `kReaderMarginSteps`: Step tables for typography and margin configuration.

#### Reader Module (`lib/reader/`)

The Phase 1 PDF path and Phase 1b continuous-scroll mode are wired end-to-end:
selecting a PDF in the file browser opens the built-in full-screen reader.
EPUB, TXT, and Markdown remain declared future formats and continue opening
through Android until the shared text reader arrives in Phases 2–3.

##### Controllers

- **[`lib/reader/controllers/reader_session.dart`](lib/reader/controllers/reader_session.dart)**:
  - Defines the shared reader-session lifecycle, navigation, rendering, and viewport contracts.
- **[`lib/reader/controllers/pdf_reader_session.dart`](lib/reader/controllers/pdf_reader_session.dart)**:
  - Implements PDF session loading, navigation, fit modes, continuous offset mapping, persistence, and cached viewport rendering.
- **[`lib/reader/controllers/reader_session_registry.dart`](lib/reader/controllers/reader_session_registry.dart)**:
  - Tracks open document sessions and coordinates suspension, resumption, and disposal.

##### Models and Services

- **[`lib/reader/models/doc_ref.dart`](lib/reader/models/doc_ref.dart)**:
  - `DocFormat` enum (`pdf`, `epub`, `txt`, `markdown`).
  - `DocRef` model representing document identity, location, format, title, and size.
- **[`lib/reader/models/reading_position.dart`](lib/reader/models/reading_position.dart)**:
  - Sealed `ReadingPosition` hierarchy (`PdfReadingPosition` with fractional page offset and `TextReadingPosition` with spine, block, and character offsets).
- **[`lib/reader/models/pdf_continuous_layout.dart`](lib/reader/models/pdf_continuous_layout.dart)**:
  - Calculates exact fit-width page heights, cumulative offsets, logical-position conversions, and the page occupying most of the viewport.
- **[`lib/reader/models/reader_settings.dart`](lib/reader/models/reader_settings.dart)**:
  - Reader configuration model encompassing fonts, font size steps, margins, line height, hyphenation, justification, `PdfFitMode`, and `ParagraphMode`.
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
- **[`lib/reader/services/page_bitmap_cache.dart`](lib/reader/services/page_bitmap_cache.dart)**:
  - Owns rendered Flutter images in a 40 MB least-recently-used cache and disposes replaced or evicted bitmaps.
- **[`lib/reader/services/pdf_crop_service.dart`](lib/reader/services/pdf_crop_service.dart)**:
  - Detects padded ink bounds on a background isolate, distinguishes blank samples, and unions up to ten spread page samples for stable document-uniform cropping.
- **[`lib/reader/services/pdf_document_service.dart`](lib/reader/services/pdf_document_service.dart)**:
  - Owns the `pdfrx` document handle and provides capped page rendering, page geometry, and PDF-outline conversion.

##### Screens and Widgets

- **[`lib/reader/screens/reader_screen.dart`](lib/reader/screens/reader_screen.dart)**:
  - Obtains long-lived sessions from the registry, presents a full-bleed PDF, coordinates app pause/resume persistence, and applies manual portrait/landscape locks.
- **[`lib/reader/screens/reader_settings_screen.dart`](lib/reader/screens/reader_settings_screen.dart)**:
  - Provides discrete fit-mode, auto-crop, momentum, and overlap controls without animated switches or sliders.
- **[`lib/reader/widgets/no_momentum_scroll_physics.dart`](lib/reader/widgets/no_momentum_scroll_physics.dart)**:
  - Allows direct vertical dragging but returns no ballistic simulation, so release stops immediately by default.
- **[`lib/reader/widgets/pdf_page_view.dart`](lib/reader/widgets/pdf_page_view.dart)**:
  - Presents tap-driven bitmaps, free zoom, or an exact-extent lazy continuous list with two-viewports of render look-ahead.
- **[`lib/reader/widgets/reader_menu_overlay.dart`](lib/reader/widgets/reader_menu_overlay.dart)**:
  - Supplies page status, previous/next, fit, crop, orientation, settings, and exit controls in high-contrast top and bottom bars.
- **[`lib/reader/widgets/tap_zone_layer.dart`](lib/reader/widgets/tap_zone_layer.dart)**:
  - Implements fixed left/back, centre/menu, and right/forward tap zones plus horizontal swipes; free zoom narrows the edge targets and preserves PDF pan gestures.

#### Launcher Models (`lib/models/`)
- **[`lib/models/file_entry.dart`](lib/models/file_entry.dart)**:
  - Data model representing a file or directory with lazy stat caching.
- **[`lib/models/clipboard_state.dart`](lib/models/clipboard_state.dart)**:
  - Value object representing the in-memory clipboard state (copy/cut mode and source paths).

#### Controllers (`lib/controllers/`)
- **[`lib/controllers/file_browser_controller.dart`](lib/controllers/file_browser_controller.dart)**:
  - Central state manager for the file manager interface, handling navigation, selections, and filesystem mutations.

#### Services (`lib/services/`)
- **[`lib/services/app_list_service.dart`](lib/services/app_list_service.dart)**:
  - Interfaces with `installed_apps` to retrieve and launch installed applications.
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

- **[`test/file_action_dialogs_test.dart`](test/file_action_dialogs_test.dart)**: Widget tests verifying validation handling in dialogs.
- **[`test/file_mime_type_service_test.dart`](test/file_mime_type_service_test.dart)**: Unit tests for precise common types, case-insensitive extensions, and the non-wildcard fallback.
- **[`test/file_operations_service_test.dart`](test/file_operations_service_test.dart)**: Unit tests for filesystem mutations.
- **[`test/page_nav_bar_test.dart`](test/page_nav_bar_test.dart)**: Widget tests for first/previous/next/last controls and boundary-page jumps.
- **[`test/widget_test.dart`](test/widget_test.dart)**: Smoke tests verifying base UI rendering.
- **[`test/reader/doc_identity_service_test.dart`](test/reader/doc_identity_service_test.dart)**: Unit tests for docId computation.
- **[`test/reader/book_store_service_test.dart`](test/reader/book_store_service_test.dart)**: Unit tests for `library.json` persistence.
- **[`test/reader/page_bitmap_cache_test.dart`](test/reader/page_bitmap_cache_test.dart)**: Unit tests for memory budgeting and LRU eviction.
- **[`test/reader/no_momentum_scroll_physics_test.dart`](test/reader/no_momentum_scroll_physics_test.dart)**: Unit test proving release creates no ballistic fling.
- **[`test/reader/pdf_continuous_layout_test.dart`](test/reader/pdf_continuous_layout_test.dart)**: Unit tests for exact extents, offset mapping, dominant-page selection, and boundary clamping.
- **[`test/reader/pdf_crop_service_test.dart`](test/reader/pdf_crop_service_test.dart)**: Unit tests for ink bounds, blank pages, alpha compositing, and noise filtering.
- **[`test/reader/pdf_document_service_test.dart`](test/reader/pdf_document_service_test.dart)**: Unit tests for PDF lifecycle/rendering and an opt-in native PDFium smoke test.
- **[`test/reader/pdf_reader_session_test.dart`](test/reader/pdf_reader_session_test.dart)**: Unit and widget tests for PDF navigation, fit and continuous modes, persistence, caching, suspension, and resumption.
- **[`test/reader/reader_session_registry_test.dart`](test/reader/reader_session_registry_test.dart)**: Unit tests for reader-session registry reuse and lifecycle management.
- **[`test/reader/reader_settings_screen_test.dart`](test/reader/reader_settings_screen_test.dart)**: Widget tests for discrete PDF settings controls.
- **[`test/reader/tap_zone_layer_test.dart`](test/reader/tap_zone_layer_test.dart)**: Widget tests for tap boundaries, fixed navigation direction, and swipe callbacks.

---

### Native Android Configurations (`android/`)

- **[`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml)**:
  - Declares `MANAGE_EXTERNAL_STORAGE` and `QUERY_ALL_PACKAGES` permissions and registers Home Launcher intent.
- **[`android/app/src/main/kotlin/com/example/eink_launcher/MainActivity.kt`](android/app/src/main/kotlin/com/example/eink_launcher/MainActivity.kt)**:
  - Provides the native Android `Open with` chooser and event-driven battery-status channels.
- **[`android/app/src/main/res/values/styles.xml`](android/app/src/main/res/values/styles.xml)**:
  - Window theme definitions configuring white background and fullscreen flags.
