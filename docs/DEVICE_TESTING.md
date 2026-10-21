# Device testing

The one place for everything checked on the physical device: what was tested, what
broke, whether it is fixed, and what to check next.

Last updated: 21 Oct 2026. This file was restructured into an issue tracker on 7 Oct
2026. Statuses and the status log were reconstructed from the older notes, so some
change dates are the date a pass reported them, not the exact day of the fix.

Device: all tests so far used a **Bigme HiBreak (model B751C)** (Android 14, arm64,
1264 × 1680, density 300, 256 MiB normal heap class, default Impeller OpenGLES
renderer). The Bigme's refresh-mode name was never recorded.

## Start here

1. **Is a problem fixed?** Look in the [Issue tracker](#issue-tracker). It is the only
   place in the whole docs folder that says so.
2. **What happened on a given day?** See [Test passes](#test-passes-newest-first). They
   are a diary of what was seen. They never say what is fixed *now*.
3. **Adding or changing something?** Read
   [Rules for writing in this document](#rules-for-writing-in-this-document) first.

## Status words

Every issue has exactly one of these. Nothing else is allowed.

| Status | Meaning |
| --- | --- |
| **OPEN** | Reported and not fixed. Also used when a fix was tried and the problem was still there afterwards. |
| **FIX BUILT** | A fix is written and passes the computer tests, but nobody has checked it on the HiBreak. **Not fixed yet.** |
| **FIXED** | The owner checked it on the HiBreak and the problem is gone. Always shows the date. |
| **DECIDED** | The owner decided what to do. The work is not done yet. |
| **NEEDS INFO** | Nothing can be done until something is found out first (an example, a log, an investigation). |
| **WATCHING** | Seen once and could not be repeated. No work until it happens again. |
| **CLOSED** | No action needed: expected behavior, or kept on purpose. The reason is always written. |

## Issue tracker

### 1. Not fixed yet

| ID | Problem | Status | Next step | Updated |
| --- | --- | --- | --- | --- |
| SEL-002 | Selection cannot be stretched over several paragraphs. The **More** button does not do what you asked for. | **FIX BUILT** | Rebuilt 11 Oct: **More** stretches the selection itself across paragraphs (repeatable), then Copy, Dictionary, Add Note and Underline apply to the whole range. Needs device check. Dragging the handles across paragraphs is a separate, later feature. | 11 Oct 2026 |
| SEL-003 | Selection handles: flipping one handle past the other makes the other handle jump a few letters or a whole word. | **OPEN** | A fix was built 6 Oct and did not cure it. Needs another attempt. | 6 Oct 2026 |
| SEL-004 | Selection handles in Hebrew: dragging the right handle pulls the left handle along (and the reverse) before they flip. | **OPEN** | Needs a fix. | 6 Oct 2026 |
| SEL-005 | Selection handles in a paragraph that mixes Hebrew and English behave strangely. | **OPEN** | Write down one exact paragraph (book and place) where it happens, then fix. | 6 Oct 2026 |
| TAN-004 | Literal words `span`, `class` and `nbsp` appear inside Hebrew verses. Exact places: Genesis 7:2 (twice), 7:11, 7:23, 8:14, 9:17. `span` search returns 202 matches in Genesis; all books affected. | **FIX BUILT** | Cause found 11 Oct: `hebrew()` in `tanach/work/build.py` escaped raw source markup; now strips to clean text (section markers kept), host-verified over 23,206 verses. Rebuild EPUBs + sidecars into `study/`, then recheck verses clean and `span` search 0. | 11 Oct 2026 |
| TAN-005 | First open of Genesis takes 1 min 45 s (later opens take about 2 s) because no Tanach sidecar files have been built. | **FIX BUILT** | Reader checks `<books-dir>/study/<book>.study.sqlite` first with next-to-EPUB fallback; build with `dart run tool/build_study_index.dart <books-dir> --out <books-dir>/study` after the rebuilt books exist and copy them to the device. Expected result: first open close to the 2 s reopen time. | 11 Oct 2026 |
| TAN-006 | Request: keep the sidecar files in their own folder instead of next to each book. | **FIX BUILT** | Built 11 Oct: `study/` subfolder checked first with next-to-EPUB fallback. See `docs/tanach/docs/tanach-epub.md`. Needs rebuilt books + device check. | 11 Oct 2026 |
| TAL-006 | An unexplained log line: "Another exception was thrown: DiagnosticsProperty<void>". | **NEEDS INFO** | Capture the full error text just above that line. See [the Talmud findings](talmud/docs/reader-device-findings.md). Do not guess a fix. | 6 Oct 2026 |
| TAL-012 | The Talmud **Paragraphs / Continuous** setting changes nothing you can see. | **DECIDED** | Decision (Levi, 6 Oct 2026): remove the setting. | 6 Oct 2026 |
| TAL-013 | Vowel marks and punctuation do not show in the Talmud text, although the Sefaria website shows them on all of Talmud. | **FIX BUILT** | Cause found: pipeline picked Sefaria's unpointed Aramaic edition. Fixed 11 Oct: inventory prefers Vocalized Aramaic, download-plan swapped for all 37, Berakhot cache verified (227k marks, 0 cantillation). Rebuild EPUBs + sidecars, then recheck the toggle on Berakhot 2a. Decision (Levi, 6 Oct 2026): there is no vowel setting for Tanach and there should not be one. | 11 Oct 2026 |
| TAL-014 | First open of Berakhot took 21 s. It should be nearly instant if the sidecar file is working. | **NEEDS INFO** | Check that the Berakhot sidecar is fresh (matches the current book), then time the first open again. | 6 Oct 2026 |
| BRW-001 | File browser acted oddly once after closing all open tabs. | **WATCHING** | Could not be repeated. If it happens again, write down the exact steps. Keep in the next device pass. | 5 Oct 2026 |
| TAL-015 | The app shows "app not responding" when opening or reading Talmud books, and opening the same book again can freeze it again. The owner reported on 18 Oct that every Talmud EPUB does this; on 21 Oct Berakhot and Bava Kama did not freeze and Tamid did. | **OPEN** | Timing runs on Tamid show one paragraph of about 287,000 characters taking about 57 seconds to lay out. Berakhot has no block that large (its largest is about 19,000 characters). Next: find out why Tamid's text has such a paragraph, then limit how big a block can be. See [the ANR investigation](talmud/docs/reader-ANR-investigation.md). | 21 Oct 2026 |

### 2. Fix built, waiting for a device check

None of these are fixed until the owner confirms them on the HiBreak. Rebuild the
books first (see the [checklist](#checklist-for-the-next-device-pass)).

| ID | Problem | Status | What to check | Updated |
| --- | --- | --- | --- | --- |
| TAN-002 | In Parshiyot mode, chapter headings were still shown (only parsha and aliyah headings should show). | **FIX BUILT** | Parshiyot mode shows only parsha and aliyah headings, each as side-by-side English and Hebrew like the verses. Chapters mode and Parshiyot mode are never shown together. | 6 Oct 2026 |
| TAN-003 | Parshiyot were in the wrong order in the Contents (Miketz appeared after Vayechi). Leviticus was also out of order. | **FIX BUILT** | Rebuild the Tanach books, then check the Contents order of the weekly portions. | 6 Oct 2026 |

### 3. Fixed, closed, or confirmed

| ID | Problem | Status | How it was confirmed |
| --- | --- | --- | --- |
| PDF-001 | Rapid next-page taps froze Fit Height and Fit Width. | **FIXED** 2 Sept 2026 | Fixed in 1.0.1, confirmed on the device; 20 rapid taps and the menu stayed responsive in the 2 Sept check. |
| PDF-002 | After a pinch in Zoom / Scroll the page went white, then came back in pieces. | **FIXED** 2 Sept 2026 | For the conditions tested on 2 Sept. Owner saw no ghosting or white flashes on 2 Sept and 6 Oct. |
| PDF-003 | Fast Zoom / Scroll reached pages before their pixels appeared. | **FIXED** 2 Sept 2026 | For the conditions tested on 2 Sept. A never-seen page still renders at PDFium's speed, which is a known limit, not a bug. |
| BTN-001 | Side buttons stopped working inside the app. | **FIXED** 18 Sept 2026 | Assigning the side buttons to D-pad Left/Right in the Bigme firmware fixed it at once. See [BUTTON_SUPPORT.md](BUTTON_SUPPORT.md). |
| SEL-001 | Selection handles were too small to grab. | **FIXED** 6 Oct 2026 | Handles are now 48 dp; owner says they are easy to grab. |
| TAL-001 | Steinsaltz notes are included in the Talmud books. | **CLOSED** | Kept on purpose (Levi's choice). |
| TAL-002 | Reference headings were bilingual; English-only was wanted. | **FIXED** 6 Oct 2026 | Headings English-only, no duplication. |
| TAL-003 | Doubled commentary titles ("Rashi on Berakhot on Rashi on…"). | **FIXED** 6 Oct 2026 | Titles read like `Rashi on Berakhot 2a:1`. |
| TAL-004 | Page numbers shifted when the keyboard opened (Go to page). | **FIXED** 6 Oct 2026 | Keyboard overlay no longer changes page numbers. |
| TAL-005 | Notes had one title each instead of one per commented section. | **FIXED** 6 Oct 2026 | Commentary grouped one block per source per segment. |
| TAL-007 | Contents-page links ("Daf 3a" and so on) did nothing. | **FIXED** 6 Oct 2026 | Daf links jump to the right place. |
| TAL-008 | Settings said "Verse language". | **FIXED** 6 Oct 2026 | Now reads "Talmud language". The line "Selected commentary appears after each segment…" is a helper sentence, not a control label. |
| TAL-009 | Berakhot began at Daf 3a (2a and 2b were missing). | **FIXED** 6 Oct 2026 | Opens at Daf 2a with the correct opening words. |
| TAL-010 | With all commentaries on, Steinsaltz appeared before Tosafot in the text. | **FIXED** 6 Oct 2026 | Follow-up pass: order is good (Rashi, then Tosafot, then the rest). |
| TAL-011 | Switching Berakhot to Continuous crashed the launcher. | **FIXED** 6 Oct 2026 | Follow-up pass: no crash. The setting itself is being removed (TAL-012). |
| TAN-007 | After clearing the cache, the next open imports the book again. | **CLOSED** | Expected behavior of the disposable cache, not data loss. Handing over a ready-made cache is a possible future workflow (see TAN-005). |
| TAN-001 | Picking an aliyah (from the picker or the Contents page) landed in the wrong place. Examples: Bereishit 5th aliyah opened Genesis 4:1 with no 5th-aliyah heading (should be 4:19); the 4th opened Genesis 3 (should be 2:20); Noach was also wrong. | **FIXED** 7 Oct 2026 | Owner confirmed on the HiBreak. The 5 Oct fix had failed on the 6 Oct pass; what changed in between was not recorded. |

## Status log

One line per change, newest first. Older dates are when a pass reported the change.

- **21 Oct 2026 (later):** TAL-015 stays OPEN. Berakhot (largest block about 19,000
  characters, no freezes) and Bava Kama did not freeze, and Tamid froze again. The earlier
  report that every Talmud EPUB freezes was not reproduced. The Tamid freeze comes from one
  huge paragraph; why that paragraph exists is not yet known.

- **21 Oct 2026:** TAL-015 stays OPEN. A second timing run on Tamid found the piece of text
  that freezes the app: one paragraph of about 287,000 characters, which took about 57
  seconds to lay out. Most of that time was spent in the reader's own line-by-line step,
  not in the text engine. Not yet known: whether the other tractates have blocks like it.

- **18 Oct 2026:** TAL-015 stays OPEN. The owner confirmed every Talmud EPUB freezes; only
  Tamid has been measured, and the other tractates are still to be tested to see whether
  the cause is the same. First timing run (Tamid, all commentaries on): one piece of text
  took 55 seconds to lay out, while rebuilding the page list and saving layouts were fast.
  It is not yet known how big that piece is or whether it is a one-off.

- **16 Oct 2026:** TAL-015 reported, OPEN ("app not responding" opening or
  reading Talmud books including Tamid; reopening the same book can freeze
  again). ANR investigation document added with bounded diagnostics and small
  safe fixes; computer tests run, no device baseline yet.
- **16 Oct 2026 (device runs):** eighteen ANR traces in `freeze-B.zip` /
  `freeze-B2.zip` (16:17–17:07, several app processes). Every trace shows the
  main thread Running in app code with no locks held, GC idle, and
  memory-copy/allocation at the top of the stack; the 16:21:37 window burned
  100% user CPU with 28,724 minor faults, and anonymous memory grew about
  18 MB per freeze episode. Retry with 11 commentaries opened in 3m53s with
  ANR during load, then ANRs roughly every 90 s for 12+ minutes with brief
  recoveries between — repeated ~10 s synchronous chunks, not one endless
  stall. Commentary projection itself runs on a worker (`Isolate.run`), so
  the burn is downstream of it (measure/publish/cache on the UI isolate).
  Run A log captured; Run B log file was never saved and holds no Run B ANR,
  so Run B must be redone with logging. Still no READER-DX lines: either the
  `=true` rebuild never reached the device, or the pass never completes to
  dump — so dumps are now also periodic (30 s), on suspend, and on dispose.
- **15 Oct 2026 (merge):** kept the 7 Oct tracker structure, ported 8–11 Oct remote
  facts: TAN-004 OPEN → FIX BUILT (markup cause + 23,206-verse check). TAN-005,
  TAN-006 OPEN → FIX BUILT (`study/` subfolder). TAL-013 NEEDS INFO → FIX BUILT
  (Vocalized Aramaic, 227k marks). SEL-002 OPEN → FIX BUILT (More-chain rebuild).
- **7 Oct 2026:** TAN-001 OPEN → FIXED (owner confirmed on the HiBreak).
- **6 Oct 2026, follow-up pass:** TAL-010 FIX BUILT → FIXED. TAL-011 FIX BUILT →
  FIXED. TAL-012 reported, then DECIDED (remove the setting). TAL-013 reported as a
  question, NEEDS INFO. TAN-004 NEEDS INFO → OPEN (exact examples captured).
  TAN-006 reported. SEL-002 re-described (owner correction on **More**). SEL-003,
  SEL-004 and SEL-005 reported, OPEN.
- **6 Oct 2026, release pass:** SEL-001 FIXED. TAL-002, 003, 004, 005, 007, 008 and
  009 FIXED. TAN-001 still wrong after the 5 Oct fix, OPEN. TAN-002 and TAN-003
  reported, then FIX BUILT after the pass. TAN-004 and TAN-005 reported. TAL-010,
  011, 013 and 014 reported; TAL-010 and TAL-011 FIX BUILT after the pass.
- **5 Oct 2026, owner pass:** SEL-001 and SEL-002 reported (SEL-001 FIX BUILT).
  TAN-001 reported (a fix was built that did not work, see 6 Oct). TAN-007 CLOSED
  as expected behavior. BRW-001 reported, WATCHING.
- **18 Sept 2026:** BTN-001 reported and FIXED (firmware button assignment).
- **2 Sept 2026:** PDF-001, PDF-002 and PDF-003 FIXED for the conditions tested.
- **31 Aug 2026:** PDF-001, PDF-002 and PDF-003 reported.

## Feature areas at a glance

This table says how much of each area has been checked. It does not say whether a
specific problem is fixed; only the tracker does.

| Area | Checked? | Issues |
| --- | --- | --- |
| PDF page turns, scrolling, zooming, pinch | Checked OK (2 Sept; 6 Oct regression "all good"; no ghosting or white flashes) | PDF-001 to 003 |
| Startup, recovery, app drawer, battery, file chooser | Checked OK (2 Sept) | none |
| EPUB / TXT / Markdown open, search, saved positions | Checked OK | none |
| Physical page buttons | Checked OK, with the button assignment in BTN-001 | BTN-001 |
| Tabs and newer screen layouts | Checked OK by owner, several times. Skip in future passes unless something regresses. | none |
| Hebrew and English dictionaries | Checked OK (5 Oct) | none |
| Selection, notes, underlines | Partly checked. Handle size OK. Notes, underlines and text-layer PDF passed 5 Oct and were not re-run. | SEL-001 to 005 |
| Tanach study books | Partly checked. Chapters mode, bilingual headings and chapter contents pass. | TAN-001 to 007 |
| Talmud study books | Partly checked. Berakhot pilot starts, headings, links and commentary grouping pass. Tamid freezes when opened or read; Berakhot and Bava Kama did not (TAL-015). | TAL-001 to 015 |
| Renderer preference, preview and sharpen timing, unplugged idle battery drain | Not measured (optional) | none |

## Rules for writing in this document

These keep the file clean. Anyone editing it, human or AI, follows them.

1. **One problem, one ID, one tracker row.** An ID is an area prefix plus three
   digits: `PDF`, `SEL` (selection), `TAN` (Tanach), `TAL` (Talmud), `BTN` (buttons),
   `BRW` (file browser). New area: add a prefix here first. IDs are never reused or
   renumbered.
2. **Use only the seven status words**, in bold capitals, exactly as spelled in the
   table above.
3. **Only the owner moves something to FIXED**, and only after checking it on the
   HiBreak. Passing `flutter test` or `flutter analyze` is at most **FIX BUILT**.
   Always write the date next to **FIXED**.
4. **When a status changes, do both:** edit the tracker row (status, next step,
   date) and move it to the right table; then add one line to the Status log. Never
   edit an old test pass to say something was fixed later.
5. **Every test pass uses the same template** (below), newest pass first.
6. **Other documents link to IDs and never copy status words.** Write "see TAN-003 in
   DEVICE_TESTING.md", not "fixed" or "still broken". Copies go stale; this is the
   most common cause of confusion.
7. **Owner decisions** are written as `Decision (Levi, 6 Oct 2026): …` in the row's
   Next step cell, and the status becomes **DECIDED** until the work is built.
8. **Write for a non-coder.** One plain sentence per cell where possible. Give exact
   examples (book and verse, not "some verses"). File and function names belong in
   the plan and builder documents, not in the tracker.
9. **Dates look like `6 Oct 2026`.** Timings say who measured them ("owner
   stopwatch"). Numbers always have units.
10. **Never delete a row.** Fixed and closed rows stay in table 3 as the record.
11. **Update the "Last updated" line** whenever you change anything here.

### Template for a test pass

```
### 6 Oct 2026: <short title> (who tested, device, build)

Build and settings: <build, refresh mode, button assignment, anything unusual>

| Step | Result | Issues |
| --- | --- | --- |
| 1 Tabs | Passed | none |
| 2 Selection | Handles flip badly | SEL-003 |

New issues: <IDs added to the tracker today, or "none">
Notes: <anything else seen, in plain words>
```

Results say what was observed that day (Passed, Problem seen, Skipped). They list
IDs but never say whether an issue is fixed now.

## Test passes (newest first)

### 6 Oct 2026: follow-up pass (owner, HiBreak, latest build)

Build and settings: latest build, default settings, fast refresh mode with increased
contrast, side buttons assigned to D-pad Left/Right.

| Step | Result | Issues |
| --- | --- | --- |
| 1 Tabs and layouts | Skipped at the owner's request (already tested several times) | none |
| 2 Selection | Handles flip badly; Hebrew handles pull each other; mixed Hebrew and English strange; **More** does not do what was asked | SEL-002, SEL-003, SEL-004, SEL-005 |
| 3 Tanach | Otherwise "all beautiful". Exact escaped-markup examples captured. Owner asked for sidecars in a separate folder | TAN-004, TAN-006 |
| 4 Talmud | Otherwise all good. Commentary order good. Continuous no longer crashes but visibly does nothing; owner decided to remove it. Owner asked why vowels and punctuation do not show | TAL-010, TAL-011, TAL-012, TAL-013 |
| 5 PDF regression | All good | none |

New issues: SEL-003, SEL-004, SEL-005, TAL-012, TAL-013 (as a question), TAN-006.

Notes: the owner asked what "a pointed verse" means. "Pointed" just means the Hebrew
carries vowel marks. The owner also asked whether Sefaria supplies vowels and
punctuation for Talmud and whether the pipeline pulls them. That is still unanswered
(TAL-013).

### 6 Oct 2026: release pass (owner, HiBreak, release build)

Build and settings: fresh full rebuild installed by the owner; timings are owner
stopwatch.

| Step | Result | Issues |
| --- | --- | --- |
| Tanach (Genesis), first open after install | "Loading" for over a minute; no sidecars exist | TAN-005 |
| Tanach, Parshiyot/aliyot toggle | Turns on, but chapter headings stay visible | TAN-002 |
| Tanach, aliyah landings | Wrong in several places (not just one) | TAN-001 |
| Tanach, Contents order of portions | Miketz appears after Vayechi | TAN-003 |
| Tanach, escaped markup | Literal `span`, `class`, `nbsp` seen; exact examples not yet captured | TAN-004 |
| Tanach, Chapters mode, bilingual headings, chapter contents | Passed | none |
| Cache clear, then open Genesis | 1 min 45 s cold; about 2 s warm reopen | TAN-005 |
| Talmud (Berakhot pilot), first open | 21 s cold; 1–2 s reopen. Starts at Daf 2a with the correct opening words | TAL-014 |
| Talmud headings, commentary grouping, Contents daf links, page-jump keyboard, commentary picker (Rashi, Tosafot, Steinsaltz) | Passed | none |
| Talmud, commentary reading order | Steinsaltz came before Tosafot | TAL-010 |
| Talmud, Continuous | Crashed the launcher | TAL-011 |
| Talmud, vowels/punctuation toggle | No visible change | TAL-013 |
| Search "Kayin" | 22 matches, consistent with the earlier base-text-only check | none |
| Selection handles | 48 dp handles easy to grab. Owner asked for bidirectional handles (either handle drags either way). Notes/underline persistence and text-layer PDF were not re-run (they passed 5 Oct) | SEL-001 |
| Ghosting and refresh | "All beautiful": no ghosting or white flashes | none |

New issues: TAN-001 to TAN-005 (TAN-001 first reported 5 Oct), TAL-010, TAL-011,
TAL-013, TAL-014.

Notes: fixes written after this pass, none yet checked on the device unless the
tracker says FIXED: TAL-010, TAL-011, TAN-002, TAN-003. Rebuild the books and
sidecars before the next pass.

### 5 Oct 2026: owner pass (HiBreak)

| Step | Result | Issues |
| --- | --- | --- |
| 1–4 Startup, Browser, PDF, Tabs | Passed, no problems | none |
| 5.2 Selection | Worked inside one block; handles quite small; could not extend across paragraphs | SEL-001, SEL-002 |
| 5–6 Text formatting, dictionaries | Passed | none |
| Study books, aliyah picks and Contents aliyah links | Chapter links worked; aliyah links and picks landed wrongly (Bereishit 5th aliyah opened Genesis 4:1, not 4:19) | TAN-001 |
| Study books, headings | Parsha and aliyah headings needed the same side-by-side English/Hebrew style as verses; chapter-only headings stayed chapter-only | TAN-002 |
| Study books, clearing the cache | The next open imports the book again | TAN-007 |
| File browser | Odd behavior once after deleting all open tabs; not repeatable | BRW-001 |

New issues: SEL-001, SEL-002, TAN-001, TAN-002, TAN-007, BRW-001.

### 18 Sept 2026: page buttons

The side buttons stopped responding inside the app while working elsewhere. Force
stop, a reboot, and a rebuilt APK all failed to help, and reader settings still
showed buttons enabled. The Bigme was not sending any supported key to this app.
Assigning the side buttons to D-pad Left/Right in the Bigme firmware fixed it at once.
Issue: BTN-001. Supported key pairs: [BUTTON_SUPPORT.md](BUTTON_SUPPORT.md).

### 2 Sept 2026: computer-driven check (ADB) of version 1.0.2

Used generated test documents: a 32-page vector PDF (29,738 bytes), a 32-page
image-only PDF (23,304,439 bytes), and mixed English/Hebrew TXT, Markdown, and EPUB.
The production app was untouched; fault-injection tests used a separate temporary
package, since removed. The owner then reported **"no ghosting or white flashes"** on
the physical screen. That is direct observation, separate from the screenshot
sampling; it does not settle a preferred renderer or cover every document and scroll
speed. Issues checked: PDF-001, PDF-002, PDF-003.

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

### 31 Aug 2026: manual pass (owner)

The owner worked through the eight-part checklist. Startup, file browsing, app drawer,
status bar, EPUB/TXT/Markdown, saved reading state, interruptions, sustained use, and
safe recovery were reported good. Individual steps, timings, memory, and crash-loop
tests were not recorded. Three PDF problems appeared across every PDF tried:
PDF-001, PDF-002, PDF-003.

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

| Book | Cold (after cache clear / first open) | Warm reopen | Related issue |
| --- | --- | --- | --- |
| Genesis (Tanach, no sidecar, so the device imports it) | **1 min 45 s** | **about 2 s** | TAN-005 |
| Berakhot (Talmud pilot; sidecar likely stale or missing, to be verified) | **21 s** | **1–2 s** | TAL-014 |

Sidecar workflow: `dart run tool/build_study_index.dart <book.epub|books-dir>` builds a
`<book>.study.sqlite` that must sit next to its EPUB. A stale sidecar makes the reader
fall back to importing on the device. This applies to Tanach books too, not just
Talmud.

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

Skip tabs and layouts unless something regresses (owner decision, 6 Oct 2026).

**Before the pass, on the laptop:**

1. Rebuild the Tanach books (needed for TAN-002 and TAN-003), then build the Tanach
   sidecars (TAN-005) and copy them to the device.
2. Rebuild the Talmud books and sidecars, and check the sidecars are fresh (TAL-014).
   Steps: [the Talmud findings](talmud/docs/reader-device-findings.md).
3. Build and install the latest app.

**On the device, only the items whose fix exists:**

| Check | Issue | Only worth doing when |
| --- | --- | --- |
| Parshiyot mode shows only parsha and aliyah headings, side by side English/Hebrew; Chapters and Parshiyot never both | TAN-002 | After the rebuilt books are installed |
| Contents lists the weekly portions in the right order (Miketz before Vayigash and Vayechi) | TAN-003 | After the rebuilt books are installed |
| Genesis first open time with its sidecar present | TAN-005 | After the sidecars are copied |
| Berakhot first open time with a fresh sidecar | TAL-014 | After the sidecar is verified |
| Handles: flip either way, in English, in Hebrew, and in a mixed paragraph; **More** stretches the selection across paragraphs; then Copy, Dictionary, Add Note and Underline; restart and confirm notes and underlines survive; repeat in a text-layer PDF (PDFs stay single-paragraph) | SEL-002 to SEL-005 | After those fixes are built. There is nothing new to check yet. |
| Talmud settings no longer show Paragraphs / Continuous | TAL-012 | After the setting is removed |
| Repeat anything odd in the file browser; write down exact steps | BRW-001 | Only if it happens again |

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
