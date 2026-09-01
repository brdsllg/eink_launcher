# PDF responsiveness follow-up

Implemented after the 2026-08-31 HiBreak manual report. The user authorized code
changes and software verification while unavailable for device testing. The
original observations remain in [BIGME_TEST_LOG.md](BIGME_TEST_LOG.md).

## Changes

- **Control rendering before allocating native buffers.** A shared scheduler
  admits one render/crop operation at a time. Visible previews and visible detail
  precede speculative work. Queued requests have a fixed upper bound; obsolete
  requests can be withdrawn and existing requests promoted as the viewport moves.
  Cancellation does not free an active slot until that operation actually ends.
- **Bound crop sampling too.** Crop previews now cap both dimensions at 512 pixels
  and reject invalid geometry before rendering. A pathological tall page cannot
  turn a nominally small crop sample into an enormous native buffer.
- **Share unfinished work.** Matching crop and bitmap requests share their
  operation. Each image consumer receives its own owned image handle. Lifecycle
  and settings changes invalidate obsolete work without reporting it as a broken
  document or allowing it to overwrite the new reading state.
- **Preserve navigation input.** Rapid PDF turns are processed in order through
  asynchronous Fit Width crop calculations. Explicit jumps, settings changes,
  suspension, and disposal invalidate obsolete pending navigation.
- **Give useful pixels priority.** Zoom / Scroll has small correct-page previews
  beneath the detailed tiles, directional look-ahead, and cancellable demand.
  Detail refinement waits briefly after motion stops. Ordinary fit-mode page
  turns do not have a mandatory one-second delay.
  Preview images have a 512-pixel longest edge and a cache reserve carved out of
  the existing total budget (one eighth, capped at 4 MiB), rather than increasing
  that budget. The initial detail idle interval is 200 ms.
- **Replace the zoom deadline with readiness.** Keep a bounded set of already
  displayed detail while preparing a new density. Present the visible replacement
  batch when ready; offscreen tiles do not gate it. Do not discard useful old
  pixels merely because 500 ms elapsed, and do not render a second old tile grid.

## Verification

The complete suite passed **234 tests**, with `PDF_NATIVE_STRESS=1` enabled.
One older optional smoke test requiring an externally supplied PDF was skipped;
the generated-document native PDFium test ran and passed. The full run completed
on 2026-09-01; static analysis in the same verification run reported **no issues**.

Coverage added for this change includes 18 navigation/session cases, seven visual
handoff/retry cases, five scheduler cases, two crop-buffer safety cases, and the
generated native-PDFium check. In the delayed 30-turn stress case, only the initial
and final pages reach rendering, with at most one admitted native render.
The visual cases include a boundary-page tap during the post-pinch idle interval:
an unchanged navigation destination must still allow the page to sharpen.

The regression suite uses delayed, visibly distinct fake pages to check input
ordering, shared requests, lifecycle cancellation, and image continuity. A
separate optional host-native test generates an eight-page PDF, runs real PDFium
crop/render calls, cancels obsolete queued demand, and checks for actual ink in
the requested images. This does not require a private book or an attached device.

Run the normal suite with `flutter test --no-pub`. On a supported host with its
PDFium native asset available, run the optional native check in PowerShell:

```powershell
$env:PDF_NATIVE_STRESS = '1'
flutter test --no-pub test/reader/pdf_native_render_stress_test.dart
Remove-Item Env:PDF_NATIVE_STRESS
```

## Built APK

The final Android release build completed on **2026-09-01**, after the last
boundary-tap regression fix. Version **1.0.1 (build 2)** is available locally as
[eink-launcher-1.0.1-pdf-fixes.apk](build/app/outputs/flutter-apk/eink-launcher-1.0.1-pdf-fixes.apk)
(31,803,551 bytes, approximately 30.3 MiB). This is a generated build artifact,
not a tracked repository file. It was built with
`flutter build apk --release --target-platform android-arm64 --no-pub`.

The APK package/version metadata and Android v2 signature were verified. It uses
the project's existing personal-sideload signing configuration. No device
installation or device testing was performed for this follow-up.

SHA-256: `4771740A531208FDEE2FD584F1720A415125866859D3A132613CA82EA7B0466B`

## Limits

- PDF-001, PDF-002, and PDF-003 remain **pending HiBreak verification**. Their
  original cause was not measured on the device; host tests do not establish an
  e-ink refresh result.
- An already running synchronous PDFium raster call cannot be interrupted by
  this scheduler. New obsolete jobs are dropped before dispatch; an active job
  finishes and its unused result is released.
- A never-rendered page still takes time to produce its first preview. Preview
  coverage reduces empty waits but is not a guarantee for arbitrary long jumps.
- Cache budgets are not total process limits. Widget-owned images, a bounded
  fallback, one admitted native operation, PDFium document data, and graphics
  allocations also consume memory. The existing memory-pressure recovery remains.
- The renderer, dependency versions, Android refresh behavior, and adaptive cache
  fraction were not changed based on speculation. Preview/refinement constants
  are conservative starting values, not HiBreak-tuned performance claims.

## Short device check when available

Use a small text/vector PDF and a scanned PDF. Record the installed APK, renderer,
and Bigme refresh mode so comparisons use the same setup.

1. In Fit Height and Fit Width, tap forward quickly, reverse direction, and cross
   page/slice boundaries. Check the final destination and centre menu/Back while
   rendering is pending.
2. Pinch in/out repeatedly, including another pinch before sharpening completes.
   Content should remain useful through refinement rather than disappearing at a
   fixed timeout.
3. Scroll quickly, reverse direction, tap forward in Zoom / Scroll, and revisit
   pages. Compare time to first useful content separately from time to sharp text.
4. Switch modes/orientation, leave and reopen the reader, and confirm position and
   bookmarks. Check sustained use for memory warnings or increasing delays.

If problems remain, capture render queue wait, execution time, frame timing, and
native/graphics/total PSS. External-camera footage distinguishes panel refresh
behavior from application-generated missing pixels. Broader renderer/cache tuning
should follow that evidence.

For a debugger inspection, `PdfRenderScheduler.instance` exposes `pendingCount`,
`activeCount`, `peakPendingCount`, `startedCount`, `finishedCount`, and
`cancelledCount`. The queue holds at most 64 pending jobs; these aggregate counters
do not store filenames or document content. `finishedCount` includes non-cancelled
operations that failed and is not a success count.
