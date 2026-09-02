# E-Ink Launcher & File Manager

An Android home launcher, file manager, and document reader built with Flutter
for e-ink devices. The UI uses black and white, instant transitions, fixed-page
lists, and small bounded caches to limit ghosting and unnecessary work.

The app is developed for personal sideloading and has been manually tested on a
Bigme HiBreak running Android 14. The original target was the Bigme B751C.

## Current status

Version **1.0.2 (build 3)** is the latest verified build. The current APK is
[eink-launcher-1.0.2-scroll-previews.apk](build/app/outputs/flutter-apk/eink-launcher-1.0.2-scroll-previews.apk).

- Rapid PDF page taps now work in the HiBreak test.
- Zoom / Scroll keeps coarse previews visible while sharp tiles render, stores
  prepared previews in a 64 MiB disk cache, and looks farther ahead during fast
  flings.
- Touching the PDF immediately stops scrolling momentum; no reverse drag is
  required.
- Very fast first-pass scrolling at minimum zoom can still outrun PDF rendering.
  Revisiting prepared pages should be much faster, but version 1.0.2 still needs
  an on-device comparison.
- The full suite passes **240 Flutter tests** with the generated native PDFium
  stress check enabled. The older test that requires an external PDF is skipped.
  Static analysis is clean.

The APK is an arm64 release build signed with the project's existing personal
sideload key. Its Android v2 signature and package/version metadata were checked.
SHA-256:
`8231F46FF8A086EF84C50AA416EADE9589A64E0599F7EB45CD7F2EA6D0317CAB`.

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
search for text formats.

PDF has three modes:

- **Fit Height:** one page per screen.
- **Fit Width:** page-height slices with a small overlap.
- **Zoom / Scroll:** continuous two-axis pan, pinch zoom, and momentum. Coarse
  page previews remain beneath sharp PDFium tiles during movement.

EPUB, TXT, and Markdown share a paginated text pipeline with bundled Latin and
Hebrew fonts, bidi paragraph handling, exact line-boundary splits, safe publisher
styles, optional hyphenation, and typography controls.

Reader sessions retain logical positions rather than display page numbers, so
changes to font size, orientation, crop, or PDF mode keep the user's place. Hidden
sessions release native PDF handles and bitmaps to control memory.

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

- Compare first and second passes through the same PDF in Zoom / Scroll.
- Recheck zoom-release continuity and fast scrolling with both vector and scanned
  PDFs.
- Measure cold start, memory, first PDF open, and sustained PDF use.
- Exercise real process restart/recovery, battery receiver reattachment, the
  Android chooser, app discovery/launching, and Impeller versus the legacy renderer.

The raw HiBreak observations are in [BIGME_TEST_LOG.md](BIGME_TEST_LOG.md). The
implemented PDF response work and short retest are in
[PDF_RESPONSIVENESS.md](PDF_RESPONSIVENESS.md).

## Plans

- [READER_PLAN.md](READER_PLAN.md) records reader behavior, architecture, remaining
  checks, and tab suggestions.
- [ANDROID_HARDENING_PLAN.md](ANDROID_HARDENING_PLAN.md) records completed Android
  hardening decisions and the remaining measurement-driven work.
