# HiBreak validation - 2026-09-02

## Scope and baseline

ADB validation of the installed **1.0.2 (build 3)** arm64 release, with source
baseline `81787c9`. The existing release APK SHA-256 remains
`8231F46FF8A086EF84C50AA416EADE9589A64E0599F7EB45CD7F2EA6D0317CAB`.
The device reports HiBreak, Android 14, 1264 x 1680 pixels, density 300, and a
256 MiB normal heap class (queried from Android `ActivityManager`). Its default
Flutter renderer is Impeller
OpenGLES. The Bigme refresh mode was left unchanged; its name was not established.

Tests used generated documents: a 32-page vector PDF (29,738 bytes), a 32-page
image-only PDF (23,304,439 bytes), and mixed English/Hebrew TXT, Markdown, and EPUB.
These are reproducible samples, not an exhaustive set of real-world books.

No production application code or installed production APK was changed.
Fault injection used a separate `com.example.eink_launcher.validation` package,
without the Home role. Its optimized test build explicitly allowed debugging so
ADB could manipulate only that package's generated private state. A temporary
instrumentation package supplied multitouch gestures and screenshot samples.

## Verification results

| Check | Result |
| --- | --- |
| Flutter static analysis | No issues. SDK located at `C:/Users/levi/flutter`. |
| Flutter suite | 240 passed with `PDF_NATIVE_STRESS=1`; one older external-PDF test skipped. |
| Android startup-policy tests | Gradle task successful; cached results contain 5 tests, zero failures/errors. |
| Source baseline | Existing changes were committed during this run as `81787c9`; worktree was clean before adding this report. |
| Fit Height rapid navigation | 20 forward plus 10 backward taps, starting at page 1, ended at page 11. Menu remained responsive. |
| Fit Width rapid navigation | 12 forward plus 6 backward slice turns moved page 11 to page 14 without hanging. |
| PDF movement | Vector and scanned PDF samples retained visible content during both forward/reverse scroll passes. |
| Legacy renderer PDF movement | Scanned PDF also completed both scroll passes with content in all eight sampled frames. |
| Physical-screen confirmation | After the ADB pass, the user reported no ghosting or white flashes on 2026-09-02. PDF-002 and PDF-003 are closed for the observed test conditions. |
| Pinch release | Captured release and later frames contained document pixels. Six consecutive in/out pinch pairs also completed on the scanned PDF. |
| Finger-down stopping | Both PDFs stopped while a finger was held. Central image differences between held samples were negligible, with no visible displacement. |
| Rotation | Scanned PDF changed to landscape and back while retaining page 5 / 12%. |
| Persistence | Page 5, Zoom / Scroll mode, and the generated Page 5 bookmark survived closing/reopening and a full production-process restart. |
| Memory pressure | Android trim signal produced the saved-position recovery screen; Continue reading resumed at page 5. |
| TXT / Markdown / EPUB | All opened; mixed English/Hebrew text rendered. EPUB contents listed the expected entry. |
| Text search | `Needle20` returned exactly 5 matches; selecting a result navigated to the page containing the match. |
| Android chooser | Open with displayed the system resolver for the generated TXT file; it was dismissed without changing a default app. |
| App drawer | App discovery, refresh, filtering, and launching the validation app succeeded. Recovery also retained drawer access. |
| Battery channel | Simulated disconnect removed charging status; a process restart reattached to that state; resetting the simulation restored charging. |
| Permission denial | The isolated app remained usable with Grant storage access and the menu available. Granting access allowed normal browsing. |
| Invalid saved home | The isolated app warned, fell back to Internal Storage, and removed the invalid preference. |
| Corrupt reader state | The exact 29-byte corrupt fixture was preserved as `library.json.corrupt`; a separate valid 449-byte library was created after continuing. |
| Startup recovery | A recent pending marker with two failures triggered recovery on the next launch. Retry startup and Use storage root worked; healthy state became `pending=false`, `failures=0`. The valid saved home survived Use storage root. |

## Startup and memory measurements

Android `am start -W` reported these **cold-launch activity display times**:

| Renderer | Five measurements (ms) | Median (ms) | Post-start PSS (KiB) |
| --- | --- | --- | --- |
| Impeller OpenGLES | 985, 1236, 1216, 1236, 1209 | 1216 | 99,531 |
| Legacy | 1097, 1109, 1108, 1176, 1119 | 1109 | 90,447 |

Settings was brought to the foreground before force-stopping the launcher so
Android would not immediately relaunch its Home activity. Earlier measurements
that reported `UNKNOWN` and zero time were discarded. These measurements are
activity display times, not instrumented first-interactive-frame timings. Five
sequential runs per renderer do not establish a general renderer winner.

The following are sampled production-process PSS values under the default
renderer. Native and graphics columns come from the `dumpsys meminfo` app summary.
They are KiB, not Dart heap sizes. Samples followed sequential use, so later PDF
samples can include retained resources from earlier sessions.

| Stage | Native heap | Graphics | Total PSS |
| --- | ---: | ---: | ---: |
| Fresh process, 60 seconds idle | 13,424 | 37,583 | 106,937 |
| First vector open | 13,804 | 58,748 | 145,534 |
| Vector scrolling | 16,164 | 131,352 | 226,797 |
| Return to file browser | 16,176 | 132,209 | 227,670 |
| Scanned PDF open after vector | 38,808 | 152,461 | 270,685 |
| Scanned PDF scrolling | 39,868 | 218,907 | 339,465 |
| Background after PDF use | 24,324 | 200,843 | 306,310 |
| After memory-pressure recovery | 24,288 | 48,522 | 151,928 |

Memory pressure released a substantial amount of graphics memory. These samples
do not establish a leak, and the 256 MiB Android heap limit is not a cap on total
native/graphics PSS. They do show why tabs need explicit session suspension and
must not assume retained-image cache budgets bound the entire process.

The separate legacy-renderer scanned-PDF pass recorded 214,545 KiB total PSS,
40,464 KiB native heap, and 115,869 KiB graphics. It began in a fresh process with
one PDF, unlike the sequential two-PDF Impeller run, so these values are not a
controlled comparison of renderer memory efficiency.

The first full vector and scanned fit pages were visible at the second captured
open sample (sampling began around 2.04 s and 1.70 s after the respective tap).
Screenshot acquisition and encoding materially slow sampling. These are coarse
observations, not precise first-preview or sharp-text latency measurements.

## Physical-screen confirmation

On 2026-09-02, after this ADB pass, the user reported: "no ghosting or white
flashes." This supplies the direct physical-screen observation that screenshots
could not provide and closes the pending PDF-002/PDF-003 confirmation for the
observed version 1.0.2 test conditions. It does not establish a preferred renderer
or a guarantee for untested documents and scroll speeds.

## Test limitations and findings for tabs

- Screenshots inspect app pixels, not physical e-ink ghosting or panel refresh.
  No external-camera evidence was collected. Physical-screen confirmation comes
  from the user's subsequent observation above, not from the screenshots alone.
- Scroll captures are sampled and slow the test. No sampled frame was wholly
  blank, but a shorter white interval between samples remains possible. Later
  passes also benefit from idle preview warming; this was not a controlled cache
  benchmark.
- The original unoptimized validation build took roughly 7-11 seconds to start
  and produced one input-timeout ANR during its first startup. This was confined
  to the temporary debug package. An optimized validation build was used for the
  final invalid-home, corrupt-library, and seeded recovery checks. No production
  ANR appeared in the captured test-period events.
- The device clock was approximately nine seconds behind the PC. A future-dated
  initial recovery fixture was correctly ignored; the successful fixture used a
  recent past timestamp.
- Closing a reader route currently cancels PDF work but retains its session and
  caches. App backgrounding, memory pressure, and the registry's four-active-
  session cap provide suspension paths. **Hidden-tab suspension must be an
  explicit part of tabs implementation.** Earlier wording that all hidden
  sessions already suspend was too broad.
- Renderer preference, precise preview/sharpen latency, and unplugged idle battery
  drain remain unmeasured. The ghosting/white-flash confirmation is complete.
  No remaining validation item prevents drafting the tabs plan; no renderer or
  cache-budget change is justified by these results alone.

Raw timings, memory dumps, UI trees, screenshots, fixture generators, and the
temporary test sources are kept locally in `.buildlog/device-check/` (git-ignored).

## Cleanup and handoff

Both temporary test packages were uninstalled, including their generated private
state and device-side helper screenshots. Their source and captured evidence
remain available locally. The original launcher was restarted with its default
Impeller backend and returned to the existing Books home folder. Battery
simulation was reset and the device again reported USB charging.

The five disposable reading fixtures remain in
`Download/EinkValidation-20260902` for optional regression testing. The physical
check is complete, so they can now be removed; copies and their generator are in
`.buildlog/device-check/`.
Production application code, installed APK, and pre-existing books were not
modified. The only tracked workspace edits from this run are this report and
the related status-document updates.
