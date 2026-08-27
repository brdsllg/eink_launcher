* this file is ai generated, so skepticism is allowed and even encouraged 


# E-Ink Launcher & File Manager

An Android home launcher and file manager built with Flutter, designed specifically for E-Ink devices (such as the Bigme B751C).

---

## 📖 Overview & Design Principles

Standard Android launchers and file explorers rely heavily on smooth animations, kinetic flings, vibrant colors, and rapid screen updates. On electronic paper displays (E-Ink), these behaviors cause severe ghosting, visual stutter, and battery drain.

This project is tailored for E-Ink displays around five core architectural pillars:
1. **High-Contrast Monochrome UI:** Pure black-and-white theme (`#000000` / `#FFFFFF`) with crisp borders and inverse highlighting. No gradients, shadows, or gray-on-gray elements.
2. **Zero Animation / Instant Transitions:** Standard route animations, splash effects, ripple feedback, and sliding snackbars are completely disabled (`Duration.zero`, `NoSplash.splashFactory`, `noTransitionRoute`).
3. **Discrete Pagination over Kinetic Scrolling:** Lists (file browser, app drawer) compute exact row fits and paginate screen-by-screen using explicit Previous/Next controls, eliminating smooth scrolling ghosting.
4. **Isolate-Based Background I/O:** Heavy filesystem listings, recursive searches, and metadata statting run on long-lived background isolates to keep the UI thread responsive.
5. **Minute-Aligned Timers:** UI timers (such as the clock readout) align strictly to minute boundaries to prevent unneeded per-second display refreshes.

---

## 🗂️ Project Directory & File Guide

Below is an exhaustive description of every significant file and directory in this project.

```
eink_launcher/
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
│   │   ├── models/
│   │   │   ├── bookmark.dart             # Reader bookmark data model
│   │   │   ├── book_state.dart           # Per-document persisted state model
│   │   │   ├── doc_ref.dart              # Document format enum & identity model
│   │   │   ├── reader_settings.dart      # Typography, display & fit settings model
│   │   │   ├── reading_position.dart     # Logical reading position (Pdf / Text)
│   │   │   └── toc_entry.dart            # Table of Contents hierarchy model
│   │   └── services/
│   │       ├── book_store_service.dart   # library.json atomic persistence service
│   │       └── doc_identity_service.dart # SHA-1 content fingerprinting service
│   ├── screens/
│   │   ├── app_drawer_screen.dart        # Paginated application drawer & search screen
│   │   └── file_browser_screen.dart      # Main home file manager screen
│   ├── services/
│   │   ├── app_list_service.dart         # Installed app discovery & launch service
│   │   ├── file_operations_service.dart  # File mutation logic (create, rename, delete, paste)
│   │   ├── folder_loader_service.dart    # Isolate-backed folder listing & lazy stat loader
│   │   └── search_service.dart           # Isolate-backed streaming filesystem search
│   └── widgets/
│       ├── clock_text.dart               # Minute-aligned e-ink digital clock widget
│       ├── file_action_dialogs.dart      # Modal dialogs for new folder, rename, & delete
│       ├── file_entry_tile.dart          # High-contrast file/folder list item row
│       ├── page_nav_bar.dart             # Pagination footer (Page X of Y, Prev/Next)
│       ├── paginated_list.dart           # Generic height-calculated paginated list container
│       └── search_overlay.dart           # Floating filename search bar with streaming matches
├── test/
│   ├── file_action_dialogs_test.dart     # Widget tests for input dialog validation
│   ├── file_operations_service_test.dart # Unit tests for filesystem mutations & edge cases
│   ├── widget_test.dart                  # Basic UI smoke tests
│   └── reader/
│       ├── book_store_service_test.dart  # Unit tests for library.json persistence & reload
│       └── doc_identity_service_test.dart# Unit tests for SHA-1 docId generation
└── android/                              # Native Android platform configuration
```

---

### Root Configuration & Documentation

- **[`README.md`](README.md)**: The primary project documentation file (this document), explaining the app's architecture, listing all files and their roles, and providing maintenance instructions.
- **[`READER_PLAN.md`](READER_PLAN.md)**: Architectural design blueprint and phased implementation plan for the integrated native document reader (PDF, EPUB, TXT, Markdown) with bidi Hebrew/English support.
- **[`analysis_options.yaml`](analysis_options.yaml)**: Configures Dart analyzer rules and linter options based on `package:flutter_lints`.
- **[`pubspec.yaml`](pubspec.yaml)**: Defines Flutter dependencies (`installed_apps`, `open_filex`, `permission_handler`, `shared_preferences`, `pdfrx`, `path_provider`, `crypto`), SDK constraints, and asset declarations.

---

### Core Source Code (`lib/`)

#### Top-Level
- **[`lib/main.dart`](lib/main.dart)**:
  - Initializes Flutter bindings and native plugins, including `pdfrxFlutterInitialize()`.
  - Locks screen orientation to `DeviceOrientation.portraitUp`.
  - Enables `SystemUiMode.immersiveSticky` to keep Android system status and navigation bars hidden.
  - Builds the root `MaterialApp` with an E-Ink-optimized theme (monochrome color scheme, zero splash factory, square outlined buttons, custom popup menus) and boots `FileBrowserScreen`.
- **[`lib/constants.dart`](lib/constants.dart)**:
  - `kStorageRoot`: Fallback home directory and Android shared internal storage root (`/storage/emulated/0`).
  - `kRowHeight`: Fixed row height (`48.0` px) for list items across all paginated views.
  - `kNavBarHeight`: Fixed height (`48.0` px) for pagination navigation bars.
  - `noTransitionRoute()`: Custom `PageRouteBuilder` helper that wraps route transitions with `Duration.zero` to eliminate slide/fade animations.
  - `kReadableExtensions`: Set of supported extensions for the built-in reader (`.pdf`, `.epub`, `.txt`, `.md`).
  - `kTapZoneEdgeWidthRatio` / `kTapZoneCenterWidthRatio` / `kTapZoneZoomEdgeRatio`: Proportions for invisible tap-turn and menu zones.
  - `kPdfDefaultSplitOverlap`: Default vertical slice overlap (6%) for fit-width and continuous scroll page turns.
  - `kPdfMaxRenderDimension`: Longest-edge pixel rendering ceiling (`2048.0` px).
  - `kPdfInkLuminanceThreshold`: Bounding box detection ink luminance cutoff (`245`).
  - `kReaderFontSizeSteps` / `kReaderMarginSteps`: Step tables for typography and margin configuration.

#### Reader Module (`lib/reader/`)
- **[`lib/reader/models/doc_ref.dart`](lib/reader/models/doc_ref.dart)**:
  - `DocFormat` enum (`pdf`, `epub`, `txt`, `markdown`).
  - `DocRef` model representing document identity, location, format, title, and size.
- **[`lib/reader/models/reading_position.dart`](lib/reader/models/reading_position.dart)**:
  - Sealed `ReadingPosition` hierarchy (`PdfReadingPosition` with fractional page offset and `TextReadingPosition` with spine, block, and character offsets).
- **[`lib/reader/models/reader_settings.dart`](lib/reader/models/reader_settings.dart)**:
  - Reader configuration model encompassing fonts, font size steps, margins, line height, hyphenation, justification, `PdfFitMode`, and `ParagraphMode`.
- **[`lib/reader/models/bookmark.dart`](lib/reader/models/bookmark.dart)**:
  - Document bookmark entity mapping creation time and label to a logical `ReadingPosition`.
- **[`lib/reader/models/toc_entry.dart`](lib/reader/models/toc_entry.dart)**:
  - Hierarchical Table of Contents tree entry with nesting support.
- **[`lib/reader/models/book_state.dart`](lib/reader/models/book_state.dart)**:
  - Comprehensive document persistence state holding reading progress, timestamp, document overrides, bookmarks, and cached crop rects.
- **[`lib/reader/services/doc_identity_service.dart`](lib/reader/services/doc_identity_service.dart)**:
  - Generates stable `sha1(first 64 KB + fileSize)` document keys so moved/renamed files retain reading positions.
- **[`lib/reader/services/book_store_service.dart`](lib/reader/services/book_store_service.dart)**:
  - Manages `library.json` using atomic write-to-temp-then-rename and 2-second debounced background flushing.

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
- **[`lib/services/file_operations_service.dart`](lib/services/file_operations_service.dart)**:
  - Handles filesystem mutations (`dart:io`), recursive cloning, and collision-safe auto-renaming.
- **[`lib/services/folder_loader_service.dart`](lib/services/folder_loader_service.dart)**:
  - Persistent background `Isolate` for directory scanning and lazy stat fetching.
- **[`lib/services/search_service.dart`](lib/services/search_service.dart)**:
  - Persistent background `Isolate` streaming filesystem search results.

#### Screens (`lib/screens/`)
- **[`lib/screens/file_browser_screen.dart`](lib/screens/file_browser_screen.dart)**:
  - Primary launcher home screen featuring high-contrast file browser and actions.
- **[`lib/screens/app_drawer_screen.dart`](lib/screens/app_drawer_screen.dart)**:
  - Application drawer with discrete pagination and app search.

#### Widgets (`lib/widgets/`)
- **[`lib/widgets/clock_text.dart`](lib/widgets/clock_text.dart)**:
  - Minute-aligned digital clock widget.
- **[`lib/widgets/file_action_dialogs.dart`](lib/widgets/file_action_dialogs.dart)**:
  - Modal dialog builders and validators for folder creation, renaming, and deletion.
- **[`lib/widgets/file_entry_tile.dart`](lib/widgets/file_entry_tile.dart)**:
  - Stateless list row item representing a file/folder.
- **[`lib/widgets/page_nav_bar.dart`](lib/widgets/page_nav_bar.dart)**:
  - Pagination navigation footer (`Page X of Y`).
- **[`lib/widgets/paginated_list.dart`](lib/widgets/paginated_list.dart)**:
  - Height-calculated paginated list container without scroll physics.
- **[`lib/widgets/search_overlay.dart`](lib/widgets/search_overlay.dart)**:
  - Floating filename search panel.

---

### Test Suite (`test/`)

- **[`test/file_action_dialogs_test.dart`](test/file_action_dialogs_test.dart)**: Widget tests verifying validation handling in dialogs.
- **[`test/file_operations_service_test.dart`](test/file_operations_service_test.dart)**: Unit tests for filesystem mutations.
- **[`test/widget_test.dart`](test/widget_test.dart)**: Smoke tests verifying base UI rendering.
- **[`test/reader/doc_identity_service_test.dart`](test/reader/doc_identity_service_test.dart)**: Unit tests for docId computation.
- **[`test/reader/book_store_service_test.dart`](test/reader/book_store_service_test.dart)**: Unit tests for `library.json` persistence.

---

### Native Android Configurations (`android/`)

- **[`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml)**:
  - Declares `MANAGE_EXTERNAL_STORAGE` and `QUERY_ALL_PACKAGES` permissions and registers Home Launcher intent.
- **[`android/app/src/main/res/values/styles.xml`](android/app/src/main/res/values/styles.xml)**:
  - Window theme definitions configuring white background and fullscreen flags.
