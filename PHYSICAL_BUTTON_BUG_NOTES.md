# Physical page-turn button bug — investigation notes (2026-09-18)

## Symptom

- Physical page-turn buttons (the mappings in `BUTTON_SUPPORT.md`: Page Up/Down,
  Left/Right, Volume Up/Down) intermittently stop responding inside the reader.
- On-screen tap zones / UI page-turn controls keep working fine during the same
  episode.
- Once it starts, it affects every open book, not just the one being read when
  it started.
- This is distinct from the pagination-window issue below, which is expected
  and separate.

## Ruled out

1. **In-app Dart/Flutter runtime state** — `_capturedKeys` in
   `lib/widgets/page_button_scope.dart`, or Flutter's `HardwareKeyboard.instance`
   singleton getting a key wedged as "still down" after a lost release event.
   - *Why ruled out:* a full app restart recreates the Dart VM/engine, which
     would reset both to empty. Confirmed: neither backing out to the file
     list nor a full app restart fixed it.

2. **A persisted settings flip** — `ReaderSettings.pageButtonsEnabled` saved as
   `false` somewhere that applies to every book.
   - *Why ruled out:* read through `BookStoreService`,
     `TextReaderSession.applySettings`, and `PdfReaderSession.applySettings`.
     The "physical page buttons" toggle in `reader_settings_screen.dart` is
     always persisted as a **per-book override**
     (`saveBookState(... settingsOverride: settings)`), never via
     `saveGlobalSettings`. `saveGlobalSettings` exists on `BookStoreService`
     but nothing in the current codebase calls it. There's no code path today
     that disables the buttons for every book from one toggle.

3. **OS-level stuck key / mechanical button fault** — Android's input layer,
   or the physical switch itself, stuck believing a key is held.
   - *Why ruled out:* confirmed the same physical buttons work correctly
     outside the app while the bug is active.

## Separate, confirmed bug (real, but not this symptom)

`TextReaderSession.nextPage()` / `prevPage()`
(`lib/reader/controllers/text_reader_session.dart`) check `_currentPage`
against `_pages.length`. During any repagination — book open, viewport/
orientation change, a settings change, or a TOC/search/bookmark jump to a
not-yet-laid-out chapter — `_repaginate()` resets `_pages` to `[]` and
`_currentPage` to `0` while `session.isReady` stays `true` throughout. In that
window `nextPage`/`prevPage` silently no-op (`0 >= -1` / `0 <= 0`), and
`PageButtonScope.enabled` never checks `isPaginating`, so the button looks
armed but does nothing.

- EPUB/TXT/Markdown only — PDF uses a proper ordered turn queue
  (`PdfReaderSession._enqueueTurn`) and doesn't have this issue.
- Confirmed by code reading; not yet fixed.
- Confirmed by Levi that this is *not* the main symptom being chased — it's a
  known, momentary, expected-during-pagination gap, separate from the
  "stops working entirely, across all books" bug above.

## Current state: unexplained

The main symptom is app-specific (fine everywhere else on the tablet) but
survives a full app restart, so the cause isn't located yet. Two untested
possibilities:

- Something Android or the Bigme firmware associates specifically with this
  app's package/window (e.g. an OEM per-app button-mapping/profile setting)
  rather than with the process instance, so restarting the app doesn't reset
  it.
- Some other app-window-scoped OS state (e.g. IME/focus history tied to this
  app) left in a bad state by a particular in-app action, not cleared by a
  normal restart.

## Suggested next step (not yet done)

Add a temporary logging hook in `MainActivity.kt` (override
`dispatchKeyEvent`) to log every raw Android `KeyEvent` the app's window
receives, then reproduce the failure and check logcat:

- No events at all while broken → confirms it's upstream of Flutter, scoped
  to this app's window (Android/OEM level) — not fixable in Dart code alone.
- Events show up but nothing acts on them → reopens the Dart-level
  investigation with real data instead of guesses.
