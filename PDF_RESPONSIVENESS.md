# PDF responsiveness follow-up

The original HiBreak observations are in
[BIGME_TEST_LOG.md](BIGME_TEST_LOG.md). Rapid taps were reported working after the
first response update. Version 1.0.2 adds more coverage for white pages during
extreme minimum-zoom scrolling and lets a resting finger stop momentum.

## Implemented response work

### Rendering and navigation

- A shared priority scheduler admits one PDF render/crop operation at a time,
  before PDFium allocates its output buffer. Visible coverage precedes sharp detail
  and speculative work.
- Crop samples are capped at 512 pixels in both dimensions and invalid geometry is
  rejected before rendering.
- Matching unfinished crop/bitmap requests share work. View changes can promote
  relevant jobs and withdraw obsolete queued jobs; an active synchronous PDFium
  call still has to finish.
- Rapid Fit Height/Fit Width navigation is processed in input order through
  asynchronous crop calculations. Session disposal, suspension, mode changes, and
  explicit jumps invalidate stale work.

### Pixels during zoom and movement

- Zoom / Scroll displays small correct-page previews below detailed tiles.
- Useful old detail remains during a density change until the visible replacement
  is ready; a fixed timeout no longer removes it.
- Sharp refinement begins after 200 ms of idle time. Ordinary fit-mode page turns
  do not wait a mandatory second.
- Preview/detail demand follows the viewport and is cancelled when no longer
  useful.

### Fast-scroll coverage in version 1.0.2

- Whole-page previews use a 320-pixel longest edge and persist in a versioned,
  64 MiB disk LRU keyed by document identity and geometry. Corrupt and partial
  entries are deleted.
- Only visible/nearby previews are decoded into memory. Missing previews are warmed
  at idle priority and yield to visible rendering.
- Signed scroll velocity expands preview demand in the direction of travel, capped
  at four screen lengths and 16 pages. Direction reversal cancels the old
  projection; settling returns demand to one screen so detail regains priority.
- Warming stops on touch, backgrounding, suspension, memory pressure, or leaving
  the reader.
- A raw finger-down event stops an active fling immediately, before a drag is
  recognized. Pan and pinch continue from the stopped position.

## Practical limit

A page with no memory or disk preview still needs its first PDFium render. At
minimum zoom, a very fast fling can expose several previously unseen pages each
second and briefly outrun that work. The persistent cache improves prepared pages
and later passes; it does not render every page of a newly opened document at
startup.

The scheduler also does not bound the entire process. Widget-owned images, one
active native render, PDFium document data, and graphics allocations sit outside
the retained bitmap caches. Existing session suspension and memory-pressure
recovery remain necessary.

## Verification

The complete suite passes **240 Flutter tests** with `PDF_NATIVE_STRESS=1`. The
generated-document native PDFium test ran; the older test requiring an external
PDF was skipped. Static analysis reports no issues.

Coverage includes rapid ordered navigation, shared/cancelled work, queue bounds,
crop-buffer safety, delayed nonwhite pages, zoom handoff, refinement retry,
persistent preview round-trips and eviction, corrupt/partial cache entries,
cross-session reuse, velocity-expanded demand, reversal, and finger-down fling
cancellation.

Run the native PDFium check on a supported host with:

```powershell
$env:PDF_NATIVE_STRESS = '1'
flutter test --no-pub test/reader/pdf_native_render_stress_test.dart
Remove-Item Env:PDF_NATIVE_STRESS
```

Host tests establish app state and image behavior, not e-ink panel refresh quality.

## Current APK

Version **1.0.2 (build 3)** is available as
[eink-launcher-1.0.2-scroll-previews.apk](build/app/outputs/flutter-apk/eink-launcher-1.0.2-scroll-previews.apk)
(31,803,551 bytes, about 30.3 MiB). It is an arm64 release build using the existing
personal-sideload signing setup. Android package/version metadata and the v2
signature were verified.

SHA-256: `8231F46FF8A086EF84C50AA416EADE9589A64E0599F7EB45CD7F2EA6D0317CAB`

## Short device check

Use a small text/vector PDF and a scanned PDF with the same renderer and Bigme
refresh mode.

1. Tap rapidly in Fit Height and Fit Width, reverse direction, and check the centre
   menu and Android Back while work is pending.
2. Pinch in/out repeatedly, including a new pinch before sharpening finishes.
   Check whether useful content remains visible after release.
3. At minimum zoom, scroll quickly, reverse direction, then rest a finger on the
   screen. Compare the first pass with a second pass over the same pages.
4. Record time to first useful preview separately from time to sharp text. Reopen
   the document and confirm position, mode, and bookmarks.
5. During sustained use, note memory warnings or delays that grow over time.

If a problem remains, collect queue wait/execution time, frame timing, and Android
native/graphics/total PSS. `PdfRenderScheduler.instance` exposes bounded aggregate
debug counters for pending, active, started, finished, cancelled, and peak pending
work; it stores no filenames or document content.
