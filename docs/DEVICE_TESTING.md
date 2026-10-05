# Device testing

Everything tested on the physical device, in one place: what was checked, what the
measurements were, what is still unchecked, and checklists for next time.

Devices: all tests so far used a **Bigme HiBreak** (Android 14, arm64, 1264 × 1680,
density 300, 256 MiB normal heap class, default Impeller OpenGLES renderer). The
original target, the **Bigme B751C**, has not been physically verified. The Bigme's
refresh-mode name was never recorded.

## Status at a glance

| Area | Status |
| --- | --- |
| PDF page turns, scrolling, zooming, pinch | Confirmed, including no ghosting or white flashes |
| Startup, recovery, app drawer, battery, file chooser | Confirmed |
| EPUB/TXT/Markdown open, search, saved positions | Confirmed |
| Physical page buttons | Confirmed (with the button assignment described below) |
| Tabs, newer screen layouts | **No recorded device check** |
| Selection, notes, underlines | **No recorded device check** |
| Hebrew and English dictionaries | **No recorded device check** |
| Tanach and Talmud study books | **No recorded device check** (see the Talmud and Tanach docs) |
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
3. Text selection: copy, dictionary (English, Hebrew, Aramaic), note, underline;
   restart and confirm underlines and notes remain; repeat in a text-layer PDF.
4. Study books: see `docs/tanach/docs/tanach-epub.md` and
   `docs/talmud/docs/reader-device-findings.md`.

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
