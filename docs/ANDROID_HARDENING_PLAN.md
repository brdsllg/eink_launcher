# Android reliability

How the app starts, recovers, and talks to Android, plus the optional work that
remains. The high-value changes are done; anything further should be driven by
measurements on the device (results so far are in [DEVICE_TESTING.md](DEVICE_TESTING.md)).

## Status

| Priority | Work | Status |
| --- | --- | --- |
| P0 | Predictable startup and usable recovery | Done; restart and fault-injection checks passed |
| P0 | Startup, memory, and e-ink baselines | Done; no ghosting or white flashes reported |
| P1 | Start PDFium only when a PDF opens | Done; precise timings not measured |
| P1 | Android chooser, app launching, battery reconnection | Done; checks passed |
| P2 | Compare Impeller with the legacy renderer | Compared; no change justified |
| P2 | Reduce rebuild and repaint work | Only if profiling shows a cost |
| P3 | Bigme refresh controls | Only if Bigme documents an API |

## What is in place

### Startup and recovery

Startup is one guarded sequence: native health check, saved preferences, storage
permission, initial folder listing. Preferences and listing have timeouts (the
permission prompt does not). Duplicate setup is suppressed and late work is ignored
after shutdown.

- An invalid saved home folder falls back to `/storage/emulated/0`, removes only
  that setting, and shows a warning. Refusing permission does not erase the setting.
- Before Flutter starts, Android notes an unfinished launch in private storage.
  Three unfinished cold launches within ten minutes send the next launch to
  recovery. Recreating the screen or engine within one process does not count. A
  usable browser or recovery screen clears the failure count.
- Recovery offers **Retry startup**, **Use storage root**, and **Open app drawer**.
  The loading screen also keeps **Open app drawer**.
- Errors are logged as usual and the last two (up to 8,192 characters each) are kept
  locally. Nothing is uploaded.
- Reading-state recovery is separate: a malformed `library.json` is backed up (up to
  three copies) before replacement; if that is unsafe, saving is disabled for that
  launch and the source is left untouched.

### Lazy PDF start-up

Launcher startup never starts PDFium. The PDF opener starts it once, immediately
before the first PDF opens, and concurrent opens share that setup. Missing files and
test openers skip it. If setup fails, the reader shows an error, and a retry works
after restarting the app.

### Android connections

- App discovery and launching use the app's own Kotlin code and list only launchable
  apps, with separate user-app and all-app caches.
- Battery status comes from Android's broadcast; nothing polls, and no `battery_plus`
  package is needed.
- File taps use `open_filex`; **Open with** uses the app's own chooser. Keep
  `open_filex` until the app has its own `FileProvider`, since both use its
  authority.
- PDF cache size reads Android's heap class once, on first PDF use.
- A Windows file-copy path bug was fixed without changing Android behavior.

### Personal sideloading

The local debug signing key suits builds installed on your own device and allows
upgrades while the signing key and package ID stay the same. A private release key
is needed before sharing or before building on a machine that cannot keep the same
key. Do not turn on code shrinking or change signing right before a device test;
try either change on its own first and exercise every native connection.

Build commands: `flutter build apk --debug`, `... --release --target-platform
android-arm64`, `... --release --split-per-abi`, `flutter build appbundle --release`.

## Optional next steps (only if measurements justify them)

1. **Fresh baseline,** using the same build and refresh mode each time. Measure five
   cold starts, folder-open response, memory after one minute idle, first PDF open,
   and ghosting after repeated page changes:
   ```powershell
   adb shell getprop ro.product.cpu.abi
   adb shell am force-stop com.example.eink_launcher
   adb shell am start -W -n com.example.eink_launcher/.MainActivity
   adb shell dumpsys meminfo com.example.eink_launcher
   ```
2. **Renderer comparison:** run `flutter run --profile`, then again with
   `--no-enable-impeller`, and change the manifest only if one clearly wins on the
   device.
3. **Rebuild scope:** if profiling shows real work during folder loads, page changes,
   clock ticks, or battery updates, split the browser into smaller parts and test
   `RepaintBoundary` on stable areas; keep it only if traces improve.
4. **Vendor refresh controls:** add a small Kotlin bridge only if Bigme documents an
   SDK, service, or intent. It should do nothing on unsupported devices and request
   full refreshes sparingly. No undocumented firmware tricks.

## Avoid without evidence

- Rewriting the app in Kotlin/Compose just because it targets Android.
- Removing unbuilt desktop/web folders for installed-app speed.
- Adding a state-management framework for the small current listener graph.
- Polling battery state, or adding animations to hide e-ink refresh.
- Disabling Impeller, changing cache sizes, or adding vendor calls without a
  repeatable device comparison.
