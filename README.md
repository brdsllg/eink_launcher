# E-Ink Launcher & File Manager

An Android home launcher, file manager, and document reader built with Flutter
for e-ink devices. The UI uses black and white, instant transitions, fixed-page
lists, and small bounded caches to limit ghosting and unnecessary work.

The app is developed for personal sideloading and has been manually tested on a
Bigme HiBreak running Android 14. The original target was the Bigme B751C.

## Current status

**Current trial: version 1.0.9 (build 10)** adds physical page-button support for
the Bigme B751C: Page Up/Down, Left/Right, and Volume Up/Down. The buttons turn
reader pages and page through file, Apps, bookmark, Contents, and search-result
lists. Holds do not repeat, text entry and dialogs are isolated, and loading or
background readers do not turn. [Button behavior and supported assignments](BUTTON_SUPPORT.md).
The APK is [eink-launcher-1.0.9-b751c-buttons-trial.apk](build/app/outputs/flutter-apk/eink-launcher-1.0.9-b751c-buttons-trial.apk).
Physical B751C verification remains pending.

**Design trial: version 1.0.8 (build 9)** gives each screen a layout suited to
its controls. Reader header icons use bounded widths, rotation has a wider
labeled cell, and three equal tabs share the remaining space between arrows.
The requested **1:2:3:1:1:1** status row and equal-third PDF modes remain intact.

The browser, Apps, all list pagers, selection actions, search, settings, dialogs,
and recovery screens now use aligned rectangular cells with suitable widths.
Settings choices divide by their option count; labels move into a shared column
on wide screens. Menus remain single-column command lists. Forms and recovery
actions adapt to narrow screens and the keyboard. Browser/Apps vertical bands
are preserved. [Layout decisions and comparisons](LAYOUT_DESIGN.md) explain the
dimensions chosen for each area, with preview links.

The trial APK is [eink-launcher-1.0.8-area-grids-trial.apk](build/app/outputs/flutter-apk/eink-launcher-1.0.8-area-grids-trial.apk).
The full suite passes **279 Flutter tests**, including native PDFium stress;
one external-PDF test is skipped. All 35 portrait, landscape, and narrow-screen
visual cases pass, covering all screen types and dialogs; the final combined
settings/search/visual run passes 41 checks. Static analysis is clean.
The latest trial has not been installed on
the device. Previous trial APKs remain available.

Version **1.0.3 (build 4)** introduced reader tabs. Its comparison APK is
[eink-launcher-1.0.3-tabs.apk](build/app/outputs/flutter-apk/eink-launcher-1.0.3-tabs.apk).
Automated tests and portrait/landscape layout checks pass. The HiBreak device
observations below are from version 1.0.2; this tab build has not been installed
or physically tested on the device yet.

- Open tabs, selection, and reading order survive restart. The menu strip
  switches and closes tabs; the browser's **+ → Tabs** action returns to reading.
- Rapid PDF page taps now work in the HiBreak test.
- Zoom / Scroll keeps coarse previews visible while sharp tiles render, stores
  prepared previews in a 64 MiB disk cache, and looks farther ahead during fast
  flings.
- Touching the PDF immediately stops scrolling momentum; no reverse drag is
  required.
- Very fast first-pass scrolling at minimum zoom can still outrun PDF rendering.
  An ADB device pass exercised vector/scanned PDFs, pinch, scrolling, and restore;
  sampled images retained content. On 2026-09-02 the user also confirmed no
  ghosting or white flashes on the physical screen.
- Version 1.0.3 passed **277 Flutter tests** with the generated native PDFium
  stress check enabled. The older test that requires an external PDF is skipped.
  Static analysis is clean.

The version 1.0.9 trial APK is an arm64 release build signed with the project's
existing personal sideload key. Its Android v2 signature and package/version
metadata were checked.
SHA-256:
`BD8A8E7CF407886C800139463722004B509144F5DAE3E3C38AD2CB2A0015C32E`.

## What the app does

### Launcher and file manager

- Registers as an Android Home launcher and provides a paginated app drawer.
- Browses, searches, creates, renames, copies, moves, and deletes files.
- Uses 15 equal-height screen bands in portrait and 12 in landscape, including
  the top and bottom controls.
- Runs folder loading, recursive search, and metadata work outside the UI isolate.
- Opens ordinary files with Android and provides an explicit **Open with** chooser.
- Shows event-driven battery status and a minute-aligned clock.

Startup has loading, ready, and recovery states. A bad saved home folder falls
back to internal storage and clears only that setting. Repeated unfinished
launches open recovery controls with access to the app drawer. Local diagnostics
are bounded and are never uploaded.

### Built-in reader

The reader opens PDF, EPUB, TXT, and Markdown files directly from the browser.
It provides equal-thirds tap zones, swipes where appropriate, manual rotation,
per-document positions and settings, bookmarks, tables of contents, and text
search for text formats. The reader menu also contains a paged strip of open
tabs. Back keeps a tab open; its corner X closes it. The browser's **+ → Tabs**
action returns to the most recently read tab, including after a restart.

PDF has three modes:

- **Fit Height:** one page per screen.
- **Fit Width:** page-height slices with a small overlap.
- **Zoom / Scroll:** continuous two-axis pan, pinch zoom, and momentum. Coarse
  page previews remain beneath sharp PDFium tiles during movement.

EPUB, TXT, and Markdown share a paginated text pipeline with bundled Latin and
Hebrew fonts, bidi paragraph handling, exact line-boundary splits, safe publisher
styles, optional hyphenation, and typography controls. Broken Latin words have
explicitly painted hyphens, including at page boundaries. Parsed EPUB chapters
and images are cached on disk (64 MiB limit); source changes and publisher-style
changes invalidate the cache. TXT detects likely hard-wrapped prose and paragraph
indents while preserving deliberate line breaks in other text.

Reader settings default to **Black and white**. Toggle **Page color** to show
color PDF content and EPUB/Markdown images; the choice is saved per document.
PDF **Image dithering** is optional and off by default. It quantizes gradients
to 16 levels, per channel in color mode. Try it for scanned pages or photographs
on the Bigme B751C; device processing can affect whether it looks better.

Fit modes prefetch one page in the reading direction, increasing to two during
rapid turns. Cached previews appear while sharp pages render, including compatible
whole-page previews when switching fit modes. Color and dithering changes
invalidate retained raster images and use separate disk-preview keys.

Reader sessions retain logical positions rather than display page numbers, so
changes to font size, orientation, crop, or PDF mode keep the user's place.
Suspension releases native PDF handles and bitmaps. Switching tabs explicitly
suspends hidden sessions. Tab order and selection persist alongside reading
positions; restoring the tab list does not open any document. Opening a PDF reuses
its cached first-page preview when available, with a static loading indicator.

## E-ink design rules

1. Use pure black and white with strong borders and no gradients or shadows.
2. Disable route, ripple, splash, and snackbar animations.
3. Use discrete pagination for the launcher, browser, app drawer, and text reader.
4. Allow continuous motion only in PDF Zoom / Scroll, where it is the purpose of
   the mode.
5. Bound native rendering, prefetch, bitmap memory, and persistent preview storage.
6. Keep expensive file work and parsing away from the UI isolate where possible.

## Project map

| Location | Purpose |
| --- | --- |
| `lib/main.dart` | App startup, theme, lifecycle, and memory-pressure handling |
| `lib/controllers/`, `lib/screens/`, `lib/widgets/` | File browser and launcher UI |
| `lib/services/` | File operations, search, app discovery, Android bridges, startup health |
| `lib/reader/controllers/` | PDF/text sessions and session lifecycle |
| `lib/reader/services/` | Parsing, pagination, persistence, PDF rendering, scheduling, and caches |
| `lib/reader/screens/`, `lib/reader/widgets/` | Reader shell, menus, navigation, and document views |
| `android/app/src/main/` | Android manifest, launcher activity, native channels, and startup marker |
| `test/` | Flutter unit, widget, integration-style, and optional native PDF tests |
| `android/app/src/test/` | Native JVM startup-policy tests |

Use `rg --files lib test android/app/src` when a complete file list is needed;
the source tree is more reliable than a manually maintained catalog.

## Build and verify

From the repository root:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --target-platform android-arm64 --no-pub
```

Run the generated native PDFium check on a supported host with:

```powershell
$env:PDF_NATIVE_STRESS = '1'
flutter test --no-pub test/reader/pdf_native_render_stress_test.dart
Remove-Item Env:PDF_NATIVE_STRESS
```

Run native Android policy tests on Windows with:

```powershell
android\gradlew.bat -p android :app:testDebugUnitTest
```

Personal sideload builds use the existing local signing setup. Do not remove
`open_filex` without first adding an app-owned `FileProvider`; the custom chooser
currently uses its provider authority. A private release keystore is needed only
before distribution or moving the signing identity to another machine.

## What still needs device testing

The [2026-09-02 ADB report](DEVICE_VALIDATION_2026-09-02.md) records completed
reader, restart/recovery, battery, chooser, app-drawer, cold-start, and memory
checks, including both renderers. The user subsequently confirmed no ghosting or
white flashes, completing the outstanding physical-screen check for the observed
conditions. Precise first-preview/sharpen timings, renderer preference, and
unplugged idle battery drain remain optional measurements, not blockers for tabs
planning.

The raw HiBreak observations are in [BIGME_TEST_LOG.md](BIGME_TEST_LOG.md). The
implemented PDF response work and short retest are in
[PDF_RESPONSIVENESS.md](PDF_RESPONSIVENESS.md).

## Plans

- [READER_PLAN.md](READER_PLAN.md) records reader behavior, architecture, remaining
  checks, and the implemented tab design.
- [ANDROID_HARDENING_PLAN.md](ANDROID_HARDENING_PLAN.md) records completed Android
  hardening decisions and the remaining measurement-driven work.
