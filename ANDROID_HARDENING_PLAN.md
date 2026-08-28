# Android-Only Hardening Plan

This plan keeps the Flutter UI and improves the parts that matter for an Android-only e-ink launcher. It deliberately excludes a native rewrite, architecture churn, and cleanup that would not improve the installed app.

## Priorities

| Priority | Improvement | Expected payoff |
| --- | --- | --- |
| P0 | Establish device baselines and fix startup ordering | Reliable measurements and deterministic home-folder startup |
| P1 | Defer PDF runtime initialization | Faster launcher cold start |
| P1 | Replace `open_filex` with the existing native Android bridge | Correct MIME handling, fewer plugin dependencies, one file-opening path |
| P1 | Replace `installed_apps` with `PackageManager` integration | Removes the current Kotlin plugin warning and gives direct launcher control |
| P1 | Configure a real Android release build | Smaller, reproducible, upgrade-safe APKs |
| P2 | Compare Impeller with the legacy renderer on the Bigme | Select the renderer with the least ghosting and best response |
| P2 | Reduce rebuild/repaint scope only where profiling proves useful | Less unnecessary rendering work |
| P3 | Add Bigme refresh controls only if a supported API is available | Direct partial/full e-ink refresh control |

## 1. Measure the Current App First

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

## 2. Defer PDF Runtime Initialization

`lib/main.dart` currently awaits `pdfrxFlutterInitialize()` before `runApp()`, although most launcher sessions do not open a PDF. Move that work off the launcher startup path.

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
3. In the default PDF-opening path, await `PdfRuntimeService.ensureInitialized()` immediately before `PdfDocument.openFile()`.
4. Preserve injected PDF openers in tests so unit tests do not require native PDFium initialization.

Acceptance criteria:

- The launcher renders before PDF initialization occurs.
- The first PDF opens normally.
- Later PDFs reuse the same initialization future.
- All reader tests continue to pass.

## 3. Consolidate Android File Opening

Normal opening still uses `open_filex`, while selection-mode **Open with** uses the custom Kotlin channel. Maintain one native implementation instead.

Implementation:

1. Rename the channel operation to `openFile` and pass:

   - `path`
   - `mimeType`
   - `forceChooser`

2. When `forceChooser` is false, launch the `ACTION_VIEW` intent directly. When true, wrap it with `Intent.createChooser()`.
3. Move the Dart call behind one `AndroidFileService` used by both normal taps and **Open with**.
4. Declare an app-owned `FileProvider` in `AndroidManifest.xml` and add `android/app/src/main/res/xml/file_paths.xml`.
5. Change the provider authority to `${applicationId}.fileprovider`. Do not keep relying on the provider contributed by `open_filex`, because it disappears when that dependency is removed.
6. Remove `open_filex` from `pubspec.yaml` only after both opening paths work through the native bridge.

Acceptance criteria:

- Normal taps respect an existing Android default app.
- **Open with** always displays the chooser.
- PDF, EPUB, TXT, Markdown, DOCX, images, audio, video, and unknown binary files receive the expected MIME type.
- A missing file and a file with no compatible app show useful launcher feedback.
- `open_filex` is absent from `pubspec.yaml` and the generated plugin registrant.

## 4. Replace `installed_apps` with Android `PackageManager`

The current Android build warns that `installed_apps` applies an older Kotlin Gradle configuration. This plugin is small enough to replace directly.

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

Structure the Android code as small handlers rather than continuing to grow `MainActivity.kt`:

```text
android/app/src/main/kotlin/com/example/eink_launcher/
├── MainActivity.kt
├── BatteryStreamHandler.kt
├── FileIntentHandler.kt
└── InstalledAppsHandler.kt
```

Acceptance criteria:

- User apps and optional system apps load and sort correctly.
- Only launchable activities appear.
- App launching and refresh work after repeated use.
- The Kotlin Gradle warning from `installed_apps` is gone.

## 5. Produce a Proper Android Release

The current release build uses the debug signing key. That is acceptable for local experiments but not for durable device updates or distribution.

Implementation:

1. Create a private release keystore and keep its passwords outside Git.
2. Add a non-committed `key.properties` file and configure `signingConfigs.release` in `android/app/build.gradle.kts`.
3. Verify the Bigme ABI. If it is `arm64-v8a` and this APK is only for that device, build only that target:

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

Acceptance criteria:

- A release APK installs and upgrades over the previous release signed with the same key.
- The release key and passwords are not committed.
- The chosen artifact contains only the architectures actually needed.

## 6. Compare Flutter Renderers on the E-Ink Device

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

## 7. Reduce Rebuilds Only If Profiling Shows a Problem

The file browser currently places most of the scaffold under one `ListenableBuilder`. That is simple and probably acceptable for twelve visible rows, but file-stat updates can rebuild the whole screen.

Practical sequence:

1. Use Flutter DevTools in profile mode to record folder load, page change, selection, clock update, and battery update.
2. If rebuild cost is visible, separate the screen into top-bar, file-grid, and search-layer widgets.
3. Expose narrower `ValueListenable` state from `FileBrowserController` for navigation, selection, and status instead of making every section react to every notification.
4. Trial `RepaintBoundary` around the top status bar and paginated grid. Keep it only if traces or device behavior improve; extra layers also consume memory.
5. Retest actual e-ink ghosting. Reduced Flutter paint work does not guarantee that the device performs a smaller physical refresh.

Do not replace the fixed twelve/fifteen-row layout with a complex lazy list. The current number of children is small and bounded.

## 8. Add Vendor Refresh Control Only When Supported

This is useful only if Bigme provides a documented SDK, system service, or intent for refresh modes.

Implementation if an API is available:

1. Wrap it in a small Kotlin handler.
2. Expose explicit operations such as `partialRefresh()` and `fullRefresh()` through the Android bridge.
3. Trigger partial refresh after a completed tap/page/folder update, not continuously during layout.
4. Trigger full refresh sparingly, such as after a configurable number of page changes or through a manual menu command.
5. Make the bridge a no-op on unsupported devices.

Do not use undocumented reflection or hard-coded service calls that could break after a firmware update.

## 9. Expand Regression Coverage Around the Android-Only Features

Add tests as each refactor lands:

- Startup sequencing: saved home folder loads before the first directory request.
- File intent payloads: correct MIME type and chooser flag.
- App query mapping, filtering, sorting, caching, and launch errors.
- Selection actions: **Open with** and Rename appear only when applicable; Paste never appears.
- Equal-band layout: 15 portrait bands and 12 landscape bands on both screens.
- Live app search filters on each edit and resets to page one.
- Battery event parsing and charging-icon selection.
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
3. Consolidate native file opening and remove `open_filex`.
4. Replace `installed_apps` and split native handlers out of `MainActivity`.
5. Configure signed, architecture-appropriate release builds.
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
