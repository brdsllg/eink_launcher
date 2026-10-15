# Selection and annotations

Long-pressing a word starts a selection with draggable handles. An action bar offers
**Copy**, **Dictionary**, **Add Note**, and **Underline**. Adding a note underlines
its text automatically; tapping an underline shows its note, with Edit and Delete.

**What is built (as of 7 Oct 2026, More-chain rebuilt 11 Oct):** selection, the four
actions, saved annotations and bidirectional handles are implemented and covered
by automated tests. Multi-paragraph underline and note are built through the
toolbar **More** button, which extends the selection through the next readable
paragraph (repeatable): the start paragraph highlights to its end, every covered
following paragraph highlights in full, then saves one multi-block annotation
(underlines in every covered paragraph, one note viewer). Copy, Add Note and
Underline apply to the whole combined range; Dictionary looks up the originally
selected word. Dragging across block boundaries in one gesture is not built
(each paragraph owns its own text painter, so a true drag would need a
cross-widget gesture + layout rewrite; More-chain is the supported pattern).

**Whether any of it works on the device** is recorded only in the issue tracker in
[DEVICE_TESTING.md](DEVICE_TESTING.md): SEL-001 (handle size), SEL-002 (**More**),
SEL-003 to SEL-005 (handle flipping, Hebrew, mixed text).

**What the owner wants from More (6 Oct 2026):** the **More** button should let the
*selection itself* extend across multiple paragraphs, so Copy, Dictionary, Add Note
and Underline then apply to the whole multi-paragraph range. Keep the button if it
helps, but change what it does. (Older notes described the current behavior as
"underline the rest of this paragraph". Check the source for what it really does
before reworking.)

## Scope

| Included | Not included |
| --- | --- |
| EPUB, TXT, Markdown (the shared text pipeline), including multi-paragraph selection via **More** (start block + following readable blocks, all highlighted; Copy/Note/Underline apply to the combined range, Dictionary to the selected word) | Dragging handles across two blocks in one gesture; selection across chapters/pages |
| PDFs with a text layer, including cropped pages and Zoom / Scroll | Image-only PDFs (would need OCR) |
| Underline as the only style | Highlight colors or other styles, which would break the black-and-white rule |

## How it works

- **Selection:** a long-press snaps to a word; the handles then grow or shrink the
  selection one character at a time, clamped to the block's text. Each has a 48 dp
  touch target and lives in an overlay outside the clipped text slice, so short
  paragraphs and page-boundary selections still have reachable controls. The action
  bar sits above the selection (below if there is no room).
- **Actions:** Copy puts the exact selected text on the clipboard. Dictionary opens
  the offline definition. Underline saves an annotation with no note. Add Note
  saves one with the typed note.
- **Saving:** an annotation records its book, position (chapter and start block),
  start and end offsets, the selected text (paragraphs joined by blank lines),
  and an optional note. A multi-block annotation also records its end block
  (index, id, document, offset). It is saved
  with the book's reading state in `library.json`, and annotations on a newly opened
  book create its first saved state. Page-turn saves keep annotations.
- **Anchoring:** saved offsets refer to each block's *original* text, including
  hidden vowel points. Generated
  hyphens and decorative prefixes shift on-screen offsets, so the app converts
  between the two; that is why underlines stay put when font size, hyphenation,
  or vowel visibility changes.
- **PDFs:** annotations use normalized rectangles from the PDF text layer, so they
  stay anchored as the view changes.
- **Drawing and tapping:** underlines are 1.5 px black lines drawn beneath the text
  and under the temporary gray selection highlight. Tapping inside an underline
  opens its note; tapping elsewhere behaves as before (including links).

## Device check, when the fixes exist

On the Bigme: select text in an EPUB paragraph and try Copy, Dictionary, Add Note and
Underline. Then check:

- **More** stretches the *selection* across paragraphs (SEL-002).
- Dragging either handle either way: the other handle must not jump letters or words
  (SEL-003), Hebrew handles must not pull each other (SEL-004), and a paragraph that
  mixes Hebrew and English must behave (SEL-005).
- Restart the app and confirm the underline and note survived.
- Repeat in a text-layer PDF (PDFs stay single-block).

Record results as a new test pass in [DEVICE_TESTING.md](DEVICE_TESTING.md).
