# Bigme device testing log

## 2026-08-31 — first manual pass

Device: **Bigme HiBreak**, Android 14 / API 34, arm64, as identified in the
connected-device check. This run is on the HiBreak, not the B751C named in the
original reader plan. Exact installed build and renderer are not yet confirmed.

Source: user observations during the manual checklist in this task. These are
reported device results, not independently reproduced failures or measured traces.
At the user's request, this update records findings only: **no code fixes,
renderer changes, or device changes are authorized by this report**.

| Manual test | Reported result |
| --- | --- |
| 1. Startup and home folder | Good; no issue reported. |
| 2. File browser | Good; no issue reported. |
| 3. App drawer and status bar | Good; no issue reported. |
| 4. PDF reading | Issues below; other tested behavior reported good. |
| 5. EPUB, TXT, and Markdown | Passed, per user follow-up. |
| 6. Saved reading state | Passed, per user follow-up. |
| 7. Interruptions and sustained use | Passed apart from the PDF issues below; user reports all other tests pass. |
| 8. Safe recovery | Passed, per user follow-up. |

The user has completed the eight-test manual checklist and reports that all other
tests pass, with the PDF issues below remaining open. Individual substeps were not
separately itemized. This does not sign off advanced crash-loop/corrupt-state fault
injection, memory profiling, or renderer comparisons.

Follow-up scope: the symptoms occur across **all PDFs the user tested, including
small files**. This is not limited to a single large document. File names, exact
sizes/page counts, and scanned versus text/vector classification are not recorded.

### PDF-001 — screen freezes after rapid next-page taps

- **Status:** Open; reported on device, cause unknown.
- **Modes:** Fit Height and Fit Width. Tapping in Zoom / Scroll does not produce
  this freeze; it produces the unloaded-page delay tracked as PDF-003 instead.
- **Trigger:** Open a PDF and tap next page several times quite quickly.
- **Observed:** The screen freezes and is unresponsive. The user does not know
  what restores responsiveness.
- **Expected:** Repeated page navigation remains responsive and eventually
  displays the intended page without getting stuck.
- **Unknown:** Tap count/rate, duration, whether it recovers without intervention,
  and a reliable recovery action. The centre menu and Android Back were not
  individually confirmed as responsive or unresponsive. A persistent hang versus
  a temporary render delay is not established.

### PDF-002 — white screens and visible content rebuilding while zooming in

- **Status:** Open; reported on device, cause unknown.
- **Mode:** PDF Zoom / Scroll.
- **Trigger:** Zoom in on a PDF and release the pinch gesture.
- **Observed:** Blanking occurs **after release**, usually for slightly less than
  one second. The page visibly loads one segment at a time. The user finds this
  disruptive. "Rebuilding" describes the visual observation, not a confirmed
  Flutter widget rebuild or engine diagnosis.
- **Expected:** Content stays visible through zooming and resolution refinement.
- **Unknown:** Whether the entire viewport initially disappears or only parts,
  and measured timings. The reported sub-second delay is an estimate, not a trace.

### PDF-003 — fast scrolling reaches blank pages while rendering catches up

- **Status:** Open; reported on device, cause unknown.
- **Mode:** PDF Zoom / Scroll.
- **Trigger:** Scroll quickly through a PDF, or tap to advance in Zoom / Scroll.
- **Observed:** Pages take time to load, leaving a white screen that the user
  must wait at before content appears. Tapping in this mode produces this delay,
  rather than the unresponsive freeze seen in Fit Height / Fit Width.
- **Expected:** Fast navigation retains useful visible content rather than
  repeatedly making the user wait on an empty viewport.
- **Unknown:** Zoom level, scrolling/tap delay duration, and whether returning to
  recently viewed pages produces the same delay. The sub-second estimate for
  PDF-002 was about zoom release; it is not a measured duration for scrolling.

PDF-002 and PDF-003 are tracked separately to preserve their different triggers;
they may share a cause, but that has not been established.

### User suggestion — not an agreed implementation

Consider postponing full-resolution page rendering until the user stays on a
page for approximately one second. This is a possible approach for later
investigation, not a confirmed cause, selected fix, or implemented behavior.
No code investigation or fix was performed as part of recording this report.

### Optional evidence for a later investigation

- A representative PDF, its size/page count, and whether it is scanned or
  text/vector; exact build, renderer, and Bigme refresh setting.
- An external-camera video showing rapid taps and the unresponsive state, or
  the segments appearing after zoom release.
- A reliable recovery action for PDF-001, if one becomes apparent, and separate
  timing observations for PDF-003.

No additional manual test or code change is required to record this follow-up.
The issues remain open; no cause or fix has been confirmed.

## Subsequent software follow-up — 2026-08-31

The user subsequently authorized implementing the pre-device-test improvements
and useful supporting changes while unavailable for manual testing. This
supersedes the earlier recording-only scope for the new work, not for the original
observations above. The implementation and software validation are documented in
[PDF_RESPONSIVENESS.md](PDF_RESPONSIVENESS.md).

PDF-001, PDF-002, and PDF-003 remain open for HiBreak verification. No new device
test result is implied by the code changes or automated tests.
