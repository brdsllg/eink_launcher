# Bigme device test log

This file keeps the user's manual observations separate from automated results.
The later [2026-09-02 ADB validation](DEVICE_VALIDATION_2026-09-02.md) covers
version 1.0.2 with generated fixtures. The user subsequently confirmed no ghosting
or white flashes on the physical screen; see the confirmation below.
The device was a **Bigme HiBreak**, Android 14/API 34, arm64. Exact renderer and
Bigme refresh mode were not recorded for the original manual pass.

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
| PDF-002 | Releasing a pinch in Zoom / Scroll briefly showed white, then content returned segment by segment, usually in under a second. | **Resolved for the observed 1.0.2 test conditions.** On 2026-09-02 the user confirmed no ghosting or white flashes after the ADB pass. |
| PDF-003 | Fast Zoom / Scroll movement or taps reached unseen pages before useful pixels appeared. | **Resolved for the observed 1.0.2 test conditions.** ADB scroll samples retained content and the user confirmed no ghosting or white flashes on 2026-09-02. First-time rendering remains subject to the documented throughput limit. |

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

## 2026-09-02 physical-screen confirmation

After the version 1.0.2 ADB validation, the user reported: "no ghosting or white
flashes." This closes the outstanding physical-screen confirmation for PDF-002
and PDF-003 under the observed test conditions. It is direct user feedback,
separate from the sampled screenshot evidence, and does not establish a preferred
renderer or guarantee every document and scroll speed.

No further physical-panel retest is required before planning tabs. Precise
preview/sharpen timings and unplugged idle battery drain remain optional
measurements.

## Optional regression checklist

Use one text/vector PDF and one scanned PDF with the same renderer and Bigme
refresh mode:

1. Compare the first fast pass with a second pass over the same pages.
2. Repeat pinch/release before and after sharpening completes.
3. Confirm a resting finger stops momentum immediately.
4. Record time to first useful preview separately from time to sharp text.
5. If white persists, an external-camera video plus app timing/memory data can
   distinguish missing app pixels from panel refresh behavior.
