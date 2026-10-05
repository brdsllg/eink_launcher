# Selection and annotations

Long-pressing a word starts a selection with draggable handles. An action bar offers
**Copy**, **Dictionary**, **Add Note**, and **Underline**. Adding a note underlines
its text automatically; tapping an underline shows its note, with Edit and Delete.

**Status:** implemented in code and covered by automated tests, but the current
Bigme validation is still pending. The feature is therefore considered
implemented-but-not-finally-confirmed: selection works within a single block,
while multi-paragraph selection remains unsupported and is still a desired
improvement. Following the 5 October device pass, the selection handles have a
48 dp touch target; their physical usability still needs confirmation on the
HiBreak.

## Scope

| Included | Not included |
| --- | --- |
| EPUB, TXT, Markdown (the shared text pipeline) | Selection that spans two blocks (paragraphs, headings); selection stays inside one block |
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
- **Saving:** an annotation records its book, position (chapter and block), start and
  end offsets within the block, the selected text, and an optional note. It is saved
  with the book's reading state in `library.json`, and annotations on a newly opened
  book create its first saved state. Page-turn saves keep annotations.
- **Anchoring:** saved offsets refer to the block's *original* text. Generated
  hyphens and decorative prefixes shift on-screen offsets, so the app converts
  between the two; that is why underlines stay put when font size or hyphenation
  changes.
- **PDFs:** annotations use normalized rectangles from the PDF text layer, so they
  stay anchored as the view changes.
- **Drawing and tapping:** underlines are 1.5 px black lines drawn beneath the text
  and under the temporary gray selection highlight. Tapping inside an underline
  opens its note; tapping elsewhere behaves as before (including links).

## Remaining check on the device

On the Bigme: select text in an EPUB paragraph, try Copy, Dictionary, Add Note, and
Underline, restart the app, and confirm the underline and note survived. Repeat in a
text-layer PDF. This is the last item, and it needs Levi's confirmation.
