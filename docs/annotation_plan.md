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
Underline apply to the whole combined range; Dictionary is meant to look up the originally
selected word (the code does not do this yet; see SEL-009). Dragging across block boundaries in one gesture is not built
(each paragraph owns its own text painter, so a true drag would need a
cross-widget gesture + layout rewrite; More-chain is the supported pattern).

**Whether any of it works on the device** is recorded only in the issue tracker in
[DEVICE_TESTING.md](DEVICE_TESTING.md): SEL-001 (handle size), SEL-002 (**More**),
SEL-003 to SEL-005 (handle flipping, Hebrew, mixed text), and SEL-006 to SEL-023 (further problems found by code review, summarized below).

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

## Known problems (code review, 22 Oct 2026)

Found by reading the code, not by testing on the device. Every item has a row in
[DEVICE_TESTING.md](DEVICE_TESTING.md), which is the only place that says where it stands.

**Handles (SEL-003 to SEL-005, SEL-017).**

- The dragged edge follows the finger directly instead of keeping the gap between the
  finger and the text edge. The 48 dp touch area sits below the line and outside the
  edge, so the first movement jumps the edge a few letters sideways or onto the next line.
- The flip rule has a 2-character dead zone, counted in internal character units, not
  letters. In pointed Hebrew a letter with its vowel counts as two units; in English two
  units are two letters. While the finger is in the zone the selection freezes, then pops.
- Handle positions come from the first and last drawn box and from the paragraph's overall
  direction. A selection that mixes Hebrew and English is several separate boxes on one
  line, and the point where the two scripts meet is one text position with two places on
  screen.
- The cause of SEL-004 is not visible in the code. Record the finger position and both
  selection ends on every drag step in one Hebrew paragraph.
- Every drag step lays out the whole paragraph again. That is fine for normal paragraphs,
  but not for the huge Tamid paragraph (see TAL-015).

**Starting a selection (SEL-006 to SEL-008).** A long-press only starts on a letter-word,
so numbers, punctuation and symbols do nothing. Hebrew abbreviation marks and the maqaf are
not treated like an ordinary hyphen. With vowels hidden, the selection ends right after the
last letter and leaves out that letter's hidden vowels.

**More (SEL-009 to SEL-012).** After **More**, Dictionary receives the rest of the
paragraph, not the first word. Touching a handle afterwards clears the extra paragraphs.
The range can reach paragraphs on the next page. It only goes forward and always ends at
the end of a whole paragraph.

**Underlines and notes (SEL-013 to SEL-016).** A saved annotation is matched by exact
position and text, so a rebuilt book hides older ones. An underline with a note looks like
one without. Overlapping underlines leave only one tappable. The underline may touch Hebrew
vowels below the letters. Tapping inside an underline opens its note by design, which also
means page-turn and link taps do not work on underlined text.

**PDFs (SEL-018 to SEL-023).** PDF handles cannot cross and assume left-to-right text.
Hebrew PDFs may store text backwards, and two-column PDFs select in hidden text order.
Cleanup of hyphens and line breaks differs between a long-press and a handle drag.
Underlines are drawn one letter at a time.

**Automated tests.** The selection tests cover one short English line. None covers Hebrew,
mixed text, several lines, hidden vowels, or one handle crossing the other, so passing
tests say nothing about SEL-003 to SEL-005.

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
