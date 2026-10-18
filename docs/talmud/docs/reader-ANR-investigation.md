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

### Device traces collected 16 Oct 2026

Live Bigme B751C runs (Tamid) produced what the October 14 excerpt lacked:
`runA-no-commentary.txt` (logcat, fresh process 16:20:07, first freeze 16:20:42
during rapid page turns), `freeze-B.zip` (bugreport with 4 ANR traces), and
`freeze-B2.zip` (bugreport with 14 further ANR traces, 16:26–17:02). In total,
**eighteen main-thread stacks across several app processes**, all
input-dispatch timeouts. Two episodes pair a MotionEvent ANR with a
FocusEvent ANR about a minute later while still wedged, ending in a
user-requested kill; the 11-commentary retry ANR'd during load (3m53s open)
and then roughly every 90 s for 12+ minutes with brief recoveries between.

Caveats: per-interval CPU burn is inferred from main-thread `schedstat`
deltas between consecutive dumps (~9–11 user CPU-seconds per ~110 s episode),
not from a profiler. The tested builds lacked the diagnostics flag
(`=1` does not enable a Dart boolean flag; `=true` is required), so no
per-phase timings exist yet and the ranking below still rests on trace
shape plus manual timings, not on measured phase durations.

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

### Assessment update from the 16 Oct traces

The common signature across all eighteen stacks: main thread `state=R` in
unsymbolized app frames, no held mutexes, GC (`HeapTaskDaemon`) idle,
sibling threads asleep, top frames in memory copy/allocation
(`__memcpy_aarch64_simd`, `malloc` into `mmap`, atomic-compare primitives),
100% user + ~0% kernel CPU in the sampled window with tens of thousands of
minor page faults, and anonymous RSS ratcheting roughly 18 MB per freeze
episode (168→187 MB, 164→182 MB).

- **H1 (long block measurement/slicing): strengthened, still not isolated.**
  Repeated ~10 s CPU bursts separated by brief recoveries fit indivisible
  synchronous work units rather than one endless stall; the commentary
  multiplier (no-commentary survives 10 flips, 11 commentaries ANR during
  load) fits per-block cost scaling with projected content. The top-frame
  allocation signature fits large painter/layout temporaries.
- **H2 (repeated visible-page layout): unchanged.** No rebuild/paint counts
  exist yet; needs the diagnostics build.
- **H3 (publication/index reconstruction): strengthened as co-candidate.**
  Same burst shape and commentary scaling as H1; per-progress full-spine
  rebuild plus fresh wrapper allocation fits the copy/allocate top frames
  and the RSS ratchet. H1 vs H3 is exactly what the phase timings must
  separate.
- **H4 (pagination-cache conversion): plausible, slightly strengthened.**
  Whole-chapter JSON encode plus UTF-8 conversion on the UI isolate is one
  of the few operations shaped like a single giant copy/allocate burst;
  still needs `cache.save_encode` timings.
- **H5 (loading fallback/other startup work): weakened for this case.**
  Cold opens with sidecars take ~1 s, warm reopens are instant, and
  commentary projection runs on a worker (`Isolate.run`), so the 3m53s
  commentary load burn sits downstream of loading. The fallback flag was
  never observed (no diagnostics); keep as a conditional check, not a lead.
- **H6 (allocation pressure/retained geometry): strengthened as amplifier.**
  The per-episode RSS ratchet and fault counts show accumulation accompanying
  each stall; not established as the trigger.

**Ruled out by the traces (mechanism level):** blocking file/network I/O on
the main thread, mutex/binder contention, plugin-channel blocking, GC
pauses, a native crash (no tombstone/signal; the `crash_dump` log lines are
the system's all-process ANR dump being denied permission, not a crash), an
infinite loop with no forward progress (popups clear and the clock advances
between episodes), and cache corruption (no evidence; repeated work plus
retained sessions suffice to explain reopen freezes).

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
- Preserve complete-entry semantics, settings/content keys, failure recovery, and safe file replacement.
- Measure worker startup, transfer, and result-consumption costs before choosing short-lived versus persistent workers.

`TextPainter`/`dart:ui` layout must not be moved into `Isolate.run`; worker candidates are pure-data work.[^isolates]

#### F. Run a current-chapter-only control experiment

Temporarily suppress automatic distant-chapter pagination while retaining on-demand navigation. Compare otherwise identical runs.

Improvement would support unnecessary background workload as a contributor; it would not isolate one function. This experiment is not the finished three-behind/two-ahead feature, and incomplete page totals must not be presented as whole-book totals.

**Decision point:** if traces instead implicate native/plugin blocking or another path, change the investigation priority. Do not force the evidence to fit pagination.

### Step 4. Revisit the broader reflow design after the targeted work

Keep `responsive-reader-reflow-plan.md` as the larger design track. Preserve its semantic anchors, shared layout requests, generation checks, coherent old-page snapshot, and page-window goals.[^plan]

Before adopting sparse/segment pagination:

- Preserve source-based positions and fallback behavior rather than saving page numbers as anchors.
- Keep the old page, blocks, settings, and required resources coherent until replacement.
- Swap the new target page and its matching data together.
- Define the intended window as three rendered pages behind, one selected page, and two ahead—not six whole chapters.
- Bound text, geometry, measurements, native layout objects, and in-flight work separately.
- Preserve canonical prefix layout until restart/checkpoint equivalence or another boundary model has executable coverage proof.
- Do not assume restarting at an arbitrary offset yields the same page boundaries.
- Define page-number and percent-jump semantics for incomplete layouts.

Splitting a large paragraph or changing projection boundaries requires geometry, source-offset, bidirectional-text, selection, and annotation regression coverage. It is not automatically a safe performance shortcut.

## 5. Tests and acceptance criteria

### Automated checks

Retain the existing reader tests and extend the relevant files, particularly:

- `test/reader/epub_paginator_service_test.dart`
- `test/reader/text_reader_session_test.dart`
- `test/reader/text_page_view_test.dart`
- `test/reader/pagination_cache_service_test.dart`
- `test/reader/tanach_session_test.dart`
- `test/reader/tanach_pagination_test.dart`
- `test/reader/annotation_selection_test.dart`
- `test/reader/state_and_epub_recovery_test.dart`

Required coverage:

- [ ] Responsive/synchronous/cached measurement paths produce equivalent geometry and ordered source coverage.
- [ ] Many small blocks, one large block, split headings, images, RTL/LTR mixtures, vowel settings, and hyphenation are covered.
- [ ] Cancellation is checked before the next generator advance/measure and no superseded work publishes.
- [ ] A timer scheduled during an active run can execute before that run finishes; test many-block and single-block slicing cases separately.
- [ ] Timer progress is not misrepresented as a bound on one synchronous measurement.
- [ ] Unrelated progress does not trigger fresh text layout for unchanged visible content.
- [ ] Genuine page, annotation, selection, and settings changes still update correctly.
- [ ] Navigation waiters do not depend on throttled progress notifications.
- [ ] Cache hit/miss/invalid-entry/failure paths remain correct, with no partial layout stored as complete.
- [ ] Suspend, memory pressure, disposal, and rapid settings changes release/cancel owned work correctly.
- [ ] Bookmarks, semantic anchors, search targets, links, and annotation mapping survive.
- [ ] Any segment-window implementation proves gap-free/nonduplicated coverage and backward/forward chapter-edge navigation.

Existing session tests use synthetic books and controlled futures. Their presence is useful but does not demonstrate B751C responsiveness or bound a single UI-thread operation.

Before proposing an implementation as validated:

```bash
flutter analyze
flutter test test/reader
```

Also run affected project-level tests, including lifecycle/navigation tests, and the device checks below. Commands are proposed gates, not commands executed for this report.

### Device checks

Start with the exact Tamid file and settings that reproduce the issue, then include a larger tractate.

Cover:

- First open with cold pagination data and reopen with warm data.
- Returning through a retained session versus a confirmed process restart.
- Repeated forward/backward turns, including chapter edges.
- Commentary, font-size, and vowel-display changes.
- Suspend/resume and recovery after memory pressure.
- Baseline, each isolated change, and the combined candidate.
- Profile-mode diagnosis and release-mode confirmation.

Run repeated comparable attempts; record the attempt count and failures. No ANR in one run is not proof of elimination. Agree on numerical responsiveness and memory budgets before acceptance; the five-second ANR timeout is not a usability target.

| Metric | Baseline | Candidate |
| --- | --- | --- |
| Run count and exact reproduction scenario | Not collected | Not collected |
| Longest foreground heartbeat delay | Not collected | Not collected |
| Block measurement p50/p95/max and sample count | Not collected | Not collected |
| Visible build/paint layout counts and durations | Not collected | Not collected |
| Publication/index p50/p95/max | Not collected | Not collected |
| Cache conversion p50/p95/max and peak queue | Not collected | Not collected |
| Settings-to-target-ready and first-rendered latency | Not collected | Not collected |
| Forward/backward navigation wait | Not collected | Not collected |
| Peak resident pages, memory, and retained native objects | Not collected | Not collected |
| ANR count and associated trace identifiers | Not collected | Not collected |

## 6. Documentation integration and handoff

Add this as a companion investigation document, not a replacement for the reflow plan.

Suggested additions:

In `docs/README.md`:

```markdown
- [Text reader ANR investigation](talmud/docs/reader-anr-investigation.md) — evidence, suspected causes, and validation steps.
```

In `docs/talmud/docs/responsive-reader-reflow-plan.md`:

```markdown
## Related ANR investigation

See [Text reader ANR investigation](reader-anr-investigation.md) for the current
code findings and targeted performance-validation sequence. The reflow design
is not yet a demonstrated fix for the reported input-dispatch ANR.
```

Record new device results in the active testing documentation, such as `docs/DEVICE_TESTING.md`, or a clearly linked new run log. Do not silently edit archived results to imply that new testing occurred.

### First implementation handoff

1. Match the source and installed build; preserve the reproduction inputs.
2. Add bounded per-phase timings and unchanged-page layout counters.
3. Capture a baseline without changing pagination boundaries.
4. Test one targeted change at a time, beginning with the measured dominant path.
5. Re-run correctness tests and compare device evidence.
6. Update this document with measured findings, including hypotheses weakened or rejected.
7. Seek owner review before merging; documentation creation is not authorization for a production rewrite.

## 7. Current validation status

- Source inspection: completed for the files and paths identified above.
- Exact failing APK mapped to reviewed source: not established.
- Full ANR stack or exported CPU/system trace analyzed for this report: no.
- Actual projected block-size distribution: not measured.
- Application implementation changed by this report: no.
- Confirmed root cause or validated ANR fix: no.

### Implementation note (16 Oct 2026)

The certain, no-regret work from Step 1–2 and Section 6 was implemented;
nothing that changes page geometry or cache semantics was altered:

- Baseline snapshot: source at `10544358bdac1d667e15be716bc695930174b2ab`
  (two commits ahead of the bundle-reported `67e06dc`), working tree clean
  before these changes, Flutter 3.47.1 stable / Dart 3.13.1. The failing APK
  is still not mapped to a source commit; rebuild from the recorded commit
  before any device comparison.
- Added `lib/reader/services/reader_diagnostics.dart`: bounded, dormant-by-default
  phase timings (`paginator.measure`, `session.publish`, `cache.load_decode`,
  `cache.save_encode`, `loading.fallback_ui_layout`), fixed-size ring buffer,
  and a lifecycle-aware heartbeat. No text, paths, or annotation contents are
  recorded.
- The tools are activated with a build flag, no code change or settings UI:
  `flutter run --release --dart-define=READER_DIAGNOSTICS=true` (the value
  must be the word `true`; `=1` leaves them dormant). Without the flag
  everything is a dormant no-op. With it, the session runs the heartbeat
  during each pagination pass and prints the bounded summary (`READER-DX`
  lines) to logcat: periodically during progress, when layout finishes, and
  on suspend/dispose — so a wedged pass that never completes still reports.
- Small safe fixes with final geometry unchanged: cancellation is checked
  before advancing the pagination generator and inside line slicing;
  progress callbacks and chapter publication are skipped when no completed
  page was added (the event-loop yield still happens); the visible-page
  painter compares annotation contents instead of list identity.
- Documentation: investigation linked from `docs/README.md` and the reflow
  plan; TAL-015 opened in `docs/DEVICE_TESTING.md`.
- `flutter analyze` and the reader test suite were run; results are recorded
  with the change, not in this document. ANR traces were collected (see
  below); CPU profile and phase timings are still pending (TAL-015).

### Device evidence (16 Oct 2026, Bigme B751C, Tamid)

Eighteen ANR traces in `freeze-B.zip` / `freeze-B2.zip` (16:17–17:07, several
app processes; logcat in `runA-no-commentary.txt`, `runB-commentary.txt`),
all input-dispatch timeouts with the same signature: main thread `state=R`
in unsymbolized app frames, no held mutexes, GC (`HeapTaskDaemon`) idle,
sibling threads asleep, top frames in memory copy/allocation
(`__memcpy_aarch64_simd`, `malloc` into `mmap`, allocation atomics). The
16:21:37 window measured 100% user + 0.4% kernel CPU with 28,724 minor
faults; anonymous RSS grew roughly 18 MB per freeze episode (168 to 187 MB,
then 164 to 182 MB). The 11-commentary retry opened in 3m53s with ANRs
during load, then ANRs roughly every 90 s for 12+ minutes with brief
recoveries between: per-interval burn is ~9–11 user CPU-seconds per ~110 s
episode, i.e. repeated multi-second synchronous chunks, not one endless
stall. Each no-commentary episode pairs a MotionEvent ANR during rapid page
turns with a FocusEvent ANR about a minute later while still wedged, ending
in a user-requested kill. Commentary projection runs on a worker
(`Isolate.run`), so the load-time burn sits downstream of it. No native
crash occurred (no tombstone/signal; the `crash_dump` lines are the
system's all-process ANR dump being denied permission).

Function-level cause is **not** established: the trace frames are
unsymbolized and the tested builds lacked the diagnostics flag (`=1` does
not enable a Dart boolean flag; `=true` is required), so no `READER-DX`
phase timings exist yet. H1 vs H3 vs H4 awaits those timings plus a CPU
profile with symbols from the flagged rebuild. No fix is validated;
TAL-015 stays OPEN.

**Working conclusion:** investigate repeated UI-isolate layout and publication first, while measuring cache/loading alternatives. Keep correctness and measured input responsiveness as separate acceptance gates.

## References

Repository paths are root-relative descriptions. Bundle-derived findings come from the owner's uploaded source, not assumptions about current `main`. The externally retrieved renderer and screen were pinned to the reported commit. Official documentation was consulted on October 16, 2026.

[^paginator]: Owner-supplied `reader_bundle.txt`, section `lib/reader/services/epub_paginator_service.dart`; symbols `_steps`, `paginateSpineResponsive`, and `TextBlockLayout`.

[^session]: Owner-supplied `reader_bundle.txt`, section `lib/reader/controllers/text_reader_session.dart`; symbols `_repaginate`, `_runPagination`, `_publishChapter`, `_rebuildPages`, `_ensureChapterLoaded`, and `_trimResidentChapters`.

[^page]: Owner-supplied `reader_bundle.txt`, section `lib/reader/widgets/text_page_view.dart`; `_TextPageViewState.build` and annotation-list construction.

[^cache]: Owner-supplied `reader_bundle.txt`, section `lib/reader/services/pagination_cache_service.dart`; `load`, `save`, `_save`, and `_trim`.

[^loading]: Owner-supplied `reader_bundle.txt`, sections `lib/reader/services/parsed_epub_cache_service.dart`, `lib/reader/services/tanach_sqlite_cache_service.dart`, and `lib/reader/services/epub_parser_service.dart`.

[^renderer]: Commit-pinned `lib/reader/widgets/block_slice_view.dart`, especially `_BlockSliceViewState.build`, `_TextBlockPainter.paint`, and `shouldRepaint`. Source: `https://raw.githubusercontent.com/brdsllg/eink_launcher/67e06dcd91c3e9628d95ef04694ef47d45bebb83/lib/reader/widgets/block_slice_view.dart`.

[^screen]: Commit-pinned `lib/reader/screens/reader_screen.dart`, especially `build`, `_buildShell`, and the `TextPageView` construction. Source: `https://raw.githubusercontent.com/brdsllg/eink_launcher/67e06dcd91c3e9628d95ef04694ef47d45bebb83/lib/reader/screens/reader_screen.dart`.

[^plan]: Owner-supplied responsive-reflow plan and commit-pinned repository copy at `docs/talmud/docs/responsive-reader-reflow-plan.md`: `https://raw.githubusercontent.com/brdsllg/eink_launcher/67e06dcd91c3e9628d95ef04694ef47d45bebb83/docs/talmud/docs/responsive-reader-reflow-plan.md`.

[^android]: Android Developers, “Diagnose and fix ANRs,” input-dispatch timeout section: `https://developer.android.com/topic/performance/anrs/diagnose-and-fix-anrs`.

[^threading]: Flutter, “Merged threads on macOS and Windows,” context describing the preceding Android/iOS default merge: `https://docs.flutter.dev/release/breaking-changes/macos-windows-merged-threads`.

[^yield]: Dart API, `Future.delayed` constructor: `https://api.dart.dev/dart-async/Future/Future.delayed.html`.

[^unawaited]: Dart API, `unawaited` function: `https://api.dart.dev/dart-async/unawaited.html`.

[^isolates]: Flutter, “Concurrency and isolates,” including background-isolate restrictions and transfer overhead: `https://docs.flutter.dev/perf/isolates`.

[^textpainter]: Flutter API, `TextPainter` class, layout lifecycle and resource disposal: `https://api.flutter.dev/flutter/painting/TextPainter-class.html`.

[^profiler]: Flutter DevTools, “Use the CPU profiler view”: `https://docs.flutter.dev/tools/devtools/cpu-profiler`.
