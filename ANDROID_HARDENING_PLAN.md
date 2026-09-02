# Android hardening status and next steps

This document tracks Android-specific reliability and performance work for the
e-ink launcher. The high-value code changes are implemented. Remaining changes
should be driven by measurements on the Bigme device.

## Priorities

| Priority | Work | Status |
| --- | --- | --- |
| P0 | Deterministic startup and usable recovery | Implemented; real restart checks pending |
| P0 | Record cold-start, memory, and e-ink baselines | Pending |
| P1 | Initialize PDFium only when a PDF opens | Implemented; device timing pending |
| P1 | Verify Android chooser, app launching, and battery reconnection | Pending device smoke test |
| P2 | Compare Impeller and the legacy renderer | Pending |
| P2 | Reduce rebuild/repaint scope | Only if profiling shows a cost |
| P3 | Add Bigme refresh controls | Only if a documented API exists |

## Implemented hardening

### Startup ordering and recovery

Startup follows one guarded sequence: native startup-health check, saved
preferences, storage permission, then the initial folder listing. Preference and
listing work have timeouts; the interactive permission prompt does not. Duplicate
initialization is suppressed and late work is ignored after disposal.

An invalid or unreadable saved home falls back to `/storage/emulated/0`, removes
only the invalid home setting, and shows a warning. Permission denial does not
erase the setting. Loading and recovery screens retain **Open app drawer**.

Before Flutter starts, Android records an unfinished launch in app-private
preferences. Three unfinished cold launches within ten minutes send the next
launch to recovery. Activity or engine recreation in the same process is not
counted as a new cold launch. A usable browser or recovery frame clears the
failure state. Recovery offers **Retry startup**, **Use storage root**, and
**Open app drawer**.

Flutter and platform errors keep normal logging and also store at most two local
diagnostic records of 8,192 characters. Nothing is uploaded.

Reader-state recovery is separate from launcher startup. Malformed `library.json`
is preserved in up to three full backups. If safe preservation is impossible,
the source remains untouched and saving is disabled for that launch.

### Lazy PDF runtime

Launcher startup does not initialize PDFium. The production PDF opener calls a
memoized runtime service immediately before `PdfDocument.openFile()`. Concurrent
PDF opens share initialization; missing files and injected test openers bypass it.
A setup failure reaches the reader error boundary and can be retried after an app
restart.

Reader lifecycle and PDF performance details are in
[READER_PLAN.md](READER_PLAN.md) and
[PDF_RESPONSIVENESS.md](PDF_RESPONSIVENESS.md).

### Native Android integrations

- App discovery and launch use an app-owned Kotlin `PackageManager` handler. Only
  launchable activities are listed, with separate user-app and all-app caches.
- Battery state uses the sticky `ACTION_BATTERY_CHANGED` broadcast through an
  event channel. There is no polling and no `battery_plus` dependency.
- Normal file taps use `open_filex`; explicit **Open with** uses an Android chooser.
  Keep `open_filex` until an app-owned `FileProvider` replaces the authority used
  by both paths.
- PDF cache sizing queries Android's normal heap class lazily on first PDF use.
- Windows file-copy path handling was fixed without changing Android path rules.

### Personal sideloading

The current local key is suitable for builds installed on the owned device and
allows upgrades while the same signing identity and package ID are retained.
A private release keystore is required before distribution or before builds move
to a machine that cannot retain that identity.

Useful build commands:

```powershell
flutter build apk --debug
flutter build apk --release --target-platform android-arm64
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

Do not enable shrinking or change signing immediately before a device test. Trial
either change separately and exercise every native channel before keeping it.

## Device work in recommended order

### 1. Record a baseline

Use the same release/profile build and device refresh mode for every comparison.

```powershell
adb shell getprop ro.product.cpu.abi
flutter run --profile
adb shell am force-stop com.example.eink_launcher
adb shell am start -W -n com.example.eink_launcher/.MainActivity
adb shell dumpsys meminfo com.example.eink_launcher
```

Measure five cold starts. Record first usable frame, folder-open response, idle
memory after one minute, first PDF-open time, and ghosting after repeated folder
and reader page changes. For PDF memory work, record normal heap class plus
native, graphics, and total PSS before and after sustained page turns and zooming.

### 2. Verify recovery and Android channels

- Exercise fresh-install permission handling and an inaccessible saved home.
- Simulate repeated process restarts and confirm the recovery threshold and return
  to normal startup without clearing all app data.
- Confirm corrupt reader-state handling retains a backup and leaves the app drawer
  usable.
- Check battery charging transitions after activity/engine recreation.
- Open the Android chooser, query/refresh apps, and launch several apps repeatedly.

### 3. Compare Flutter renderers

Run the same actions with the default renderer and the legacy renderer:

```powershell
flutter run --profile
flutter run --profile --no-enable-impeller
```

Compare startup, taps, folder/page changes, PDF motion, ghosting, and idle battery
use. Change the manifest only if one renderer wins repeatably on the actual device.

### 4. Profile before changing rebuild structure

If DevTools shows meaningful work during folder loads, page changes, clock ticks,
or battery updates, split the file-browser scaffold into narrower listeners and
trial `RepaintBoundary` around stable areas. Keep a change only if traces and the
panel response improve; the fixed 12/15-band list is already small.

### 5. Consider vendor refresh controls last

Add a small Kotlin bridge only if Bigme supplies a documented SDK, service, or
intent. It should be a no-op on unsupported devices and request full refreshes
sparingly. Do not rely on undocumented reflection or firmware-specific service
names.

## Verification baseline

The last complete Android hardening run passed **201 Flutter tests** and **5 native
JVM startup-policy tests**, with clean static analysis and successful debug/release
APK builds. Later reader work supersedes the Flutter count: the current full suite
passes **240 tests** with the generated native PDFium check enabled. The raw HiBreak
results are in [BIGME_TEST_LOG.md](BIGME_TEST_LOG.md).

Standard checks:

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
android\gradlew.bat -p android :app:testDebugUnitTest
```

## Avoid without evidence

- Rewriting the app in Kotlin/Compose solely because it targets Android.
- Removing unbuilt desktop/web directories for installed APK performance.
- Adding a state-management framework for the current small listener graph.
- Polling battery state or adding animations to mask e-ink refresh behavior.
- Disabling Impeller, changing cache fractions, or adding vendor calls without a
  repeatable device comparison.

## Measurement log

| Date | Build | Renderer/refresh mode | Cold start median | Idle memory | Folder open | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| _Pending_ |  |  |  |  |  |  |
