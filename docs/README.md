# E-Ink Launcher & File Manager

> **Note for anyone (human or AI) helping with this project:** the owner does not
> code. Keep explanations and instructions non-technical, and give copy-paste
> commands rather than code changes to make by hand.

An Android home launcher, file manager, and document reader built with Flutter for
e-ink devices. It uses black and white, instant transitions, fixed-page lists, and
small bounded caches to limit ghosting and wasted work. It is built for personal
sideloading. It has been tested on a Bigme HiBreak (Android 14); the original
target was the Bigme B751C.

## Where things stand

- **Current release:** version 1.0.10 (build 11). APK:
  `build/app/outputs/flutter-apk/app-release.apk`
  (SHA-256 `01D04659FC1BEB73F5A7F8767A357ACAA1E7078E82CA8701E9C1A4C80958706E`).
  Earlier trial APKs stay in the same folder for comparison.
- **Latest checks (5 Oct 2026):** 436 automated tests pass. The one failure, in the
  PDF runtime test, also occurs without recent changes and is unrelated. Static
  analysis shows only two minor `avoid_print` notices.
- **Current device status:** several areas are confirmed on the Bigme, but the
  remaining work is still concentrated in tabs, newer layouts, selection and
  annotations, dictionaries, and study books. This project does not treat any of
  those partial checks as complete. See [DEVICE_TESTING.md](DEVICE_TESTING.md).
- **Confirmed on the device:** PDF page turns, scrolling and zooming with no
  ghosting or white flashes; startup, recovery, app drawer, and battery behavior
  (2 Sept); physical page buttons (18 Sept). The status of newer features is
  tracked in the device checklist rather than assumed to be complete.

## What the app does

### Launcher and file manager

- Works as an Android Home launcher with a paginated app drawer.
- Browses, searches, creates, renames, copies, moves, and deletes files.
- Uses 15 equal-height screen bands in portrait and 12 in landscape.
- Opens ordinary files with Android, with an explicit **Open with** chooser.
- Shows battery status and a minute-accurate clock.
- Startup has loading, ready, and recovery states. A bad saved home folder falls
  back to internal storage. Repeated unfinished launches open recovery controls
  with access to the app drawer. Diagnostics stay on the device.

### Reader

Opens PDF, EPUB, TXT, and Markdown directly from the file browser.

- **Reading controls:** equal-thirds tap zones, swipes, manual rotation,
  per-document positions and settings, bookmarks, tables of contents, and text
  search for text formats.
- **Tabs:** open books form a strip of tabs in the reader menu. Back keeps a tab
  open; its X closes it. **+ → Tabs** in the browser returns to the last-read tab,
  even after a restart.
- **Physical page buttons:** Page Up/Down, Left/Right, and Volume Up/Down turn
  pages and page through lists. See [BUTTON_SUPPORT.md](BUTTON_SUPPORT.md).
- **PDF modes:** Fit Height (one page per screen), Fit Width (page-height slices
  with a small overlap), and Zoom / Scroll (continuous pan, pinch zoom, momentum).
- **Text formats:** one shared paginated pipeline with bundled Latin and Hebrew
  fonts, mixed-direction text, optional hyphenation, and typography controls. TXT
  detects hard-wrapped prose.
- **Color:** black and white by default. **Page color** shows color PDF content and
  images, per document. PDF **Image dithering** (off by default) may help scans and
  photos.
- **Selection and annotations:** in EPUB, TXT, Markdown, and PDFs with a text
  layer, long-press a word, drag the handles, then choose **Copy**,
  **Dictionary**, **Add Note**, or **Underline**. Notes underline their text; tap
  an underline to view, edit, or delete the note. Annotations stay anchored when
  font size or hyphenation changes. Image-only PDFs have no lookup (no OCR).
  Details: [annotation_plan.md](annotation_plan.md).
- **Offline dictionaries:** English (WordNet 3.0, 86,538 entries, about 4.7 MB),
  modern Hebrew (Wiktionary extract via Kaikki.org), and Rabbinic Hebrew/Aramaic
  (the public-domain Jastrow dictionary from Sefaria, via jastrow.app); the two
  Hebrew sets add about 6.9 MB. No connection or download is needed, and each
  definition shows its source and license. Rebuild tools:
  `tool/build_dictionary.dart` and `tool/build_hebrew_dictionaries.dart`.
- **Study books (Tanach and Talmud):** recognized study EPUBs get translation and
  commentary controls and a fast on-device search index. The books themselves are
  produced by the separate `tanach/` and `talmud/` segments; the reader only uses
  the finished files. See [READER_PLAN.md](READER_PLAN.md).

## E-ink design rules

1. Pure black and white, strong borders, no gradients or shadows.
2. No route, ripple, splash, or snackbar animations.
3. Discrete pagination for the launcher, browser, app drawer, and text reader.
4. Continuous motion only in PDF Zoom / Scroll, where it is the point of the mode.
5. Bounded native rendering, prefetch, bitmap memory, and preview storage.
6. File work and parsing stay off the UI thread where possible.

## Project map

| Location | Purpose |
| --- | --- |
| `lib/main.dart` | Startup, theme, lifecycle, memory-pressure handling |
| `lib/controllers/`, `lib/screens/`, `lib/widgets/` | File browser and launcher UI |
| `lib/services/` | File operations, search, app discovery, Android bridges, startup health |
| `lib/reader/controllers/` | PDF/text sessions and their lifecycle |
| `lib/reader/services/` | Parsing, pagination, saving, PDF rendering, scheduling, caches |
| `lib/reader/screens/`, `lib/reader/widgets/` | Reader shell, menus, navigation, document views |
| `android/app/src/main/` | Manifest, launcher activity, native channels, startup marker |
| `test/`, `android/app/src/test/` | Flutter tests and native startup-policy tests |
| `tanach/`, `talmud/` | Separate EPUB-building segments (see their READMEs) |

For a full file list, run `rg --files lib test android/app/src`; the source tree is
more reliable than a hand-kept catalog.

## Build and verify

From the repository root, in PowerShell:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --target-platform android-arm64 --no-pub
```

Optional extra checks:

```powershell
# Native PDF stress test
$env:PDF_NATIVE_STRESS = '1'
flutter test --no-pub test/reader/pdf_native_render_stress_test.dart
Remove-Item Env:PDF_NATIVE_STRESS

# Native Android startup-policy tests
android\gradlew.bat -p android :app:testDebugUnitTest
```

**Signing:** personal builds use the debug signing setup in
`android/app/build.gradle.kts`. Create and protect a private release key before
sharing the app or moving the build to another machine. Do not remove `open_filex`
until the app has its own `FileProvider`; the file chooser relies on it.

## Documentation

| Document | What it covers |
| --- | --- |
| [READER_PLAN.md](READER_PLAN.md) | How the reader works: decisions, PDF and text pipelines, study books, tabs, remaining work |
| [LAYOUT_DESIGN.md](LAYOUT_DESIGN.md) | Screen layout dimensions and the reasons behind them |
| [BUTTON_SUPPORT.md](BUTTON_SUPPORT.md) | Physical page-button behavior and supported key pairs |
| [annotation_plan.md](annotation_plan.md) | Selection and annotation design, and the remaining device check |
| [ANDROID_HARDENING_PLAN.md](ANDROID_HARDENING_PLAN.md) | Startup, recovery, and Android reliability work |
| [DEVICE_TESTING.md](DEVICE_TESTING.md) | Everything tested on the device, measurements, and what is still unchecked |
| `docs/tanach/README.md`, `docs/talmud/README.md` | The two EPUB-building segments |
| [`archived/README.md`](archived/README.md) | The earlier versions of every document above, kept for history only |

## Next

1. Run a device pass on the HiBreak (or B751C) covering tabs, layouts, annotations,
   and the dictionaries. The checklist is in [DEVICE_TESTING.md](DEVICE_TESTING.md).
2. Test the largest Tanach books on the device: first-open time, memory, search.
3. Finish Talmud device checks and scale-up work (see `docs/talmud/README.md`).
