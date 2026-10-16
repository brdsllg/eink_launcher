# Text reader ANR investigation and next steps

**Status:** Draft investigation. Suspected causes, not a confirmed diagnosis or validated fix.  
**Updated:** October 16, 2026  
**Project:** `brdsllg/eink_launcher`  
**Suggested location:** `docs/talmud/docs/reader-anr-investigation.md`  
**Bundle-reported commit:** `67e06dcd91c3e9628d95ef04694ef47d45bebb83`

## Summary

The owner reports recurring Android “app not responding” errors when opening or reading tractates, including Tamid. After an incident, opening the same file can trigger another ANR.

The leading theory is **excessive uninterrupted and repeated UI-isolate work across pagination, visible-page rendering, publication, and cache conversion**. The paginator has genuine asynchronous yield points, but they do not cover every expensive operation.

Confidence in that overall theory is **moderate, approximately 7/10**. This is a qualitative code-review judgment, not a measured probability. Confidence that the individual code patterns exist is higher than confidence that any particular pattern caused the reported ANR.

**No individual five-second operation has been demonstrated. No fix, benchmark result, or regression-test pass is claimed here.** The next step is a bounded baseline and small, independently testable changes—not an immediate rewrite of the pagination boundary model.

## 1. Evidence and scope

### Owner-reported environment

| Item | Supplied information |
| --- | --- |
| Device | Bigme B751C, as identified in the issue discussion |
| Android | Android 14 |
| RAM | 4 GB |
| Processor | MediaTek Helio P35 / MT6765 |
| Display | 7-inch e-ink; reported monochrome resolution 1264 × 1680 |
| Flutter | 3.47.0 stable; framework revision `4cf2416426` |
| Engine | Hash `59d54a2b2896a6bbf356c94b7fac7b9e235bdacd`; revision `5f77625673` |
| Dart / DevTools | Dart 3.13.0 / DevTools 2.60.0 |
| Build command | `flutter run --release` |
| Log collection | Device connected through ADB |

These are supplied details, not independently measured hardware specifications or a verified mapping from toolchain to installed APK. Physical display resolution is not the Flutter logical viewport; record the latter during testing.

### Observed log

```text
10-14 18:30:26.787  1322  1446 I WindowManager: ANR in Window{8659771 u0 com.example.eink_launcher/com.example.eink_launcher.MainActivity}. Reason:Input dispatching timed out (8659771 com.example.eink_launcher/com.example.eink_launcher.MainActivity (server) is not responding. Waited 5000ms for MotionEvent)
```

This establishes an **input-dispatch timeout**, not the function responsible. Android documents a default five-second timeout for this ANR category and several possible causes, including main-thread computation, blocking operations, and contention.[^android]

The discussion places the incident on October 14, 2026; the excerpt itself contains no year or timezone. The bundle identifies a commit dated October 15, 2026 at 21:16:25 +1100. Therefore, the reviewed source is not automatically the source of the failing APK.

### Materials reviewed

- The uploaded `reader_bundle.txt`, including the session, paginator, pagination cache, page widget, parsing/loading services, and two reader test files.
- `block_slice_view.dart` and `reader_screen.dart`, retrieved separately at the bundle-reported commit.[^renderer][^screen]
- The supplied responsive-reflow plan and its repository copy.[^plan]
- Official Flutter, Dart, and Android documentation listed below.

The bundle was generated from working-tree files. Its commit header does **not** establish that the working tree was clean. Symbol references below describe the supplied files; recheck them against the implementation branch before editing.

The bundle's root-level documentation reads failed because those files were not at those locations. The supplied file list places active plans under `docs/` and the old Bigme log under `docs/archived/root/`. Those command errors do not mean the documentation is absent.

The earlier plan described a CPU-bound main thread with unsymbolized Dart frames. That description was not independently established from a complete ANR stack in this review.

## 2. Code findings

“Confirmed” below means visible in the reviewed source, not measured on the device.

### F1. The pagination budget does not bound a synchronous work interval

**Source:** `lib/reader/services/epub_paginator_service.dart` — `_steps`, `paginateSpineResponsive`, `TextBlockLayout.measure`.[^paginator]

Confirmed behavior:

- `_steps` measures an entire block before entering its page-slicing loop.
- Text measurement includes painter layout, line metrics, display/source-offset preparation, and per-line boundary lookups.
- The slicing loop finishes processing that block before the timed publication check.
- The timed check requires the completed-page count to have changed. Work producing no completed page relies on the mandatory block-count checkpoint.
- Mandatory checkpoints occur between batches of 16 blocks.
- The no-line branch uses `continue`, bypassing the timed check at the bottom of the block loop.
- The asynchronous wrapper calls `onProgress` before its event-loop yield.

Therefore, `defaultYieldBudget = 16 ms` is **not a hard maximum** for block measurement, slicing, publication, or subsequent frame work. A large block could delay even the first page it produces until the whole block has been processed.

Cancellation also has a blind spot: in the wrapper's `for` loop, advancing the synchronous generator happens **before** the loop-body `isCancelled()` check. A superseded run can do more generator work before observing cancellation. Checks are needed before advancement and within cooperative work boundaries.

Unknown: the actual largest projected block, its measurement time, and whether this path reaches ANR-scale delays.

### F2. Visible-page rendering repeats whole-block layout

**Source:** `lib/reader/widgets/block_slice_view.dart`.[^renderer]

Confirmed behavior:

- `_BlockSliceViewState.build`, inside its `LayoutBuilder`, calls `TextBlockLayout.measure` for the complete block.
- `_TextBlockPainter.paint` creates another laid-out painter for the complete block.
- Clipping and translating select the visible slice; they do not eliminate those preceding layout calls.
- Annotation hit targets and selection interactions have additional painter-creation paths.
- `_TextBlockPainter.shouldRepaint` compares annotation lists with `!=`.

Consequently, a block already measured during pagination can be measured again during widget layout and again during painting. The actual number and duration of executions need instrumentation; this is not evidence that every notification causes a separate frame or ANR.

### F3. Progress publication repeats global bookkeeping and can invalidate visible content

**Sources:** `text_reader_session.dart`, `text_page_view.dart`, and `reader_screen.dart`.[^session][^page][^screen]

Confirmed behavior:

- `_publishChapter` replaces a chapter's published list, signals publication waiters, calls `_rebuildPages`, and notifies listeners.
- `_rebuildPages` walks the spine and creates fresh wrappers for every previously published page, then searches for the selected position.
- `_steps` also copies its growing chapter-page list for each yielded snapshot.
- A mandatory batch yield can republish the same nonempty page set without adding a completed page.
- `ReaderScreen.build` uses a `ListenableBuilder` for the session and constructs the text-page subtree through its shell.
- `TextPageView` constructs fresh filtered annotation lists with `.toList()`.

Together with F2, this gives unrelated pagination progress a path to redundant visible-page work. Flutter can coalesce rebuild requests, so notification count must not be presented as an identical rebuild or repaint count.

The global list-copying and wrapping costs grow with accumulated pages. No measured scaling curve or ANR-sized publication has yet been established.

### F4. Background pagination is still a whole-book workload

**Source:** `text_reader_session.dart` — `_repaginate`, `_runPagination`, `_trimResidentChapters`.[^session]

`_repaginate` schedules the current chapter, then every later chapter, then earlier chapters. `awaitComplete: false` changes when the caller returns; it does not cancel the remaining whole-spine work.

The lazy-text residency policy unloads chapter blocks but retains `_chapterPages`, `_pages`, and completion metadata. A limit of three resident text chapters is therefore not a limit of three chapters' page geometry, nor a rendered-page memory budget.

This is a workload and memory amplifier. It does not, by itself, prove a long uninterrupted main-thread stall.

### F5. Pagination-cache conversion remains synchronous

**Source:** `lib/reader/services/pagination_cache_service.dart` — `load`, `_save`, `save`.[^cache]

File operations are awaited, but JSON decoding, page-object reconstruction, page-to-JSON conversion, and JSON/UTF-8 encoding run synchronously on the calling isolate.

The session's `unawaited(_savePages(...))` does not move that conversion onto a worker. Dart's `unawaited` deliberately changes neither execution nor error behavior; it only expresses that a future is not being awaited.[^unawaited]

Additional risks to measure:

- `_writes` serializes writes, but pending work can retain page lists.
- The encoded-size rejection happens after constructing the encoded representation.
- A disk byte limit does not bound temporary allocations or decoded in-memory objects.

Unknown: actual entry sizes, conversion durations, queue depth, and whether a problematic reopen takes this path.

### F6. Loading has a synchronous fallback worth instrumenting

**Sources:** `parsed_epub_cache_service.dart` and `tanach_sqlite_cache_service.dart`.[^loading]

Normal parsing, parsed-cache conversion, SQLite import/skeleton reading, and lazy chapter projection already use worker isolates in the reviewed paths. Do not describe all loading as UI-isolate work.

However:

- After SQLite import failure, `ParsedEpubCacheService.load` directly calls `TanachLayoutService.layout(...)` in its fallback. That call is not wrapped in an isolate at that point.
- `TanachSqliteCacheService._trim` uses synchronous file metadata calls during sorting and size accounting.
- `_ensureChapterLoaded` has no shared in-flight load map of its own; chapter-layout deduplication does not automatically prove that every concurrent chapter-loading request is deduplicated.

These are conditional investigation targets, not established causes. Record fallback activation, metadata time, and load counts before assigning them greater priority.

## 3. Working hypothesis and limits

The suspected sequence is:

```text
Open a book or change settings
  → load/project content
  → measure and slice blocks
  → publish progress and rebuild the page index
  → potentially rebuild/paint unchanged visible text
  → continue through distant chapters and convert page caches
```

The important question is **which operation, or sequence of operations, prevents timely input processing**. Large total CPU usage alone does not prove the input timeout.

Flutter documents merged UI/platform threads on modern Android builds, making UI-isolate blocking relevant to native input handling. Verify the actual APK/engine configuration when collecting the trace rather than treating the supplied version string as a runtime trace.[^threading]

| Hypothesis | Current assessment | Evidence that would strengthen it | Evidence that would weaken it |
| --- | --- | --- | --- |
| H1: Long block measurement or slicing | Leading candidate | Long individual spans aligned with event-loop delay | Representative worst-case blocks remain short during reproduced incidents |
| H2: Repeated visible-page layout | Leading amplifier | High repeated-layout counts for unchanged content; reduced stalls after isolation/reuse | Little visible-page work during the incident |
| H3: Publication/index reconstruction | Confirmed repeated work; causal weight unknown | Publication duration grows materially with retained pages | Publication remains consistently cheap |
| H4: Pagination-cache conversion | Plausible, including reopen cases | Decode/encode spans overlap the delay; worker conversion improves it | Incident occurs before conversion or conversion is cheap |
| H5: Loading fallback or other startup work | Conditional candidate | Fallback flag, load spans, or metadata operations identify the stall | Normal worker path is used with short UI handoffs |
| H6: Allocation pressure and retained geometry | Possible amplifier | Memory/GC trace and queue growth correlate with stalls | Stable residency and no relevant allocation/GC pressure |

These hypotheses overlap; the rows are not probabilities.

### Conclusions not supported by current evidence

- The paginator is **not** merely yielding to microtasks: it explicitly uses `Future.delayed(Duration.zero)`, which schedules completion no earlier than a subsequent event-loop iteration.[^yield] That opportunity does not guarantee a maximum input latency.
- A page failing to appear during a timed wait does not prove an infinite loop.
- The shown line-fitting loop has an explicit forward-progress safeguard. That reduces the specific “oversized line never advances” concern, without proving all loops are safe.
- Reopening after an ANR does not establish cache corruption or even a process restart. It can repeat expensive work or reuse a retained session.
- Tamid reproducing does not rule out size-related costs: projected block shape, active commentary, startup work, and cache state matter as well as total book length.
- The supplied build command does not establish which symbols or other build artifacts remain available. Preserve the original log/APK; do not discard them on the assumption that symbolization is impossible.

## 4. Next steps

### Step 1. Establish a comparable baseline

Do this before changing layout semantics or deleting caches.

- Record the installed APK identity, build mode, source commit, working-tree changes, Flutter/engine revisions, and build command.
- Identify the exact Tamid EPUB by content fingerprint; record sidecar presence/version and saved anchor.
- Record settings, logical viewport, font selection, commentary/translation choices, and vowel/hyphenation settings.
- Distinguish a cold process, a reopened retained session, a pagination-cache hit, and a pagination-cache miss. A warm parse cache is a separate condition.
- Preserve bookmarks, annotations, and settings. Prefer an isolated diagnostic cache namespace or explicit cache-bypass flag over clearing app storage.
- Obtain a profile-mode reproduction on the same device, then validate any improvement in release mode. DevTools CPU profiling identifies where Dart execution time is spent.[^profiler]

Useful commands from the project root:

```bash
git rev-parse HEAD
git status --short
flutter --version
flutter run --profile
```

Use the DevTools address printed by Flutter. Record the CPU profile while opening Tamid and export the result. If the issue is intermittent or the profile is inconclusive, capture the corresponding Android ANR trace/system trace. The owner can perform device runs later; they are not prerequisites for adding this investigation document.

### Step 2. Add bounded diagnostics

Use optional fixed-size counters/ring-buffer events and monotonic timing. Keep diagnostics off by default outside investigation builds.

Measure separately:

- Book-open stages, worker handoff, projection, and fallback activation.
- `TextBlockLayout.measure` by call site: paginator versus visible widget.
- Painter creation/layout, line/offset preparation, and page slicing.
- `_publishChapter`, `_rebuildPages`, and position lookup.
- Notifications, actual visible-widget rebuilds, actual paints, and unchanged-content layout calls.
- Cache read/decode/reconstruction, encoding, write-queue depth, and outstanding payload size.
- Resident blocks/pages, measurement-cache entries, native painter ownership, and memory/GC behavior.
- Settings-to-target-layout-ready, target-first-rendered, and navigation-completed latency.

For block events, record generation, spine/block indices, character/run/line counts, duration, and cancellation status—not source text.

Add a lifecycle-aware event-loop heartbeat. Report foreground timing gaps separately from suspension. A delayed heartbeat indicates delayed callback service; it does not, alone, identify the responsible function or distinguish computation from scheduling/GC.

Report p50, p95, maximum, and sample count. Preserve a small bounded tail of recent phase information so an ANR is not documented only by a later “finished” event. Avoid per-character logging, unbounded traces, synchronous diagnostic writes, document paths, excerpts, or annotation contents.

**Output:** a measured ranking of H1–H6, including the longest contiguous work intervals—not just total pagination duration.

### Step 3. Make small, independently testable changes

Choose the order using the baseline. Keep changes separable so their effects can be compared.

#### A. Isolate progress from unchanged visible content

- Separate content invalidation from page-count/progress updates.
- Preserve immediate target-ready, navigation, error, and completion updates.
- Release navigation/publication waiters independently of UI-notification throttling.
- Use stable content/annotation revisions or correct value comparisons.
- Do not set `shouldRepaint` permanently false; genuine selection, annotation, settings, and page changes must still update.
- Treat a repaint boundary as an optional adjunct, not a substitute for preventing unnecessary build/layout work.

#### B. Remove redundant publication and indexing work

- Avoid publishing an unchanged page set solely to give the event loop a turn.
- Separate yielding, internal publication, and visible notifications.
- Avoid recreating all earlier page wrappers for each append.
- Preserve spine order and correct navigation when chapters arrive out of order.
- Keep ordinal/index metadata separate from stable content identity where practical.

#### C. Reuse measurements and visible layout safely

- Start with immutable measurement results and a tightly bounded visible-layout cache.
- Define keys from actual layout inputs: source identity/revision, styled runs, direction, width, typography, display transformations, relevant publisher properties, and image/page-height constraints.
- Do not assume an unchanged block ID means unchanged content.
- Keep native painters on the UI isolate. Give any retained painter an explicit owner and dispose it on replacement, eviction, or teardown.[^textpainter]
- Measure memory as well as speed. An unbounded whole-book painter cache is not an acceptable fix.
- Reuse across commentary toggles only when all relevant block/layout inputs actually match.

#### D. Cover cooperative work and cancellation gaps

- Check cancellation before starting/resuming expensive generator work, between block measures, during slicing, and before publication.
- Allow a yield when elapsed work warrants it even if no page has completed.
- Include non-text/no-line branches in the policy.
- Keep synchronous and responsive pagination geometrically identical.
- Remember that cooperative checks cannot interrupt a synchronous native text-layout call already in progress.

Do not claim that adding more yields alone bounds every operation.

#### E. Move suitable cache/fallback computation to workers

- Resolve platform-dependent cache locations before worker handoff where needed.
- Move large JSON conversion and page reconstruction off the UI isolate.
- Keep expensive pure projection off the UI isolate on fallback paths too.
- Bound outstanding writes and retained payloads; coalesce superseded optional work where safe.
- Preserve complete-entry semantics, settings/c
