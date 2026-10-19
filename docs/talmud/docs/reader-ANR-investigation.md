# Text reader "not responding" (ANR) investigation

| | |
| --- | --- |
| Issue | TAL-015 in [DEVICE_TESTING.md](../../DEVICE_TESTING.md). That file is the only place that says whether the problem is fixed. This document never does. |
| Last updated | 18 Oct 2026 |
| Device | Bigme HiBreak (model B751C), Android 14 |
| App package | `com.example.eink_launcher` |
| Source | Reviewed at commit `10544358bdac1d667e15be716bc695930174b2ab`, plus the uncommitted edits listed in Section 6 |

**How facts are labelled.** *Measured* = seen in device logs or traces. *In code* = visible in the source files. *Reported* = told to us by the owner, not independently checked. *Inferred* = worked out from other facts. A fact with no label is a plain statement of what this document does.

## 1. In plain words

When you open or read a Talmud tractate such as Tamid, the tablet sometimes freezes for several seconds and Android shows "app not responding". Opening the same book again can freeze it again.

Every device trace collected so far looks the same: the reader app was busy working flat out. It was not waiting on the disk, the network or another process, and it had not crashed. The work comes in bursts of several seconds, and the app's memory use grows a little with each freeze. It is worse with commentary switched on: Tamid with 11 commentaries took almost 4 minutes to open and froze again and again. Without commentary it also froze, during rapid page turning.

The most likely cause is that the app does a lot of page-layout work in one stretch, on the same thread that handles your taps, so taps wait. **We do not yet know which job is the slow one.** Three suspects fit the evidence equally well: laying out very large blocks of text, rebuilding the list of pages every time progress is reported, and saving page layouts to disk.

Nothing is confirmed and no fix has been checked on the device. The next step is to repeat the freeze with the timing tools switched on, plus one experiment that lays out only the chapter you are reading (Section 7).

## 2. What is established and what is not

| Established | Not established |
| --- | --- |
| The freezes are Android input timeouts: the app did not handle a touch or focus event for 5 seconds (measured). | Which function is responsible. The traces show unnamed app code (measured). |
| During freezes the main thread was running app code, holding no locks, with garbage collection idle (measured, 18 traces). | Whether layout, page-list rebuilding, or cache saving is the dominant cost. |
| The suspect code patterns exist in the source (Section 4). | That any one of those patterns caused a freeze. |
| Commentary makes it much worse (measured, Run B). | The size of the largest block of text being laid out. |
| Memory grows about 18 MB per freeze (measured). | Whether that growth is a cause or a side effect. |

**Validation status**

| Item | State |
| --- | --- |
| Source inspection | Re-checked on 18 Oct for the paginator, the session, the page painter and the pagination cache. Other files are carried forward from the 16 Oct review (Section 4 says which). |
| Installed APK matched to a source commit | No |
| ANR stacks collected | Yes, 18, on 16 Oct. Not symbolized, so function names are unknown. |
| Phase timings (READER-DX lines) | None seen. Whether the saved logs contain any is unchecked (Section 7, step 1). |
| CPU profile | None |
| Block-size distribution | Not measured |
| Code changed | Yes (Section 6). Not checked on the device. |
| Root cause confirmed, or fix validated | No |

## 3. Evidence

### 3.1 Device and toolchain

| Item | Value | Label |
| --- | --- | --- |
| Device | Bigme HiBreak (B751C), Android 14 | Reported |
| RAM / processor | 4 GB, MediaTek Helio P35 (MT6765) | Reported |
| Display | 7-inch e-ink, 1264 x 1680 physical pixels. The Flutter viewport is a different, logical size and must be recorded for each test. | Reported |
| Flutter / Dart | Discussion: Flutter 3.47.0, Dart 3.13.0. The 16 Oct baseline recorded Flutter 3.47.1, Dart 3.13.1. Record `flutter --version` for every run. | Reported |
| Build command | `flutter run --release` | Reported |
| Logs | Collected over wireless ADB | Reported |

These are supplied details, not a verified mapping from toolchain to the installed APK.

### 3.2 The first log (14 Oct)

```text
10-14 18:30:26.787  1322  1446 I WindowManager: ANR in Window{8659771 u0 com.example.eink_launcher/com.example.eink_launcher.MainActivity}. Reason:Input dispatching timed out (8659771 com.example.eink_launcher/com.example.eink_launcher.MainActivity (server) is not responding. Waited 5000ms for MotionEvent)
```

This shows an input-dispatch timeout, not the function responsible. Android documents a five-second default for this kind of ANR and lists several possible causes, including main-thread computation, blocking calls and lock contention.[^android] The excerpt has no year or time zone; the discussion places it on 14 Oct 2026. The source reviewed here is dated later (the 15 Oct commit used as the first review point was `67e06dcd91c3e9628d95ef04694ef47d45bebb83`), so it is not necessarily the code that produced this log.

### 3.3 Device runs on 16 Oct (Tamid)

Files are in the repository root:

- `runA-no-commentary.txt`: logcat, no commentary. Fresh process at 16:20:07; first freeze at 16:20:42 during rapid page turns.
- `runB-commentary.txt`: logcat, 11 commentaries. The log runs from 16:55:04 to 17:11:39 (checked 18 Oct). It is saved as UTF-16 text; see Section 7, step 1.
- `freeze-B.zip`: bug report with 4 ANR traces.
- `freeze-B2.zip`: bug report with 14 further ANR traces (16:26 to 17:02).

Together these hold **18 main-thread stacks across several app processes, all input-dispatch timeouts** (measured). Every trace has the same signature:

- Main thread in the Running state, in unsymbolized app frames.
- No locks held, garbage-collection thread idle, sibling threads asleep.
- Top frames in memory copying and allocation (`__memcpy_aarch64_simd`, `malloc` into `mmap`, allocation atomics).
- In the 16:21:37 window: 100% user CPU, about 0.4% kernel CPU, 28,724 minor page faults.
- Anonymous memory grew about 18 MB per freeze (168 to 187 MB, then 164 to 182 MB).

Pattern across episodes (from the 16 Oct write-up; per-episode times have not been re-extracted from the zip files):

- Each freeze burned about 9 to 11 CPU-seconds over roughly 110 seconds (inferred from changes in the main thread's CPU counter between dumps, not from a profiler). That fits repeated multi-second chunks of work with brief recoveries, not one endless stall.
- In the run without commentary, at least two episodes paired a touch-event ANR with a focus-event ANR about a minute later while the app was still stuck, ending when the owner closed the app.
- With 11 commentaries, the book took 3 min 53 s to open with ANRs during loading, then froze roughly every 90 seconds for more than 12 minutes with brief recoveries between.
- Reported: opening Tamid with its sidecar file and no commentary took about 1 second cold, and reopening was instant.

### 3.4 Limits of this evidence

- Per-episode CPU figures are inferred, as above.
- The traces do not name functions, so the suspects in Section 5 are ranked by trace shape and by how the problem scales with commentary, not by measured durations.
- The test builds produced no READER-DX timing lines that anyone has seen. The cause is unconfirmed. The source comment for the diagnostics switch said to use `=1`, which does not turn a Dart boolean flag on (`=true` is required). That comment was corrected on 18 Oct. Other possibilities: the `=true` build never reached the device, or the saved log is unreadable to plain search tools.
- The installed APK was never matched to a source commit.
- Reopening after a freeze does not show whether the app process restarted.

## 4. What the code does

"In code" findings. "Re-checked 18 Oct" means read again in the current files. "Carried forward" means taken from the 16 Oct review and not re-read.

### F1. The 16 ms work budget does not cap a single step (re-checked 18 Oct)

`lib/reader/services/epub_paginator_service.dart`, function `_steps`.

- Each text block is measured in full before it is cut into pages. Measuring includes building a text painter, reading line positions, and mapping display offsets back to source offsets.
- Pages are published on a timer (16 ms of work) only after a block finishes, and only when a page has completed. A mandatory pause happens every 16 blocks.
- A block with no text lines (for example an image) skips the timed check.
- So the 16 ms budget is not a hard maximum. One very large block can delay everything until it is fully measured.
- Cancellation: the asynchronous wrapper now checks before and after each step and inside line slicing (16 Oct change). It still cannot interrupt a measurement already in progress.

Unknown: the size of the largest block and how long it takes to measure.

### F2. Visible pages measure whole blocks again (re-checked 18 Oct)

`lib/reader/widgets/block_slice_view.dart`.

- Building a visible slice measures the whole block again. Painting creates another full text painter for the whole block. Clipping only selects the visible part afterwards.
- Selection, links and annotation hit areas create further painters.
- The repaint check used to compare annotation lists by identity; it now compares their contents (16 Oct change), so unrelated progress should no longer repaint unchanged text.

Unknown: how many extra measurements happen during a freeze. There is no timer on this path yet.

### F3. Each progress update rebuilds global bookkeeping (re-checked 18 Oct, except where noted)

`lib/reader/controllers/text_reader_session.dart`.

- `_publishChapter` stores the pages, releases waiting page turns, calls `_rebuildPages`, and notifies listeners.
- `_rebuildPages` walks the whole book and creates a new wrapper for every page published so far.
- The paginator copies its growing page list for each progress snapshot.
- Since 16 Oct, a progress update that adds no completed page is dropped. Completed chapters always publish.
- Carried forward: the text page view builds fresh filtered annotation lists on every build.

Cost grows with the number of pages published. No measured curve exists yet.

### F4. Background layout covers the whole book (re-checked 18 Oct)

`_repaginate` lays out the current chapter first, then every later chapter, then earlier ones. Not waiting for the whole book changes when the caller returns; it does not stop the remaining work. The residency limit on loaded chapter text does not limit the stored page layouts, which are kept for every chapter. This multiplies work and memory but does not by itself prove a long stall.

Since 18 Oct a build flag can limit the background pass to the current chapter (Section 6).

### F5. Cache saving and loading run on the main thread (re-checked 18 Oct)

`lib/reader/services/pagination_cache_service.dart`.

- File reads and writes are awaited, but turning pages into JSON, JSON into bytes, and the reverse all run synchronously on the main thread.
- The session saves in the background without waiting, which changes when the caller returns, not where the work runs.
- A save that is too large is rejected only after the whole thing has been encoded.

Unknown: how big the entries are and how long conversion takes.

### F6. Loading has a fallback that runs on the main thread (carried forward)

`parsed_epub_cache_service.dart` and `tanach_sqlite_cache_service.dart`. Normal parsing and projection already run on worker isolates. If the database import fails, one fallback runs the layout directly. Cache trimming also uses synchronous file calls. These are conditional checks, not established causes.

## 5. Suspects

The rows overlap; they are not probabilities. "Current view" uses all the evidence in Section 3.

| ID | Suspect | Current view | Evidence that would settle it |
| --- | --- | --- | --- |
| H1 | Long block measurement or slicing (F1) | Leading candidate. Repeated multi-second bursts and the commentary effect fit work that grows with block content. | One `paginator.measure` sample lasting seconds |
| H2 | Repeated visible-page layout (F2) | Possible amplifier. No timing exists for this path. | A new timer on visible-page measure and paint |
| H3 | Page-list rebuilding on each progress update (F3) | Co-candidate with H1. Copy-and-allocate frames and the memory growth fit it. | `session.publish` samples that grow with page count |
| H4 | Cache conversion on the main thread (F5) | Plausible. A whole-chapter JSON encode is one of the few single large copy-and-allocate jobs. | `cache.save_encode` or `cache.load_decode` samples lasting seconds |
| H5 | Loading fallback or other startup work (F6) | Weakened for this case: Tamid with its sidecar opened quickly, and commentary projection runs on a worker. | The fallback timer firing |
| H6 | Memory pressure from retained layouts (F4) | Possible amplifier. Memory growth accompanies each freeze; not shown to be the trigger. | Memory growth lining up with stalls across several runs |

**Not seen in any of the 18 sampled traces:** waiting on disk, network or other processes; lock contention; garbage-collection pauses; a native crash (the `crash_dump` log lines are the system's all-process ANR dump being denied permission, not a crash); a loop with no forward progress (popups clear and the clock advances between episodes).

**No evidence for, which is not the same as ruled out:** damaged saved layouts (repeated work or a kept session would explain freezes on reopening); plugin or platform-channel blocking (no sign in the stacks).

**What this document does not claim:**

- That the paginator never yields. It pauses with `Future.delayed(Duration.zero)`, which lets other events run, but that is no guarantee of a maximum delay.[^yield]
- That a page failing to appear in time means an endless loop. The line-fitting loop also has a forward-progress safeguard.
- That reopening after a freeze means the cache is damaged or the process restarted.
- That Tamid freezing means book length does not matter. Block shape, commentary and cache state matter too.
- Anything about which build symbols are available. Keep the original logs and APK.

## 6. Code changes so far

None of these has been checked on the device. None changes page geometry or the cache format.

| Date | Change |
| --- | --- |
| 16 Oct | Added `lib/reader/services/reader_diagnostics.dart`: opt-in timings for `paginator.measure`, `session.publish`, `cache.load_decode`, `cache.save_encode` and `loading.fallback_ui_layout`; fixed-size buffers; an event-loop heartbeat. It records durations and counts only, never text, paths or notes. |
| 16 Oct | The paginator checks for cancellation before and after each step and inside line slicing (F1). |
| 16 Oct | Chapter progress is published only when a new completed page exists (F3). The pause that lets taps through still happens. |
| 16 Oct | The page painter compares annotation contents instead of list identity (F2). |
| 16 Oct | Periodic (30 s), on-suspend and on-dispose diagnostics dumps, so a stuck pass still reports. |
| 18 Oct | Added the experiment switch `READER_CURRENT_CHAPTER_ONLY` to `text_reader_session.dart`. Off by default; with it on, the background pass lays out only the chapter holding the reading position and other chapters are laid out on demand. Page counts and percentages are incomplete while it is on. Never ship a build with it on. |
| 18 Oct | Corrected the comment in `reader_diagnostics.dart`: the switch value must be the word `true`. |

Two cautions:

- The 16 Oct changes were made before any device baseline existed, the reverse of the order recommended here. Because the installed build from the 16 Oct runs was never matched to a source commit, it is not known which of them that build contained.
- The 18 Oct edits compile (`flutter analyze --no-pub` reports no issues) and the reader tests pass apart from two failures in code those edits do not touch (see "Code check" in Section 10). They have not been run on the device.

## 7. How to run the test

All commands are PowerShell, run from the repository root. The tablet must be connected over ADB (`adb devices` should list it).

### Step 1. Check the logs you already have

The saved logs are UTF-16, which `findstr` and most search tools cannot read. `Select-String` can:

```powershell
Select-String -Path runA-no-commentary.txt,runB-commentary.txt -Pattern "READER-DX"
Select-String -Path runA-no-commentary.txt,runB-commentary.txt -Pattern "ANR in"
```

If READER-DX lines appear, the timing tools worked and the numbers already exist: copy those lines into the results log (Section 10). If not, continue.

### Step 2. Check the code and record the build

```powershell
flutter analyze --no-pub
flutter test --no-pub test/reader
git rev-parse HEAD
git status --short
flutter --version
```

Paste the last three outputs into the results log. This is what ties a test run to its source.

### Step 3. Smoke test the timing tools (about 5 minutes)

Window 1 (leave it open):

```powershell
flutter run --release --dart-define=READER_DIAGNOSTICS=true
```

The value must be the word `true`. Window 2:

```powershell
adb logcat -c
cmd /c "adb logcat -v time flutter:I WindowManager:I ActivityManager:I *:S > run-0-smoke.txt"
```

On the tablet, open any small book and let it finish laying out. Stop the log with Ctrl+C, then:

```powershell
Select-String -Path run-0-smoke.txt -Pattern "READER-DX"
```

You should see lines starting `READER-DX`. If you see none, do not start the real runs; tell me.

### Step 4. The real runs

Use the same scenario every time: the same Tamid file, the same settings, starting at the first page.

Before each run:

1. Close the app: `adb shell am force-stop com.example.eink_launcher`.
2. On the tablet: Settings, Apps, the launcher, Storage, **Clear cache**. Do not choose Clear storage or Clear data. This keeps bookmarks, notes and settings but removes saved page layouts, so every run starts the same way.
3. Start the build and the log (same two windows as step 3, with a new file name).

During the run: turn pages as fast as you normally would for up to 3 minutes. If a "not responding" popup appears, write down the time and tap Wait. Stop after the second popup or after 3 minutes, whichever comes first.

| Run | Window 1 command | Log file |
| --- | --- | --- |
| 1. Baseline, no commentary | `flutter run --release --dart-define=READER_DIAGNOSTICS=true` | `run-1-baseline.txt` |
| 2. Experiment, no commentary | `flutter run --release --dart-define=READER_DIAGNOSTICS=true --dart-define=READER_CURRENT_CHAPTER_ONLY=true` | `run-2-chapter-only.txt` |
| 3. Baseline with the commentary set that froze before (optional) | same as run 1 | `run-3-commentary.txt` |

If you can, repeat runs 1 and 2 once more. One run each proves little.

After each run:

```powershell
Select-String -Path run-1-baseline.txt -Pattern "ANR in"
Select-String -Path run-1-baseline.txt -Pattern "READER-DX"
```

Give me the ANR count and the last block of READER-DX lines. The READER-DX lines show, for each phase: how many samples, the median (p50), the slow end (p95) and the worst (max), in microseconds (1,000,000 = 1 second). A "heartbeat gaps" line shows how long the app was unable to run its own timer.

**What the experiment can and cannot show.** It shows whether work on other chapters is a major contributor. It does not isolate one function. If Tamid is a single chapter in the file, the experiment changes nothing, and that result is informative too.

## 8. Reading the results

| What you see | What it suggests | Next |
| --- | --- | --- |
| Run 1 freezes; run 2 freezes much less or not at all | Layout work on the other chapters is a major cause | Limit the background pass to a window around the reading position, then re-measure |
| Both runs freeze about equally | The cause is inside the current chapter | Read the READER-DX numbers below |
| One phase (`paginator.measure`, `session.publish`, `cache.save_encode` or `cache.load_decode`) has a worst sample over about 1 second (a rule of thumb, not a measured limit) | That phase is the main suspect (H1, H3 or H4) | Fix that one first |
| Heartbeat gaps are large but no phase has a large worst sample | The time is going somewhere untimed, probably drawing visible pages (H2) | Add timing to the visible-page path (needs the owner's go-ahead) |
| No READER-DX lines at all | The timing tools were not on, or the log is incomplete | Repeat the smoke test (step 3) |

## 9. Candidate fixes

Do not start these before the measurements above. Make one change at a time so each can be measured separately. Keep the final page geometry identical to today's.

- **Separate progress from visible content.** Progress updates should not rebuild unchanged visible text. Keep immediate updates for target-ready, navigation, errors and completion. Release waiting page turns independently of any throttling. Never set the repaint check permanently to false.
- **Remove redundant publication and indexing.** Do not republish an unchanged page set. Do not recreate every earlier page wrapper for each new page. Keep spine order correct when chapters arrive out of order.
- **Reuse measurements safely.** Start with immutable measurement results and a small, bounded cache for visible layouts. Build keys from every real input (source revision, styled runs, direction, width, typography, display settings, image and page-height limits); an unchanged block ID does not prove unchanged content. Keep text painters on the main thread with an explicit owner that disposes them.[^textpainter] Measure memory as well as speed; an unbounded cache of the whole book is not a fix.
- **Close cooperative-work gaps.** Allow a pause when enough time has passed even if no page completed. Include the no-text branches. A pause cannot interrupt a measurement already running, so more pauses alone will not bound every step.
- **Move cache conversion to a worker.** Move JSON conversion and page reconstruction off the main thread, keeping complete-entry rules, keys, failure recovery and safe file replacement. Text painting itself cannot move to a worker; only plain-data work can.[^isolates] Bound queued writes and retained data. Measure worker start-up and transfer costs first.
- **Larger design (later).** `responsive-reader-reflow-plan.md` remains the bigger track. Before adopting any segment-based pagination: keep source-based positions, keep the old page and data coherent until the new ones replace them, aim for three rendered pages behind and two ahead (not six whole chapters), bound each kind of memory separately, and do not assume restarting layout at an arbitrary offset gives the same page boundaries.

## 10. Tests and results log

### Automated checks

Keep the existing reader tests and extend these where relevant: `epub_paginator_service_test.dart`, `text_reader_session_test.dart`, `text_page_view_test.dart`, `pagination_cache_service_test.dart`, `tanach_session_test.dart`, `tanach_pagination_test.dart`, `annotation_selection_test.dart`, `state_and_epub_recovery_test.dart` (all under `test/reader/`).

Coverage any change must include:

- Equivalent page geometry and ordered source coverage across the synchronous, responsive and cached paths.
- Many small blocks, one large block, split headings, images, mixed right-to-left and left-to-right text, vowel settings, hyphenation.
- Cancellation checked before the next step; a cancelled run never publishes.
- Unrelated progress causes no fresh layout of unchanged visible text; real page, note, selection and settings changes still update.
- Page turns do not depend on throttled progress notifications.
- Cache hit, miss, invalid-entry and failure paths; no partial layout stored as complete.
- Suspend, memory pressure, disposal and rapid settings changes release and cancel work.
- Bookmarks, semantic anchors, search targets, links and notes still map correctly.

Existing session tests use synthetic books and controlled futures. They do not show Bigme responsiveness or bound a single main-thread step.

### Device acceptance

Start with the exact Tamid file and settings that froze, then a larger tractate. Cover cold and warm opens, repeated forward and backward turns including chapter edges, commentary and font-size changes, and suspend and resume. Diagnose in profile mode and confirm in release mode. One run without a freeze proves nothing: record how many runs were made and how many froze. Agree numeric limits for responsiveness and memory before accepting a fix; the 5-second Android timeout is not a usability target.

### Code check (18 Oct 2026)

| Item | Result |
| --- | --- |
| Commit | `a45a5a4c99d39c8367f7aa28cac33070c81703c3`, plus uncommitted edits to the three files listed in Section 6 |
| Flutter / Dart | 3.47.1 / 3.13.1 |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub` | 474 passed, 3 skipped, 2 failed |

The two failures:

- `pdf_runtime_service_test.dart`, "startup stays lazy; concurrent default opens and reopens initialize once": the test has no stand-in for the `eink_launcher/file_intent` platform channel.
- `text_search_service_test.dart`, "keeps Hebrew punctuation and treats queries as literal text": the search code treats Hebrew punctuation (maqaf, paseq, sof pasuq) as removable marks.

Neither test exercises code edited for this investigation. A run on a clean tree has not been done to confirm they already failed before the edits.

### Results log

Fill one row per run. Record outcomes as seen; do not edit old rows.

| Run | Date | Commit and flags | Scenario | ANR count | Worst READER-DX samples | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 Baseline | Not run | | | | | |
| 2 Chapter-only | Not run | | | | | |
| 3 Commentary | Not run | | | | | |

## 11. Where this fits in the docs

- Linked from `docs/README.md` and from `docs/talmud/docs/responsive-reader-reflow-plan.md`. The reflow plan is not yet a demonstrated fix for this problem.
- Record device results as a test pass in [DEVICE_TESTING.md](../../DEVICE_TESTING.md), using its template, and update TAL-015 there. Do not edit old test passes to imply later testing.
- Writing rules for this document: status of TAL-015 lives only in DEVICE_TESTING.md; label every fact (Measured, In code, Reported, Inferred); put new findings in Section 3 and update the suspects table in Section 5, marking weakened ideas rather than deleting them; update the "Last updated" line on every change.
- Documentation or measurement work is not permission to rewrite pagination. Get the owner's review before merging any production change.

## References

Official documentation was consulted on 16 Oct 2026. Bundle-derived findings in Section 4 marked "carried forward" come from the owner's uploaded `reader_bundle.txt` at commit `67e06dcd91c3e9628d95ef04694ef47d45bebb83`.

[^android]: Android Developers, "Diagnose and fix ANRs": `https://developer.android.com/topic/performance/anrs/diagnose-and-fix-anrs`.

[^yield]: Dart API, `Future.delayed` constructor: `https://api.dart.dev/dart-async/Future/Future.delayed.html`.

[^isolates]: Flutter, "Concurrency and isolates": `https://docs.flutter.dev/perf/isolates`.

[^textpainter]: Flutter API, `TextPainter` class: `https://api.flutter.dev/flutter/painting/TextPainter-class.html`.
