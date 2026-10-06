# Device testing

Everything tested on the physical device, in one place: what was checked, what the
measurements were, what is still unchecked, and checklists for next time.

Devices: all tests so far used a **Bigme HiBreak (model B751C)** (Android 14, arm64, 1264 × 1680,
density 300, 256 MiB normal heap class, default Impeller OpenGLES renderer). The Bigme's
refresh-mode name was never recorded.

## Status at a glance

| Area | Status |
| --- | --- |
| PDF page turns, scrolling, zooming, pinch | Confirmed, including no ghosting or white flashes |
| Startup, recovery, app drawer, battery, file chooser | Confirmed |
| EPUB/TXT/Markdown open, search, saved positions | Confirmed |
| Physical page buttons | Confirmed (with the button assignment described below) |
| Tabs, newer screen layouts | **Confirmed by owner (tested several times; skip future passes unless regression)** |
| Selection, notes, underlines | **Partially checked (48 dp handles grabbable 6 Oct; follow-up: flip jumps stationary handle, Hebrew handles pull each other, mixed-dir weird; More button must extend selection across paragraphs)** |
| Hebrew and English dictionaries | **Checked (Passed)** |
| Tanach study books | **Partially checked (6 Oct: chapters/bilingual pass; escaped-markup examples now Gen 7:2, 7:11, 7:23, 8:14, 9:17 + sidecar-folder request; parsha/aliyah still needs rebuilt EPUBs)** |
| Talmud study books | **Partially checked (6 Oct: Berakhot start/headings/links pass; follow-up: commentary order good, Continuous does nothing — remove? vowels question answered in findings)** |
| Renderer preference, preview/sharpen timing, unplugged idle battery drain | Optional measurements, never taken |

## Test history

### 31 Aug 2026: manual pass

The owner worked through the eight-part checklist. Startup, file browsing, app drawer,
status bar, EPUB/TXT/Markdown, saved reading state, interruptions, sustained use, and
safe recovery were reported good. Individual steps, timings, memory, and crash-loop
tests were not recorded. Three PDF problems appeared across every PDF tried:

| ID | Problem | Outcome |
| --- | --- | --- |
| PDF-001 | Rapid next-page taps could freeze Fit Height/Fit Width | Fixed in 1.0.1; confirmed on device |
| PDF-002 | After a pinch in Zoom / Scroll, the page briefly went white, then returned in pieces | Resolved for the conditions tested on 2 Sept |
| PDF-003 | Fast Zoom / Scroll reached unseen pages before pixels appeared | Resolved for the conditions tested on 2 Sept. First-time rendering of a never-seen page remains limited by PDFium speed |

### 2 Sept 2026: computer-driven check (ADB) of version 1.0.2

Used generated test documents: a 32-page vector PDF (29,738 bytes), a 32-page
image-only PDF (23,304,439 bytes), and mixed English/Hebrew TXT, Markdown, and EPUB.
The production app was untouched; fault-injection tests used a separate temporary
package, since removed. The owner then reported **"no ghosting or white flashes"** on
the physical screen. That is direct observation, separate from the screenshot
sampling; it does not settle a preferred renderer or cover every document and scroll
speed.

| Check | Result |
| --- | --- |
| Fit Height rapid taps | 20 forward and 10 back from page 1 ended on page 11; menu stayed responsive |
| Fit Width rapid taps | 12 forward and 6 back moved page 11 to 14 without hanging |
| Zoom / Scroll movement | Both PDFs kept visible content on forward and reverse passes, under both renderers |
| Pinch release | Content stayed visible; six in/out pinch pairs completed |
| Finger-down stopping | Both PDFs stopped while a finger was held |
| Rotation | Portrait to landscape and back kept page 5 / 12% |
| Persistence | Page, mode, and a bookmark survived reopening and a full restart |
| Memory pressure | Showed the recovery screen; **Continue reading** resumed at page 5 |
| TXT / Markdown / EPUB | Opened; mixed English/Hebrew rendered; EPUB contents correct |
| Text search | `Needle20` found exactly 5 matches; selecting one jumped to its page |
| Android chooser | **Open with** showed the system chooser |
| App drawer | Discovery, refresh, filtering, and launching worked; recovery kept drawer access |
| Battery | Simulated unplug removed charging; a restart reattached; reset restored it |
| Permission denied | App stayed usable with **Grant storage access** available |
| Invalid saved home | Warned, fell back to Internal Storage, cleared the bad setting |
| Corrupt reading state | The 29-byte bad file was kept as `library.json.corrupt`; a fresh valid library was created |
| Startup recovery | Two recent failures triggered recovery; **Retry startup** and **Use storage root** worked; the saved home survived |

Analysis was clean and 240 tests passed at the time.

### 18 Sept 2026: page buttons

The side buttons stopped responding inside the app while working elsewhere. Force
stop, a reboot, and a rebuilt APK all failed to help, and reader settings still showed
buttons enabled. The Bigme was not sending any supported key to this app. **Assigning
the side buttons to D-pad Left/Right in the Bigme firmware fixed it at once.** Details
and supported key pairs: [BUTTON_SUPPORT.md](BUTTON_SUPPORT.md).

### 5 Oct test (User pass on HiBreak)

- **Steps 1–4 (Startup, Browser, PDF, Tabs):** Completed successfully with no problems.
- **Step 5.2 (Selection):** Selection worked within a single block, but its handles were quite small and it did not extend across multiple paragraphs. The source follow-up increases each handle's touch target to 48 dp; multi-paragraph selection remains a planned feature because annotations are anchored to one block. The larger handles still need a HiBreak check.
- **Steps 5–6 (Text formatting, dictionaries):** Completed successfully.
- **Study Books:**
  - Clearing the disposable cache requires the next open to import the EPUB again. This is expected cache behavior, not a data-loss condition; pre-parsing and transferring a ready cache remains a possible future workflow.
  - Parshiyot and aliyot within Genesis–Deuteronomy: selecting the fifth portion of Bereishit initially displayed Genesis 4:1 without the fifth-aliyah heading instead of Genesis 4:19. The source follow-up now resolves the anchor after the lazy chapter loads and waits for its page before displaying it. This needs a HiBreak recheck.
  - EPUB TOC links: chapter links worked, but aliyah links initially did not. They use the same lazy-anchor correction and need a HiBreak recheck.
  - UI preference: source code selects either the aliyah contents/headings or the chapter contents/headings, never both. Confirm this on the device with the revised build.
  - Headings formatting: chapter headings remain chapter-only. Parshiyot and aliyot now use the same bilingual split renderer as pesukim (English left, Hebrew right); this needs a HiBreak recheck.
- **File Browser Quirk:** Observed once after deleting all open tabs, but could not be reproduced. The normal folder-opening regression test passes; keep this in the next device pass and record exact steps if it recurs.

### 6 Oct 2026: release pass (owner, HiBreak, release build)

Fresh full rebuild installed by the owner. Timings are stopwatch-measured below.
Code fixes landed after this pass (6 Oct fix pass, host-tested, needs recheck):
Continuous-crash root cause (segment headings parsed as paragraphs), commentary
reading-order sort, parsha-order + heading-mode fixes, vowel-range unification,
bidirectional handles, inventory Finding F. Rebuild EPUBs + sidecars before the
next device pass.

- **Tanach (Genesis):**
  - Cold open after install showed "loading" for over a minute. There is currently
    **no prebuilt sidecar workflow for Tanach**: `tool/build_study_index.dart`
    works for any study EPUB (Tanach included), but no Tanach sidecars were
    built/copied, so the device imports on first open. Follow-up: build Tanach
    sidecars on the laptop and copy each `<book>.study.sqlite` next to its EPUB.
  - Parshiyot/aliyot toggle enables successfully, but **chapter headings remain
    visible in parsha mode** (want parsha/aliyah headings only). Reader cause:
    `_applyHeadingMode` (`lib/reader/services/tanach_layout_service.dart`)
    removes only top-level `body h1` non-parsha headings in parsha mode, so
    chapter headings at other levels survive.
  - **Aliyah landings are wrong, not just one anchor:** Bereishit 5th aliyah
    lands on Genesis 4:1 with no 5th-aliyah heading (want 4:19); the 4th lands
    on Genesis 3 (reported want: 2:20); Noach portions also misbehave.
  - **Builder data bug (confirmed in source):** in `tanach/work/build.py` the
    Miketz entry (Gen 41:1–44:17) is listed *after* Vayechi (Gen 47:28–50:26),
    so the parsha contents order is wrong (Miketz appears after Vayechi).
  - **Escaped markup visible in places:** literal `span`, `class`, `nbsp` text
    in the rendered book. Needs exact book/verse examples captured before a
    builder-vs-reader call is made.
  - Chapters mode, bilingual headings, and chapter contents all pass.
- **Cache reimport (Genesis):** after clearing the disposable cache, cold
  import took **1m 45s** (stopwatch); warm reopen **~2s**.
- **Talmud (Berakhot pilot):**
  - First open **21s**, reopen **1–2s**, begins at **Daf 2a** with the correct
    opening words. (21s suggests the sidecar was stale/missing and the reader
    fell back to on-device import; verify sidecar fingerprints next pass.)
  - Headings English-only, no duplication — pass. Commentary grouped one block
    per source per segment — pass. Contents daf links — pass. Page-jump
    keyboard overlay — pass. Picker lists Rashi/Tosafot/Steinsaltz — pass.
  - **Commentary display order:** the picker itself is now correctly ordered
    (Rashi → Tosafot → rest), but with all sources selected the *reading* order
    puts Steinsaltz before Tosafot. Reader cause: projected notes are appended
    in builder index-link order, not in `orderedStudySources` rank order
    (`tanach_layout_service.dart` projection loop). Follow-up: sort appended
    commentary notes by source rank. Requested standing order: Rashi then
    Tosafot first when reading with multiple commentaries.
  - **Settings wording:** "Talmud language" confirmed. "After each segment" was
    never a control label — it is the helper sentence *"Selected commentary
    appears after each segment…"* above the selectors. No action; checklist
    wording corrected in `docs/talmud/docs/reader-device-findings.md`.
  - **Vowels toggle on Talmud:** showing/hiding vowel points and punctuation
    produced no visible change. Expected if the Talmud text carries no niqqud;
    verify on a pointed Tanach verse before calling it a bug.
  - **Continuous mode crash:** switching Berakhot to Continuous crashed the
    launcher. Open crash bug — needs `adb logcat` around the switch plus a
    regression test once the cause is known.
  - Search "Kayin": 22 matches — consistent with the earlier base-text-only
    check.
- **Selection:** 48 dp handles confirmed easy to grab. Request: bidirectional
  handles (either handle drags either direction, modern-phone style) instead of
  fixed forward/back roles. Notes/underlines persistence and text-layer PDF
  repeat were not re-run (already passed 5 Oct).
- **Ghosting/refresh:** reported "all beautiful" — no ghosting or white
  flashes on this pass.

### 6 Oct 2026: follow-up pass (owner, HiBreak, latest build)

Config: latest build, defaults, fast refresh mode with increased contrast,
side buttons assigned to D-pad Left/Right.

- **Tabs/layouts (Step 1):** not re-run by owner request — already tested
  several times, treated as confirmed. Drop from future passes unless a
  regression appears.
- **Selection (Step 2):** bidirectional handles still flawed:
  - Flipping jumps the stationary handle a few letters or a whole word.
  - In Hebrew, dragging the right handle pulls the left handle (and vice versa)
    before flipping — feels wrong.
  - Mixed Hebrew + English in one paragraph behaves strangely.
  - **More button misunderstood:** owner did NOT ask for "underline the rest of
    the current paragraph". The **More** button should let the selection itself
    extend across multiple paragraphs (then Copy/Dictionary/Note/Underline the
    whole range). Keep the button if useful, but fix what it does. See
    [annotation_plan.md](annotation_plan.md).
- **Tanach (Step 3):** otherwise "all beautiful". Escaped markup now has exact
  examples — literal `span` / `class` / `nbsp` words inside the Hebrew psukim
  at **Gen 7:2, 7:11, 7:23, 8:14, 9:17** (7:2 listed twice by owner, likely two
  spots in the verse; more expected elsewhere). Owner request: let
  `.study.sqlite` sidecars live in a separate folder instead of next to each
  EPUB. See `docs/tanach/docs/tanach-epub.md`.
- **Talmud (Step 4):** otherwise all good. Continuous mode no longer crashes
  but visibly does nothing — owner asks what it is for and suggests removing
  it. Vowels question: owner does not know what "pointed verse" means and asks
  why vowels *and punctuation* do not show, whether Sefaria provides them and
  whether we pull them. See `docs/talmud/docs/reader-device-findings.md`.
- **PDF regression (Step 5):** all good.

## Measurements (version 1.0.2)

**Cold start** (Android's activity display time; five runs each):

| Renderer | Runs (ms) | Median (ms) | Memory after start (KiB) |
| --- | --- | --- | --- |
| Impeller OpenGLES | 985, 1236, 1216, 1236, 1209 | 1216 | 99,531 |
| Legacy | 1097, 1109, 1108, 1176, 1119 | 1109 | 90,447 |

These are not first-interactive-frame timings, and five runs do not crown a winner.

**Memory** (default renderer, in KiB; sequential use, so later rows include leftovers
from earlier ones):

| Stage | Native heap | Graphics | Total |
| --- | ---: | ---: | ---: |
| Fresh start, 60 s idle | 13,424 | 37,583 | 106,937 |
| First vector PDF open | 13,804 | 58,748 | 145,534 |
| Vector scrolling | 16,164 | 131,352 | 226,797 |
| Back in file browser | 16,176 | 132,209 | 227,670 |
| Scanned PDF open | 38,808 | 152,461 | 270,685 |
| Scanned PDF scrolling | 39,868 | 218,907 | 339,465 |
| Background after PDF use | 24,324 | 200,843 | 306,310 |
| After memory-pressure recovery | 24,288 | 48,522 | 151,928 |

Memory pressure released a lot of graphics memory. Nothing here shows a leak, and the
256 MiB heap limit does not cap total memory. It does show why hidden tabs must be
suspended and why image-cache budgets alone do not bound the whole process.
Legacy-renderer scanned-PDF pass (fresh process, so not comparable): 214,545 total,
40,464 native, 115,869 graphics.

First full page of each PDF type was visible by the second sample (about 2 s after
the tap). Screenshot capture slows sampling, so this is coarse.

## Measurements (study books, 6 Oct 2026, owner stopwatch, HiBreak release)

| Book | Cold (after cache clear / first open) | Warm reopen |
| --- | --- | --- |
| Genesis (Tanach, no sidecar — on-device import) | **1m 45s** | **~2s** |
| Berakhot (Talmud pilot; sidecar likely stale/missing — verify) | **21s** | **1–2s** |

Sidecar workflow: `dart run tool/build_study_index.dart <book.epub|books-dir>`
builds a `<book>.study.sqlite` that must sit next to its EPUB; a stale sidecar
falls back to on-device import. Applies to Tanach books too, not just Talmud.

## Limits of the evidence

- Screenshots show app pixels, not e-ink ghosting; the owner's observation fills that
  gap. No external-camera footage exists.
- Scroll sampling is sparse; a very short white interval between samples is possible.
  Later passes also benefit from idle preview warming, so this is not a controlled
  cache test.
- The clock on the device ran about nine seconds behind the PC.
- A temporary unoptimized debug build took 7–11 seconds to start and hit one ANR
  during first startup. That was confined to the temporary package; no ANR appeared in
  production during the test period.

## Housekeeping

Five test files remain on the device in `Download/EinkValidation-20260902` and can be
deleted; copies, generators, and raw timings are kept locally in
`.buildlog/device-check/` (not tracked by git).

## Checklist for the next device pass

**Newer features (not yet checked):**

1. Tabs: open and close mixed formats, switch while one is loading, restart and
   confirm tabs return, check portrait and landscape.
2. Layouts: browser, Apps, settings, dialogs, search, recovery.
3. Text selection: bidirectional handles (either handle drags either way) are built
   6 Oct and need a device recheck; then copy, look up, add a note, and underline in English,
   Hebrew, and Aramaic on the new-handle code. Restart and confirm notes and
   underlines remain; repeat in a text-layer PDF. Multi-paragraph selection
   via **More** is expected to work; direct drag-across-blocks is not yet expected.
4. Study books (details live here; builders/trackers own the fixes):
   - Tanach: needs rebuilt EPUBs (parsha order, aliyah mapping, escaped
     markup) — see `docs/tanach/docs/tanach-epub.md` — plus Tanach sidecars,
     then recheck 5th-aliyah landing (want Gen 4:19 heading), parsha-only
     headings, and Chapters/Parshiyot exclusivity.
   - Talmud: needs commentary display-order fix + Continuous-crash diagnosis —
     see `docs/talmud/docs/reader-device-findings.md` — then recheck
     multi-source order (Rashi → Tosafot), Continuous layout, and sidecar
     fingerprints. Capture `adb logcat` for any crash and exact book/verse
     for any escaped markup.

**PDF regression (after future PDF changes).** Use one text/vector PDF and one scanned
PDF, with the same renderer and refresh mode:

1. Rapid taps in Fit Height and Fit Width, reversing direction; check the centre menu
   and Android Back while work is pending.
2. Pinch in and out repeatedly, including a new pinch before sharpening finishes;
   check content stays visible.
3. Fast scroll at minimum zoom, reverse, then rest a finger to stop; compare the first
   pass with a second over the same pages.
4. Time the first useful preview separately from sharp text; reopen and confirm
   position, mode, and bookmarks.
5. Over sustained use, watch for memory warnings or delays that grow.
6. If white persists: record queue wait and run time, frame timing, and native /
   graphics / total memory. `PdfRenderScheduler.instance` exposes bounded debug
   counters (pending, active, started, finished, cancelled, peak pending) with no
   file names or content. An external-camera video plus app timing can tell missing
   app pixels from panel refresh.

**When reporting a problem,** include the renderer, the Bigme refresh mode, and the
side-button assignment.
