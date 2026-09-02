# Bigme device test log

This file keeps the user's manual observations separate from automated results.
The device was a **Bigme HiBreak**, Android 14/API 34, arm64. Exact renderer and
Bigme refresh mode were not recorded.

## 2026-08-31 manual pass

The user completed the eight-part checklist. Startup, file browsing, app drawer,
status bar, EPUB/TXT/Markdown, saved reading state, interruptions, sustained use,
and safe recovery were reported good except for the PDF behavior below. Individual
substeps, timings, memory measurements, and advanced crash-loop fault injection
were not separately recorded.

The PDF symptoms occurred across every PDF tried, including small files. File
types, sizes, page counts, and scanned versus vector classification are unknown.

| ID | Original observation | Current status |
| --- | --- | --- |
| PDF-001 | Rapid next-page taps could leave Fit Height/Fit Width unresponsive. | **Reported fixed on device** after version 1.0.1. Exact tap rate and recovery behavior from the original failure remain unknown. |
| PDF-002 | Releasing a pinch in Zoom / Scroll briefly showed white, then content returned segment by segment, usually in under a second. | **Needs a focused retest.** No trace established whether the whole viewport or only tiles disappeared. |
| PDF-003 | Fast Zoom / Scroll movement or taps reached unseen pages before useful pixels appeared. | **Still visible in the first 1.0.1 check.** The user noted this happened at minimum zoom while moving through several pages per second. Version 1.0.2 has not yet been checked. |

The observations describe what appeared on the panel; they do not identify a
Flutter rebuild, PDFium failure, or e-ink refresh cause.

## Software follow-up

Version 1.0.1 added bounded priority rendering, cancellable/shared work, ordered
rapid navigation, correct-page movement previews, retained old detail, and a short
idle refinement delay. The user then confirmed that rapid taps work, resolving
PDF-001 for the tested case.

Version 1.0.2 adds persistent 320-pixel page previews, velocity-aware look-ahead,
idle preview warming, and immediate finger-down fling stopping. These target
PDF-003 but cannot guarantee instant pixels for a never-rendered page. Details and
the current APK are in [PDF_RESPONSIVENESS.md](PDF_RESPONSIVENESS.md).

## Next device evidence

Use one text/vector PDF and one scanned PDF with the same renderer and Bigme
refresh mode:

1. Compare the first fast pass with a second pass over the same pages.
2. Repeat pinch/release before and after sharpening completes.
3. Confirm a resting finger stops momentum immediately.
4. Record time to first useful preview separately from time to sharp text.
5. If white persists, an external-camera video plus app timing/memory data can
   distinguish missing app pixels from panel refresh behavior.
