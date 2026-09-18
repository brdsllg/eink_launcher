# Annotation plan: selection, copy, dictionary, notes, and underlines

## Implementation status (2026-09-18)

Implemented hardest-first: selection geometry, draggable controls, stable text
anchors and underline hit-testing; then persistence, toolbar actions, note
dialogs, and documentation. `flutter analyze --no-pub` is clean, and
`flutter test --no-pub` passes with 360 tests passed and 3 native PDF checks
skipped. The Bigme device check in Step 7.3 remains pending and requires user
confirmation.

Implementation details discovered in this checkout:
- The product-decision table is in `READER_PLAN.md`, not `READER_DESIGN.md`.
- Saved offsets use the original block text. Painter offsets include generated
  hyphenation and decorative prefixes, so saving those directly would move
  underlines when typography settings change. `AnnotationTextMapping` converts
  between the two using the paginator's existing offset mapping.
- Selection controls use an overlay outside the clipped text slice so short
  paragraphs and page-boundary selections still have reachable controls.
- Page-turn saves preserve annotations, and annotations on a newly opened book
  create its first saved state. `saveBookState` remains the persistence API.
- A follow-on implementation supports word-level PDF annotations using
  normalized PDF text-layer rectangles, including cropped pages and Zoom /
  Scroll. Image-only PDFs still require OCR and remain unsupported.

The original implementation checklist follows for reference.

This replaces the current behavior where long-pressing a word immediately opens
its dictionary definition. Instead, long-press starts a selection with
draggable handles, and an action bar offers **Copy**, **Dictionary**, **Add
Note**, and **Underline**. Adding a note underlines its range automatically;
tapping an underlined range shows the note.

This plan is written as small, ordered steps for an AI with no prior context
on this codebase. Each step touches one file (or a tightly related pair), says
exactly what to add, and ends with a concrete "Done when" check. Do not skip
ahead — later steps assume earlier ones compile and pass their checks.

## Scope

| In scope | Out of scope (for this plan) |
| --- | --- |
| EPUB, TXT, Markdown (the shared text pipeline) | PDF selection — PDFium exposes text through a separate API; a follow-on plan will cover it |
| Selection confined to one `ContentBlock` (one paragraph/heading/etc.) | Selection dragged across two blocks — would require lifting selection state out of `BlockSliceView` into `TextPageView` |
| Underline as the only annotation style | Highlight colors, multiple underline styles — stay pure black/white per the e-ink rules in `README.md` |

`READER_DESIGN.md`'s product-decision table currently lists "Highlights, notes"
under **Not planned**. Step 7.1 below corrects that once this feature exists.

## Before starting: read these first

Read each file fully before touching anything. They establish the exact
patterns every step below reuses.

| File | Why |
| --- | --- |
| `lib/reader/models/bookmark.dart` | `Annotation` (Step 1.1) copies this shape exactly |
| `lib/reader/models/reading_position.dart` (`TextReadingPosition`) | Shows the existing `spineIndex` / `blockIndex` / `charOffset` anchor convention |
| `lib/reader/models/book_state.dart` | Shows how `bookmarks` is stored, serialized, and copied — `annotations` mirrors it |
| `lib/reader/services/book_store_service.dart` | The actual persistence: one debounced `library.json` via `path_provider`. (Not the `shared_preferences` package — same idea, different mechanism.) |
| `lib/reader/services/text_word_selection.dart` (`wordAtOffset`) | The existing word-snap logic; selection start reuses this unchanged |
| `lib/reader/widgets/block_slice_view.dart` | Where nearly all the UI work in this plan happens — current long-press → dictionary flow lives here |
| `lib/reader/widgets/dictionary_dialog.dart` | The dialog style to match: `AnimationStyle.noAnimation`, plain `showDialog` |
| `lib/reader/widgets/reader_menu_overlay.dart` (`_MenuButton`) | The e-ink button style to match for the new toolbar: sharp corners, black/white, no ripple |

Two agents can work on this codebase at once — re-read a file immediately
before editing it if any time has passed since the table above.

## Phase 1 — `Annotation` model

### Step 1.1 — Create the model
File: `lib/reader/models/annotation.dart` (new)

Fields, matching `Bookmark`'s field style:
```dart
class Annotation {
  final String id;          // Annotation.generateId(), same pattern as Bookmark
  final String docId;
  final DateTime createdAt;
  final int spineIndex;
  final int blockIndex;
  final int startOffset;    // TextSelection.baseOffset, within the block's plain text
  final int endOffset;      // TextSelection.extentOffset
  final String text;        // snapshot of the selected text, for display
  final String? note;       // null = underline only, no note
}
```
Add `toJson` / `fromJson` / a `generateId()` static, following `bookmark.dart`
line for line.

**Done when:** the file compiles with `flutter analyze --no-pub` and a new
`test/reader/models/annotation_test.dart` round-trips `toJson`/`fromJson`
(mirror whatever existing test covers `Bookmark`, if one exists — check
`test/reader/models/` first).

### Step 1.2 — Confirm the anchor convention
No code change. Just confirm: `spineIndex` comes from
`page.start.spineIndex` and `blockIndex` from `slice.blockIndex`, both already
available in `TextPageView.build` (see `text_page_view.dart`). Write this down
in a comment above the `Annotation` class so Phase 5 doesn't have to
rediscover it.

**Done when:** the comment is in place.

## Phase 2 — Persistence

### Step 2.1 — Add `annotations` to `BookState`
File: `lib/reader/models/book_state.dart`

Add a field exactly parallel to `bookmarks`:
```dart
final List<Annotation> annotations;
```
- Constructor: `this.annotations = const []`
- `copyWith`: add `List<Annotation>? annotations` param, same pattern as
  `bookmarks`
- `toJson`: `if (annotations.isNotEmpty) 'annotations': annotations.map((a) => a.toJson()).toList()`
- `fromJson`: same optional-list pattern used for `bookmarks`

**Done when:** `flutter analyze --no-pub` is clean and a `BookState`
round-trip test (extend whatever test file covers `BookState.toJson`/
`fromJson` today) passes with a non-empty `annotations` list.

### Step 2.2 — No new service method needed
Confirm `BookStoreService.saveBookState(state)` is sufficient — callers will
do `state.copyWith(annotations: [...state.annotations, newAnnotation])` and
call `saveBookState`. Do not add an `addAnnotation` method; the codebase
doesn't have an `addBookmark` method either, by the same pattern.

**Done when:** you've confirmed this by reading how bookmarks currently get
added (search for where `bookmarks:` is used in a `copyWith` call).

## Phase 3 — Selection engine (handles)

This phase only changes `lib/reader/widgets/block_slice_view.dart`.

### Step 3.1 — Stop auto-firing the dictionary on long-press
Currently `_selectWord` calls `wordAtOffset`, sets `_selection`, then
immediately `await widget.onDefineWord!(selected.word)`. Change this so
`_selectWord` only sets `_selection` and enters a new bool state,
`_selecting = true`. Do not call `onDefineWord` here anymore — that moves to
the toolbar in Phase 4.

**Done when:** long-pressing a word highlights it (existing gray box) and
nothing else happens — no dialog opens. Existing dictionary tests will now
fail; that's expected and gets fixed in Step 4.3.

### Step 3.2 — Add handle widgets
Add two small `CustomPaint` or `Container`-based markers (solid black,
sharp-cornered, no shadow — no new visual style needed beyond what
`reader_menu_overlay.dart` already establishes elsewhere). Position them at:
- start handle: bottom-left corner of `painter.getBoxesForSelection(selection).first`
- end handle: bottom-right corner of `painter.getBoxesForSelection(selection).last`

Wrap each in its own small `GestureDetector` with `onPanUpdate`.

**Done when:** after a long-press, two markers are visible at the correct
corners of the highlighted word (verify with a widget test using
`tester.getTopLeft`/`getBottomRight` on the handle keys).

### Step 3.3 — Wire dragging to grow/shrink the selection
On the start handle's `onPanUpdate`, recompute
`painter.getPositionForOffset(localPosition).offset`, clamp it to
`0 <= x <= selection.extentOffset - 1`, and call
`setState(() => _selection = _selection.copyWith(baseOffset: x))`. Mirror this
for the end handle against `startOffset`.

Clamp both to the current block's own text length — do not let the offset
escape `[0, painter.text!.toPlainText().length]`. This is what keeps
selection inside one block for this plan (see Scope table).

**Done when:** dragging either handle grows or shrinks the highlighted region
live, one character at a time, and stops at the block's edges without
crashing.

## Phase 4 — Selection toolbar

### Step 4.1 — Build the toolbar widget
File: `lib/reader/widgets/selection_toolbar.dart` (new)

A `StatelessWidget` taking `onCopy`, `onDictionary`, `onAddNote`,
`onUnderline` callbacks. Style it like `_MenuButton` in
`reader_menu_overlay.dart`: `TextButton` with
`shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero)`, black text
on white, no `elevation`. Lay the four buttons out in a single row.

**Done when:** a widget test can pump `SelectionToolbar` standalone and find
all four buttons by key.

### Step 4.2 — Show the toolbar after a selection settles
In `block_slice_view.dart`, when `_selecting == true`, position a
`SelectionToolbar` above the selection's bounding box (below it if there's no
room above — check against the block's own height, not the full screen, since
this widget doesn't know its screen position).

**Done when:** after long-pressing a word, the toolbar appears near it and
stays anchored correctly while the handles from Step 3.3 are dragged.

### Step 4.3 — Wire Copy
`onCopy: () => Clipboard.setData(ClipboardData(text: selectedPlainText))`,
then clear `_selecting`.

**Done when:** tapping Copy on a selection puts the exact selected substring
on the clipboard (verify with a widget test using a fake `Clipboard` handler,
matching this project's `noSuchMethod` fake pattern).

### Step 4.4 — Wire Dictionary
`onDictionary: () => showDictionaryDefinition(context, selectedPlainText)`,
then clear `_selecting`. This is the same call the old `onDefineWord` used to
make — restores the previous dictionary tests, now triggered from the toolbar
instead of automatically.

**Done when:** the dictionary tests broken in Step 3.1 pass again, now driven
through the toolbar's Dictionary button instead of a bare long-press.

### Step 4.5 — Wire Underline
Build an `Annotation` (`note: null`) from the current `docId`, `spineIndex`,
`blockIndex`, and `_selection`'s offsets and selected text. Append it to the
current `BookState.annotations` and call `saveBookState`. Clear `_selecting`.

**Done when:** after selecting text and tapping Underline, a new `Annotation`
exists in `BookStoreService.instance.getBookState(docId)!.annotations`
(verify in a test, not by rendering yet — rendering is Phase 5).

### Step 4.6 — Add-note dialog + wire Add Note
New small dialog (reuse the `GridDialog`/`AnimationStyle.noAnimation` pattern
from `dictionary_dialog.dart`) with a single multiline `TextField` and
Save/Cancel. On Save, build an `Annotation` the same way as Step 4.5 but with
`note: enteredText`, save it, clear `_selecting`.

**Done when:** after selecting text, tapping Add Note, typing, and tapping
Save, the saved `Annotation.note` matches what was typed.

## Phase 5 — Rendering persisted underlines

### Step 5.1 — Pass annotations down from `TextPageView`
File: `lib/reader/widgets/text_page_view.dart`

Look up `BookStoreService.instance.getBookState(docId)?.annotations ?? []`
once per build, filter to
`a.spineIndex == page.start.spineIndex && a.blockIndex == slice.blockIndex`,
and pass the filtered list as a new `annotations` param to `BlockSliceView`.

**Done when:** `flutter analyze --no-pub` is clean with the new param
threaded through.

### Step 5.2 — Draw the underline
File: `lib/reader/widgets/block_slice_view.dart` (`_TextBlockPainter`)

For each annotation passed in, build a `TextSelection(baseOffset:
a.startOffset, extentOffset: a.endOffset)`, get its boxes via
`painter.getBoxesForSelection(...)`, and draw a 1.5px solid black line at each
box's bottom edge (`canvas.drawLine`). Draw this before the transient gray
`_selection` highlight so an active selection remains visually distinct from
a saved underline.

**Done when:** a widget test that saves an `Annotation` and then rebuilds
`BlockSliceView` finds a black line painted under the correct text range
(golden-image or `findsPaint`-style assertion, matching existing painter
tests in this file's test suite if any exist).

## Phase 6 — Tap-to-view/edit note

### Step 6.1 — Hit-test taps against annotations
File: `lib/reader/widgets/block_slice_view.dart`

In the existing `onTapUp` handler (currently only checks
`block.runs.any((run) => run.href?.isNotEmpty == true)` for links), add a
check: for each passed-in annotation, get its boxes the same way as Step 5.2
and see if any box contains `details.localPosition`. If one matches, call a
new `onOpenAnnotation(Annotation)` callback instead of the link logic.

**Done when:** tapping inside a saved underline (with or without a note)
calls `onOpenAnnotation` with the right `Annotation`, and tapping elsewhere
still behaves as before.

### Step 6.2 — Note viewer/editor dialog
New dialog, same `AnimationStyle.noAnimation` pattern, showing
`annotation.note` (or "No note — underline only" if null) with Edit and
Delete actions. Edit reopens the Step 4.6 text field pre-filled. Delete
removes the `Annotation` from `BookState.annotations` and calls
`saveBookState`.

**Done when:** tapping a saved underline shows its note; Delete removes the
underline from the next render (re-run Step 5.2's test after deleting).

## Phase 7 — Docs and full verification

### Step 7.1 — Fix `READER_DESIGN.md`
In the product-decision table, remove "Highlights, notes" from the **Not
planned** row (or remove the row if TTS and DRM bypass are the only things
left in it) and add a row: `| Annotations | Underline + optional note, EPUB/TXT/Markdown only — see annotation_plan.md |`.

**Done when:** the table no longer contradicts this plan.

### Step 7.2 — Full verification
```powershell
flutter analyze --no-pub
flutter test --no-pub
```

**Done when:** both are clean, per this project's standard verification bar.

### Step 7.3 — On-device check
Per this project's convention, phase completion for UI work is confirmed by
on-device testing, not code review alone. On the Bigme device: select text
inside an EPUB paragraph, try Copy/Dictionary/Add Note/Underline, restart the
app, and confirm the underline and note both survived the restart.

**Done when:** the user confirms this on-device.
