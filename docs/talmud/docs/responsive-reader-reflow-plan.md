# Responsive reader reflow: implementation and validation plan

Status: revised draft, not an ANR fix yet. Base: main at
385238575b2fcc87479eccfcb39ae780b125ba1f.

## Evidence and constraints

The supplied Android bugreport was summarized as a CPU-bound running main
thread, with unsymbolized Dart frames. Pagination is a suspected hot path,
not a confirmed function-level diagnosis. Capture a baseline before changing
layout semantics.

Flutter does not support dart:ui work in spawned isolates:
https://docs.flutter.dev/perf/isolates

TextPainter measurement must remain on the UI isolate. Move pure parsing,
projection, display-offset preparation, and cache JSON encoding/decoding to
workers where useful. Do not call TextPainter from Isolate.run. An async method
alone does not move work off the UI isolate.

## Existing behavior to retain

- applySettings saves _anchoredPosition before changing settings, resolves it
  with _clampPosition, and uses prepareViewport(awaitComplete: false).
- Anchors already include document path, block id, verse fallback, and character
  offset. Extend these; do not replace them with page numbers.
- _layouts joins duplicate requests, and pagination/lifecycle generations reject
  obsolete work. Retain both guarantees.
- Lazy study content is already projected through an isolate. Settings changes
  unload lazy chapters. This is not a new feature of this change.

## Current gaps

- _publishChapter calls _rebuildPages and notifyListeners for every partial.
  _rebuildPages wraps every previously published page across the whole spine.
- _repaginate clears all pages and starts an eager full-spine pass, even when
  applySettings returns as soon as the current position is covered.
- _trimResidentChapters unloads blocks but retains _chapterPages. A chapter-count
  bound on loaded text is not a page-layout memory bound.
- Mandatory yields occur between 16 blocks and at timed publications. One
  exceptionally large block is still one uninterruptible TextPainter measure.
  A time budget cannot preempt that measure.

## Work order

### 1. Baseline and bounded diagnostics

Add a fixed-size ring buffer and dart:developer timeline events for cache
load/decode, projection, each block measurement (duration and character count),
publication/index updates, and settings-to-target-ready latency. Record
pagination generation, spine index, page counts, cancellations and queue size.
Do not log text, excerpts, paths, or commentary contents. Add an event-loop
heartbeat with lifecycle cleanup; export device/build identifiers with metrics.

Keep timing collection bounded and optional so diagnostics do not become the
hot path. Measure a full tractate on the B751C with cache hit and miss, repeated
forward/backward turns, and rapid commentary toggles.

### 2. Separate yielding, publication and notifications

Yield after a small measurement batch and inside the page-slicing loop for a
large block. Check cancellation before the next measure and before publication.
Use elapsed work time, not page count alone, to yield when no page completes.
Keep the synchronous paginateSpine API deterministic for geometry tests.

Publish the first usable selected page immediately. Pace ordinary listener
notifications at roughly 300ms, with a final flush on completion and an immediate
notification on target-ready/navigation/error. Cancel pending notification timers
on supersession, suspension, memory pressure and disposal. Navigation waiters
must be released on internal publication even when listeners are throttled.

Replace full-book flattening with a per-chapter/segment index and cached chapter
page wrappers. Appending pages must not recreate wrappers for previous chapters.
Replacing a chapter invalidates only that chapter and the positional index.
Keep logical order stable for TOC, search, percent jumps and previous/next turns.

A long TextPainter measure still needs investigation if timings show it exceeds
the UI budget. Do not split arbitrary paragraphs without proving line, bidi,
hyphenation and renderer equivalence. This PR must not claim that yielding alone
bounds every synchronous operation.

### 3. Selected passage first, then the page window

The requested 3 behind / 2 ahead window counts *rendered pages*, not chapters.
Keep those values configurable in an internal policy, with one selected page.
That is a six-page target, not permission to retain six whole chapters.

On commentary/typography changes:

1. Snapshot the old rendered page together with its old blocks and settings.
   The old page cannot safely render against newly projected blocks. Keep that
   snapshot visible until replacement, not just a stale LaidOutPage reference.
2. Resolve the existing semantic/text anchor against the new projection.
3. Give the selected passage's layout request highest priority. Swap the page,
   blocks and settings together once the target is covered. Never move the
   saved reading position backwards to a provisional page start.
4. Reflow three pages behind and two ahead, automatically, at lower priority.
5. Leave distant chapters stale/unrequested for both lazy and non-lazy books.
   Do not eagerly paginate the remaining full spine after the target is ready.

Boundary decision to validate before implementing segment reflow: determining
the canonical page containing an arbitrary offset requires the preceding layout
state, either by replaying the prefix or restoring a valid checkpoint for the
same settings. Starting with empty page state at the selected offset can produce
a different local page boundary. It does not always differ: a restart at a valid
canonical boundary can match. Do not assume the two strategies are equivalent. A sparse segment model can use
an anchor-based local boundary, but its backward segment must end at the same
boundary, with no overlap, missing text or duplicated passage. Test that design
before making it the default. Until proven, retain canonical prefix layout and
label selected-offset-first reflow as unfinished rather than claiming it works.

The priority scheduler owns selected, behind, ahead and navigation requests.
An explicit turn/jump outranks prefetch. Deduplicate by generation, chapter and
segment range. Stop obsolete prefetch on settings change or when the reading
window moves; it must not delay a selected-page request. Across chapter edges,
request only the neighboring segments required by the page window. Backward
chapter entry may need the last page; do not assume a first-page partial suffices.

### Why selected-offset restarts need a boundary rule

These citations are repository-root paths, not relative Markdown links. They
refer to commit 385238575b2fcc87479eccfcb39ae780b125ba1f; line numbers may change
in later commits. This document works unchanged at the repository root or in
any docs subfolder.

**Verified by reading the current code:**

- `lib/reader/services/epub_paginator_service.dart:91-93` initializes every run
  with an empty page list, empty slices, and `usedHeight = 0`.
- The same file, lines 124-139, walks blocks from index zero and measures them.
  There is currently no start-offset or resume-checkpoint input to `_steps`.
- Lines 141-157 pack blocks without line slices using the height left on the
  current page. Lines 161-175 do the same for text lines. Thus the next page
  break depends on accumulated preceding height, not only the current offset.
- Lines 100-121 take page start/end from the first/last slices and reset height
  to zero only when finishing a page. Lines 182-190 also make widow/orphan
  choices based on whether a page already has slices. A partial run must carry
  more state than a block index if it wants identical canonical boundaries.
- `lib/reader/controllers/text_reader_session.dart:1174-1194` copies published
  page ranges into spine order. It does not trim overlaps or reconcile segment
  boundaries. Lines 1207-1217 select the first matching start/end range; they
  do not repair overlapping ranges either.
- `test/reader/epub_paginator_service_test.dart:88-111` already asserts contiguous
  character offsets between adjacent pages for a single paragraph. This is a
  useful existing invariant, not a test of selected-offset segment stitching.

**Worked counterexample, calculated from the packing rule:**

Assume a 100-pixel page and five indivisible measured blocks A, B, C, D, E, each
40 pixels tall including spacing. These are illustrative measured heights,
not measurements of a real tractate or Flutter font.

| Run | First page | Second page | Third page |
| --- | --- | --- | --- |
| Full chapter from A | A + B (80px) | C + D (80px) | E (40px) |
| Fresh run starting at B | B + C (80px) | D + E (80px) | none |

The arithmetic follows lines 141-157: the third 40-pixel block cannot fit into
20 pixels, so the page ends. Restarting at B discards the 40 pixels already
occupied by A in the canonical run. B now fits with C. An offset at B is inside
the canonical A+B page but is the start of the restarted B+C page.

A small independent script implementing that branch of the packing rule was
run and checked these exact two outputs. This is a verified arithmetic
counterexample to *unconditional boundary equivalence*, not an executed Flutter
pagination regression test. It does not prove that this device's selected page
will always diverge.

**Conditional stitching risk, not an observed bug:**

If a future implementation retains canonical A+B as its backward page and then
appends restarted B+C, B is displayed twice. If it drops the entire A+B page to
avoid overlap without regenerating its A-only prefix, A is missing from that
local page sequence. This example establishes why a naive splice can lose or
duplicate coverage. The current code does not implement this splice, and no
such defect has been reproduced in the current app.

A correct design can split/reflow the prefix so it ends exactly at B, use a valid
same-settings checkpoint, or adopt canonical prefix pagination. With text, it
must additionally preserve line boundaries, source offsets, bidi context and
widow/orphan behavior. Starting with a substring inside a line can change line
wrapping too, so remapping block indices alone is not enough.

**Required executable proof before changing the boundary model:** add a Flutter
fixture that compares full-chapter boundaries with a restarted segment, then
stitches the prefix and suffix and checks ordered, non-overlapping source
coverage, no lost blocks/characters, and back/forward round trips. Include an
old selected-page anchor that becomes interior to a new canonical page after a
commentary toggle. Execute it alongside existing pagination/anchor tests.
Until then, boundary divergence is code-grounded and demonstrated with a
calculated model; actual selected-offset reflow and safe stitching remain
unimplemented and unverified.

### 4. Eviction and cache semantics

Track page geometry separately from loaded source text. Evict geometry outside
the active page window after necessary navigation/in-flight pins are released;
remove matching _chapterPages, completion flags and index entries together.
Keep disk caches available for reload. Eviction must not mark an incomplete
segment as a complete chapter or save it under a complete-chapter cache key.
Use bounded overscan/in-flight allowance and a byte/page cap; a loaded chapter
cap alone does not bound a huge tractate chapter's geometry.

Retain source blocks referenced by the old visible snapshot until the swap.
Do not unload a chapter used by the renderer, a navigation request, or layout.
Cancel generation-owned waiters on eviction/suspension instead of leaving them
pending. Distinguish 'finished active window' from 'whole book paginated' in
isPaginating and page/percent jump UI semantics.

## Code paths

- lib/reader/controllers/text_reader_session.dart: applySettings, _repaginate,
  _runPagination, _awaitPages, _runChapterLayout, _publishChapter, _rebuildPages,
  _trimResidentChapters, _anchoredPosition, _clampPosition.
- lib/reader/controllers/text_chapter_layout.dart: shared waiters, cancellation
  and completion semantics for segments.
- lib/reader/services/epub_paginator_service.dart: _steps,
  paginateSpineResponsive, TextBlockLayout.measure, display/source offsets.
- lib/reader/services/pagination_cache_service.dart: off-thread serialization,
  complete-chapter versus partial-segment cache keys and eviction.
- lib/reader/widgets/text_page_view.dart: coherent old-page snapshot and atomic
  replacement with matching blocks/settings, selection/annotation behavior.

## Tests and merge gates

Retain and extend existing test/reader/text_reader_session_test.dart,
tanach_session_test.dart, tanach_pagination_test.dart and
epub_paginator_service_test.dart.

- Geometry equality for synchronous versus yielded pagination, including large
  single paragraphs, Hebrew/English bidi, hyphenation, images and split headings.
- Cancellation before a measure and inside slicing; no publication from an old
  settings generation, after suspension/disposal, or after memory pressure.
- First target-ready notification immediate, ordinary progress throttled, final
  update flushed, navigation waiters independent of notification throttling.
- Rapid commentary enable/disable preserves document/block/verse/char anchors;
  removal of a selected commentary block uses the existing verse fallback.
- The old page uses old settings/blocks while reflow waits. Replacement is
  atomic, without a blank or unrelated page, and annotations remain mapped.
- Three backward and two forward pages populate automatically, including chapter
  edges. No gaps/duplicates when prefix and anchor-based segments meet.
- Evicted geometry reloads on back-turn, caches stay generation/settings-safe,
  resident geometry stays bounded while traversing a full tractate.
- TOC, search, bookmarks, page/percent jumps remain correct with sparse layouts.

Record before/after p50/p95/max measurement and publication time, longest
heartbeat gap, settings-to-target-ready latency, back-turn wait, resident page
count, memory and ANR outcome on the same full tractate/device/settings. Do not
fill in estimated measurements. Require Flutter analyze, regression tests and
B751C evidence before marking this fix ready to merge.

## Current validation status

Repository and plan were inspected. No Flutter or Dart SDK was available in the
execution environment at the time of this revision. No tests, Android build,
rendered reader UI or B751C benchmark has run. No implementation or ANR fix is
claimed by this plan. Publish as draft until those gates are met; never merge
without the owner's further instruction.

## Related ANR investigation

See [Text reader ANR investigation](reader-ANR-investigation.md) for the current
code findings and targeted performance-validation sequence. The reflow design
above is not yet a demonstrated fix for the reported input-dispatch ANR.
