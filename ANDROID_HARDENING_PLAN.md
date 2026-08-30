# Android-Only Hardening Plan

This plan keeps the Flutter UI and improves the parts that matter for an Android-only e-ink launcher. It deliberately excludes a native rewrite, architecture churn, and cleanup that would not improve the installed app.

## Priorities

| Priority | Improvement | Expected payoff | Status |
| --- | --- | --- | --- |
| P0 | Establish device baselines and fix startup ordering | Reliable measurements and deterministic home-folder startup | [ ] Not started |
| P1 | Defer PDF runtime initialization | Faster launcher cold start | [ ] Not started |
| P1 | Launcher crash resilience (safe mode, corrupt-state recovery) | Prevents the device from becoming unusable if the launcher crashes repeatedly | [ ] Not started |
| P2 | Compare Impeller with the legacy renderer on the Bigme | Select the renderer with the least ghosting and best response | [ ] Not started |
| P2 | Reduce rebuild/repaint scope only where profiling proves useful | Less unnecessary rendering work | [ ] Conditional |
| P3 | Add Bigme refresh controls only if a supported API is available | Direct partial/full e-ink refresh control | [ ] Conditional |
| Done | Native `PackageManager` app discovery and launching | Removed the Kotlin plugin warning and gives direct launcher control | [x] Implemented |
| Done | Native Android battery broadcast bridge | Event-driven battery updates with no `battery_plus` dependency | [x] Implemented |
| Done | Preserve simple personal-sideload signing | Directly installable APKs that upgrade on the owned device | [x] Documented current workflow |

## 1. Measure the Current App First — Not Started

Use a release or profile build on the actual Bigme device. Debug APK size and timing are not representative.

### Record a baseline

1. Connect the device and confirm its ABI:

   ```sh
   adb shell getprop ro.product.cpu.abi
   ```

2. Run a profile build:

   ```sh
   flutter run --profile
   ```

3. Measure five cold starts:

   ```sh
   adb shell am force-stop com.example.eink_launcher
   adb shell am start -W -n com.example.eink_launcher/.MainActivity
   ```

4. Record idle memory after leaving the launcher untouched for one minute:

   ```sh
   adb shell dumpsys meminfo com.example.eink_launcher
   ```

5. Manually record these e-ink-specific observations:

   - Time from tapping Home until the first usable page.
   - Time from tapping a folder until the new folder appears.
   - Whether the temporary inverted row is visible.
   - Ghosting after ten folder changes and ten page changes.
   - Whether battery and clock updates repaint more of the screen than expected.

Keep the results in a dated section at the bottom of this file. Repeat the same measurements after each performance change.

### Fix startup ordering before comparing results

`FileBrowserScreen.initState()` currently starts `_controller.init()` and `_checkPermission()` independently. Permission handling can therefore load the storage root before the saved home folder has finished loading.

Implementation:

1. Add a private `_initialize()` method in `lib/screens/file_browser_screen.dart`.
2. Await `_controller.init()` first.
3. Check `mounted`.
4. Then await `_checkPermission()`.
5. Call `_initialize()` from `initState()` without separately calling the two operations.

Acceptance criteria:

- A configured home folder is always the first folder loaded after a cold start.
- Permission prompts still work on a fresh install.
- No folder is loaded twice during normal startup.

## 2. Defer PDF Runtime Initialization — Not Started

`lib/main.dart` currently awaits `pdfrxFlutterInitialize()` before `runApp()`, although most launcher sessions do not open a PDF. Move that work off the launcher startup path.

This step is the startup side of the reader lifecycle described in
[E-Ink Reader Plan §4.1](READER_PLAN.md#41-pdf). `PdfReaderSession.open()` and
`resume()` call `PdfDocumentService.open()`; the service's default document
opener is the precise place where lazy initialization belongs. This preserves
the session's suspend/resume architecture without making the launcher aware of
PDFium.

Implementation:

1. Add `lib/reader/services/pdf_runtime_service.dart` with a memoized `Future<void>`:

   ```dart
   class PdfRuntimeService {
     static Future<void>? _initialization;

     static Future<void> ensureInitialized() {
       return _initialization ??= pdfrxFlutterInitialize();
     }
   }
   ```

2. Remove the `pdfrxFlutterInitialize()` call and `pdfrx` import from `lib/main.dart`.
3. In `PdfDocumentService._openPdfDocument()`, await `PdfRuntimeService.ensureInitialized()` immediately before `PdfDocument.openFile()`.
4. Leave `PdfReaderSession.open()` and `resume()` calling `PdfDocumentService.open()`; both lifecycle paths will therefore use the same memoized initialization.
5. Preserve injected PDF openers in tests so unit tests do not require native PDFium initialization.

Acceptance criteria:

- The launcher renders before PDF initialization occurs.
- The first PDF opens normally.
- Later PDFs reuse the same initialization future.
- All reader tests continue to pass.

## 3. Keep `open_filex` — Decision Complete

Normal file opening uses `open_filex`, while the selection-mode **Open with** uses the custom Kotlin channel with `Intent.createChooser()`. Both paths work correctly, so `open_filex` is being kept as a dependency. The dual-path approach is acceptable for a personal-sideload app:

- Normal taps go through `open_filex`, which handles its own `FileProvider` and `ACTION_VIEW` intent.
- **Open with** goes through the Kotlin bridge, which borrows `open_filex`'s `FileProvider` authority for the chooser intent.

This was originally planned for consolidation but has been deliberately deferred — the current setup works reliably and removing `open_filex` would require setting up a standalone `FileProvider` configuration.

Important dependency: the custom Kotlin chooser currently borrows the provider authority installed by `open_filex`. Do not remove or replace `open_filex` in the future unless an app-owned `FileProvider` and `file_paths.xml` are added first and both opening paths are retested.

## 4. Native Android Battery Bridge — Implemented

The app does not depend on `battery_plus`. `MainActivity.kt` already listens to Android's sticky `ACTION_BATTERY_CHANGED` broadcast and sends percentage and charging state through `eink_launcher/battery_events`. `BatteryStatus` subscribes to that event stream and cancels its subscription when disposed.

This already provides the desired low-work behavior: there is no polling, and the launcher repaints only when Android reports a battery change. Moving the receiver into a separate `BatteryStatusHandler.kt` can be done later if `MainActivity.kt` becomes difficult to maintain, but that is code organization rather than a performance or reliability improvement.

Remaining verification:

- Add a widget test for valid, malformed, and unavailable battery events.
- Confirm charging transitions and receiver reattachment after an activity/engine restart on the Bigme.

## 5. Replace `installed_apps` with Android `PackageManager` — Implemented

The launcher now owns this integration. `LauncherApp`, `AppListService`, and
`InstalledAppsHandler` replace the plugin, preserve separate caches, and remove
its Kotlin Gradle warning. Automated channel tests cover mapping, sorting,
caching, query flags, and launch payloads; repeated launch behaviour still
needs the normal on-device smoke test.

Implementation:

1. Add a launcher-owned Dart model such as `LauncherApp` containing only `name`, `packageName`, and `isSystemApp`.
2. Add a Kotlin handler that queries activities matching:

   - `Intent.ACTION_MAIN`
   - `Intent.CATEGORY_LAUNCHER`

3. Return label, package name, and system-app status through a method channel.
4. Launch apps with `PackageManager.getLaunchIntentForPackage()`.
5. Keep the existing Dart-side sorting and separate caches for user-only and system-inclusive results.
6. Update `AppDrawerScreen` to use `LauncherApp` instead of the plugin's `AppInfo`.
7. Remove `installed_apps` from `pubspec.yaml` and rebuild the APK.

The app-query channel is kept in its own handler. Battery and file-intent code
can move out of `MainActivity.kt` when those hardening steps are undertaken:

```text
android/app/src/main/kotlin/com/example/eink_launcher/
├── MainActivity.kt
└── InstalledAppsHandler.kt
```

Acceptance criteria:

- User apps and optional system apps load and sort correctly.
- Only launchable activities appear.
- App launching and refresh work after repeated use.
- The Kotlin Gradle warning from `installed_apps` is gone.

## 6. Personal Sideloading and Optional Distribution — Current Workflow Complete

This app is currently intended for personal sideloading onto one owned device,
so both debug and release-mode APKs use Flutter's generated debug key. That is
installable and upgrade-safe as long as the same local key is retained. A
private release keystore is only needed if the app will be distributed or must
survive moving builds to another development machine.

Current workflow:

1. For personal sideloading, build the already signed debug APK with
   `flutter build apk --debug`.
2. Only before distribution, create a private release keystore, keep its
   passwords outside Git, and replace the debug signing configuration.
3. If release-mode performance testing is needed, verify the Bigme ABI and build only that target:

   ```sh
   flutter build apk --release --target-platform android-arm64
   ```

4. If distributing to multiple Android devices, use an app bundle or split APKs:

   ```sh
   flutter build appbundle --release
   flutter build apk --release --split-per-abi
   ```

5. Inspect release size rather than debug size:

   ```sh
   flutter build apk --release --analyze-size --target-platform android-arm64
   ```

6. Consider R8/resource shrinking only after the native plugin replacements are complete. Enable it in a branch, build, and exercise every native feature before keeping it.

Acceptance criteria for the current personal workflow:

- A debug APK installs and upgrades over the previous debug-key build.
- The package ID stays stable so Android retains app data across sideloaded updates.
- Distribution signing remains explicitly out of scope until distribution is planned.

## 7. Launcher Crash Resilience — Not Started

Because this app is registered as the device's Home launcher, startup recovery matters more than it would for an ordinary app. The goal is not to hide every error; it is to ensure a bad saved folder, corrupt state file, or repeated startup failure still leaves a usable route to the app drawer and recovery controls without requiring ADB.

Implementation:

1. Make startup an explicit state machine (loading, ready, and recovery) instead of letting unawaited initialization errors escape. Catch failures from shared preferences, permission checks, and the first folder load.
2. If the saved home folder is missing or unreadable, fall back to `/storage/emulated/0`, clear only the invalid home-folder preference, and show a concise warning. Do not clear unrelated settings.
3. `BookStoreService` already falls back to empty reader state when `library.json` cannot be decoded. Before that fallback, preserve the bad file as a bounded `.corrupt` backup and record a useful error; never repeatedly overwrite the only copy of the user's reading state.
4. Add a minimal recovery screen that does not initialize the reader. It must offer **Retry startup**, **Use storage root**, and **Open app drawer**. A reset-reading-state action may be included, but it must require confirmation and preserve or rename the old file rather than silently deleting it.
5. Add a small native startup-health marker. Mark a launch as healthy only after Flutter has rendered a usable file browser or recovery screen. If three launches fail before that point within a short window, start in recovery mode and ignore the saved home folder for that launch.
6. Install top-level Flutter error handlers for diagnostics and a bounded local crash record. Treat these as evidence for recovery, not as a substitute for the guarded startup flow.

Acceptance criteria:

- A missing or inaccessible saved home folder opens the storage root and explains what changed.
- Invalid `library.json` data cannot prevent the launcher or app drawer from opening, and a recoverable backup is retained.
- Three simulated early startup failures lead to the recovery screen on the next launch.
- Recovery mode can open the app drawer and return to normal startup without ADB or clearing all app data.
- Tests cover invalid preferences, unreadable folders, corrupt JSON, and the crash-loop threshold.

## 8. Compare Flutter Renderers on the E-Ink Device — Not Started

Do not disable Impeller based on assumptions. Compare both renderers using identical actions and the baseline checklist.

Implementation:

1. Test the default renderer:

   ```sh
   flutter run --profile
   ```

2. Test the legacy renderer:

   ```sh
   flutter run --profile --no-enable-impeller
   ```

3. Compare startup, tap feedback, folder changes, page changes, ghosting, and idle battery use.
4. Only if the legacy renderer is consistently better, disable Impeller in the Android manifest:

   ```xml
   <meta-data
       android:name="io.flutter.embedding.android.EnableImpeller"
       android:value="false" />
   ```

Acceptance criteria:

- The selected renderer wins repeatably on the actual device.
- The choice is documented with measurements, not preference.

## 9. Reduce Rebuilds Only If Profiling Shows a Problem — Conditional

The file browser currently places most of the scaffold under one `ListenableBuilder`. That is simple and probably acceptable for twelve visible rows, but file-stat updates can rebuild the whole screen.

Practical sequence:

1. Use Flutter DevTools in profile mode to record folder load, page change, selection, clock update, and battery update.
2. If rebuild cost is visible, separate the screen into top-bar, file-grid, and search-layer widgets.
3. Expose narrower `ValueListenable` state from `FileBrowserController` for navigation, selection, and status instead of making every section react to every notification.
4. Trial `RepaintBoundary` around the top status bar and paginated grid. Keep it only if traces or device behavior improve; extra layers also consume memory.
5. Retest actual e-ink ghosting. Reduced Flutter paint work does not guarantee that the device performs a smaller physical refresh.

Do not replace the fixed twelve/fifteen-row layout with a complex lazy list. The current number of children is small and bounded.

## 10. Add Vendor Refresh Control Only When Supported — Conditional

This is useful only if Bigme provides a documented SDK, system service, or intent for refresh modes.

Implementation if an API is available:

1. Wrap it in a small Kotlin handler.
2. Expose explicit operations such as `partialRefresh()` and `fullRefresh()` through the Android bridge.
3. Trigger partial refresh after a completed tap/page/folder update, not continuously during layout.
4. Trigger full refresh sparingly, such as after a configurable number of page changes or through a manual menu command.
5. Make the bridge a no-op on unsupported devices.

Do not use undocumented reflection or hard-coded service calls that could break after a firmware update.

## 11. Expand Regression Coverage Around the Android-Only Features — Ongoing

Add tests as each refactor lands:

- Startup sequencing: saved home folder loads before the first directory request.
- File intent payloads: correct MIME type and chooser flag.
- App query mapping, filtering, sorting, caching, and launch errors.
- Selection actions: **Open with** and Rename appear only when applicable; Paste never appears.
- Equal-band layout: 15 portrait bands and 12 landscape bands on both screens.
- Live app search filters on each edit and resets to page one.
- Battery event parsing and charging-icon selection.
- Startup recovery: invalid home folder, corrupt reader state, and crash-loop safe mode.
- Opening feedback inverts a row before invoking the opener.

Keep the standard completion checks:

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Also perform a short on-device smoke test for battery events, MIME resolution, Android chooser behavior, app discovery, app launching, rotation, and e-ink ghosting.

## Things Not Worth Doing Now

- Rewriting the application in Kotlin/Compose or Android Views without measured Flutter failures.
- Removing the iOS, web, desktop, or Linux directories for performance; they are not packaged into the Android APK.
- Introducing a state-management framework solely to reduce a few small rebuilds.
- Polling battery state; the existing Android broadcast stream is already the correct low-work design.
- Adding animations to make transitions appear smoother; this conflicts with the e-ink design.
- Disabling Impeller or adding vendor refresh calls without testing on the real device.

## Recommended Execution Order

1. Capture the baseline and fix startup sequencing.
2. Defer PDF initialization.
3. Add launcher startup recovery and crash-loop safe mode.
4. Keep the current `open_filex` and native battery implementations; only perform their remaining tests.
5. Keep using the documented personal-sideload signing workflow.
6. Compare Impeller on/off.
7. Optimize rebuild boundaries only if profiling identifies them.
8. Add Bigme-specific refresh control only if a supported API exists.

## Measurement Log

Add dated before/after measurements here as work is completed.

| Date | Build/commit | Renderer | Cold start median | Idle memory | Folder open | Ghosting notes |
| --- | --- | --- | --- | --- | --- | --- |
| _Pending_ |  |  |  |  |  |  |

## Official References

- [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [Flutter Impeller renderer](https://docs.flutter.dev/perf/impeller)
- [Flutter Android deployment and ABI splitting](https://docs.flutter.dev/deployment/android)
- [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices)
- [Android startup measurement and optimization](https://developer.android.com/topic/performance/appstartup/analysis-optimization)
- [Android APK size reduction](https://developer.android.com/topic/performance/reduce-apk-size)
