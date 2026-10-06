# Tanach EPUB: reader compatibility guide

The format reference for the Tanach (and, by extension, Talmud) EPUBs, written from
inspecting the actual files. The bundled reader implements this contract (see
`../docs/tanach-epub.md`); this guide remains the reference for any other reader and
for checking regressions. Current format: presentation revision 5, with Hebrew text at
1.1em (amended Oct 2026: study headings 1.0em bold, note titles 0.9em).

## 1. What the reader needs to do

The files are reflowable EPUB 3 books. A basic reader can show the chapters and follow
ordinary links to chapter-end notes. A study reader should parse those notes into a
separate store, paginate the main text, and open chosen commentary in its own view.

The EPUB carries text, verse-to-note relationships, source names, categories, language
directions, and edition identifiers. The reader supplies the interface: source
switches, translation selection, note panels, and pagination. There is no script, no
Sefaria API dependency, and no database inside an EPUB.

Recommended approach: keep the Hebrew and primary English in the reading flow and show
commentary in a separate scrollable view. Changing a commentary filter in that view
then needs no repagination of the main text.

## 2. Package layout

```text
mimetype
META-INF/container.xml
EPUB/package.opf
EPUB/nav.xhtml
EPUB/toc.ncx
EPUB/style.css
EPUB/title.xhtml
EPUB/chapter-1.xhtml (one per chapter)
EPUB/credits.xhtml
```

Find the package through `container.xml` rather than hard-coding `EPUB/`. Read
resources and reading order from the manifest and spine. `nav.xhtml` gives navigation;
`toc.ncx` is a legacy extra. The spine sets `page-progression-direction="ltr"`; that
controls page turns, while each text block keeps its own direction, so assign gestures
accordingly. Complete books have several chapter documents, so keep the document path
in every resolved anchor and reading position. Packaging semantics follow the
[EPUB specification](https://www.w3.org/TR/epub-33/); general reading behavior is in
[EPUB Reading Systems](https://www.w3.org/TR/epub-rs-33/).

## 3. Verse → index → note

```text
Genesis 1:1 verse
    └── note link
          └── index-genesis-1-1
                ├── alternate translation link → translation aside
                ├── Rashi link → all Rashi comments for this verse, Hebrew + English
                └── other sources and their notes
```

The index exists because hundreds of links under each verse overwhelmed the page. A
custom reader can skip that index screen and use its links to fill a native source
chooser, opening the chosen note directly. All of these are real `<a>` links; do not
look only for tappable spans, and do not assume the verse's first link leads straight
to commentary text.

Abridged example (bracketed text stands for generated values):

```xml
<section class="verse" id="v-genesis-1-1" data-ref="Genesis 1:1">
  <h2>[one-row bilingual heading: English span left, Hebrew span right]</h2>
  <p class="hebrew" lang="he" xml:lang="he" dir="rtl">[Hebrew verse]</p>
  <div class="translation" lang="en" xml:lang="en" dir="ltr"
       data-edition="[edition id]" data-primary="true" data-translation-label="Metsudah">
    [Primary English translation]
  </div>
  <p class="note-links">
    <a epub:type="noteref" href="#index-genesis-1-1"
       data-category="index" data-ref="Genesis 1:1">[note link]</a>
  </p>
</section>

<aside epub:type="footnote" id="index-genesis-1-1"
       data-category="index" data-ref="Genesis 1:1">
  <a epub:type="noteref" href="#g-[group id]"
     data-source="Rashi on Genesis" data-category="rishon">Rashi on Genesis</a>
</aside>

<aside epub:type="footnote" id="g-[group id]" class="commentary-note"
       data-source="Rashi on Genesis" data-category="rishon"
       data-ref="Rashi on Genesis 1:1">
  <p class="note-title">Rashi on Genesis 1:1</p>
  <div class="note-he" lang="he" xml:lang="he" dir="rtl" data-editions="[ids]">
    <div class="comment-segment" data-note-id="[id]" data-ref="Rashi on Genesis 1:1:1">[Hebrew comment]</div>
    <div class="comment-segment" data-note-id="[id]" data-ref="Rashi on Genesis 1:1:2">[Hebrew comment]</div>
  </div>
  <div class="note-en" lang="en" xml:lang="en" dir="ltr" data-editions="[ids]">
    [separate comment-segment blocks for available English]
  </div>
  [backlinks]
</aside>
```

The XHTML uses the namespaces `http://www.w3.org/1999/xhtml` and
`http://www.idpf.org/2007/ops`. In an XML parser, recognize the `type` attribute of the
latter namespace, not the literal prefix `epub`, and test its space-separated tokens
for `noteref` or `footnote`. If an HTML parser keeps attributes under literal names,
support the `epub:type` form too.

## 4. Fields the parser must keep

| Element or field | Meaning and handling |
|---|---|
| `section.verse` | One base verse; keep its anchor (`v-{book}-{chapter}-{verse}`) and `data-ref` |
| Verse heading `h2` | One compact bold row with two independently directed spans (English left, Hebrew right) and a literal space between. Render as one horizontal row, not concatenated strings or two rows. Body size (1.0em), bold |
| `.hebrew` | Prepared source text; keep inline markup and Unicode. 1.1em |
| `.translation` | Default English for this verse, with opaque `data-edition`, `data-primary="true"`, and a short `data-translation-label`. No `data-source`. Never add a visible source label |
| `a` with `epub:type="noteref"` | Resolve `href`, then inspect the target's category |
| Aside, `data-category="index"` | Navigation to the verse's notes and alternates; not a commentator |
| Aside, `data-category="translation"` | Alternate English translation. Short `data-source` label, `data-edition` identity, **no** `note-title`; its direct English div is the replacement text |
| Aside, category `rishon`, `acharon`, or `modern` | Full commentary: class `commentary-note`, generated `g-` anchor, `data-source`, verse-level `data-ref`, one `note-title` |
| `.note-he`, `.note-en` | Language blocks; either may be absent. Hebrew commentary 1.1em, English 1em |
| `.comment-segment` | One comment, as its own paragraph block in document order. Keeps original `data-note-id`, `data-ref`, `data-editions`, and full content. Don't synthesize headings from segment refs |
| `data-editions` | Space-separated provenance ids. One block can cite several because the build fills gaps from other selected editions |
| Credits | Edition attribution appears in `credits.xhtml` only |
| `.backlinks` | Return links; the app may replace them with native Back |

Grouping is by source and base verse. A comment attached to several verses can appear
in several groups: de-duplicating original note ids must not erase a group's content.

Keep these fields before any sanitizing or conversion to widgets. A reader that strips
`aside`, ids, `data-*`, or namespaced attributes loses what the source controls need.

Treat ids as opaque. A note id is not a verse number, and superscripts are local
display order. Store and look up by `(content fingerprint, document path, element id)`.
The same canonical note id can occur in different EPUBs.

## 5. Import and display sequence

1. Open the EPUB with the normal package loader, keeping its resource resolver,
   navigation, spine, and metadata.
2. Load the chapter and build an id lookup; parse XHTML before flattening to styled
   text.
3. Collect the footnote asides into a note store: content, category, source,
   reference, language blocks, edition ids, links.
4. For each verse, resolve its index link and read the index's note links. Build
   verse-to-note relationships from these links, not from note headings, order, or
   guessed reference parsing.
5. De-duplicate a target within a verse, keep exported order, keep relationships from
   other verses to the same note.
6. Build the display tree from the base verses; remove the extracted note section so
   thousands of notes never enter main pagination. Keep the parsed data separately.
7. Paginate the display tree. The exported index link may be replaced with a native
   verse action.
8. On a note request, fetch the aside from the store and render it fully in the note
   view, keeping a return position and a separate note-navigation history.

Hide asides only in recognized footnote structures, never throughout unrelated EPUBs.
If a target is unrecognized or can't be extracted, fall back to ordinary anchor
navigation rather than hiding text.

Resolve links relative to the containing document (usually `#id`, but `chapter-2.xhtml#id`
must work). Native Back should return to where the user opened the note, not to the
first backlink in the HTML.

## 6. Hebrew and mixed-language rendering

Honor each block's `dir` and language. Don't reverse Hebrew strings or the whole
chapter; let the text engine do bidi layout and Hebrew shaping. Use a font that
supports Hebrew vowel marks, generous line height, and mixed Hebrew/English text, and
test for clipped marks above and below the line. No font is embedded. Keep combining
characters and grapheme boundaries intact when measuring, selecting, highlighting, or
breaking pages.

The base text already has vowels, no cantillation, the qere first and the ketiv
bracketed after it. The reader must not swap brackets, strip vowels, or substitute
Divine names. A qere-only word can appear without a bracketed partner, and Ruth 3:12
has a written-only word with no pointed qere. Bracket contents are not commands.

Commentary can contain source footnotes, `<b>`, `<i>`, `<small>`, `<sup>`, paragraph
blocks, and `<br>`. A superscript is not necessarily a note link; identify links by
their attributes.

## 7. Translation selection and source switches

The primary translation is already chosen per verse (Metsudah, else Koren), so the
reader needs no fallback logic to display it.

**Selector:** seed it with the inline `.translation` as a real option (id from
`data-edition`, name from `data-translation-label`) and select it first. Do not add a
generic "Book default". Add alternates from the verse's index, using each aside's
`data-edition` and short `data-source`. Switching replaces only the translation body
with the alternate aside's direct English div (not the whole aside or its backlinks);
switching back restores the original. Show source names only in the selector. If the
chosen edition is missing for a verse, keep the exported default with its real
metadata; never label Koren text as Metsudah. Remember an explicit choice by edition,
otherwise use that verse's primary. For older imports without a label, resolve
`data-edition` through `credits.xhtml`.

**Commentary:** group by exact `data-source`; let users choose sources and
Hebrew/English/both. A missing English block must never hide available Hebrew; a
"both" setting shows what exists, with an optional missing-translation marker.

**Limits:** `Rashi on Genesis` and `Rashi on Ruth` are separate source names, and there
is no cross-book "Rashi" id. For a library-wide switch use an explicit mapping or add a
`data-commentator-id` in a later revision; don't split names at "on". Categories are
broad groupings, not edition identities or religious assessments. A reader switch can't
recover an edition or commentary missing from the EPUB.

## 8. Pagination, caching, reading position

| Change | Repaginate main text? |
|---|---|
| Sources shown only in the note panel | No |
| Note-panel font or language | Only the panel |
| Replace the inline English translation | Yes |
| Main font, size, line spacing, margins, viewport, text scale | Yes |
| Show or hide English in the main flow | Yes |
| Insert selected commentary inline | Yes (include sources and languages in the layout key) |

Cache chapter parsing separately from pagination. A parsed-note cache should depend on
chapter content and parser version, not font settings. A page-layout cache should
also depend on viewport, font metrics, sizes, spacing, display mode, selected
translation, and renderer version. Don't use the package identifier as a content key;
the builder can keep it after content changes. Use a content hash.

Store position as document, verse anchor, and a text position within the verse, with
page number only as a convenience; page numbers or whole-chapter offsets break after
filter, translation, or font changes. Annotation anchoring also needs language or
edition context if the shown translation can change.

## 9. Performance on the Bigme

Genesis 1's XHTML is **3,006,495 bytes** uncompressed (345 commentary asides plus
indexes and alternates); Deuteronomy 32 is **2,342,092 bytes**. Those are file sizes,
not ZIP sizes or memory needs; parsed trees and layout use much more. Avoid widgets or
layout for every note at chapter open: extract the note store, lay out the base verses,
and build requested notes on demand. Keep heavy parsing and indexing off the UI thread.
Measure chapter open, first page, peak memory, and note-open latency on the device. If
parsing is still slow, a later format revision could move notes into separate
source-specific XHTML files with cross-document links.

## 10. Device acceptance checks

| Test | Expected | Area if it fails |
|---|---|---|
| Open Ruth 3 | Hebrew and Metsudah in alternating blocks; Metsudah selected in the selector | XHTML conversion, font, bidi |
| Ruth 3:3–5 and 3:12 | Correct qere/ketiv order, no clipped vowels, read-only and written-only cases kept | Font/shaping, destructive normalization |
| Switch to Koren, then back | Different text with no prefix or suffix label; switching back restores Metsudah | Translation handling |
| Open Isaiah 40 | Koren used; provenance in metadata and credits | Translation blocks |
| Verse heading | One row, English left and Hebrew right | Heading rendering |
| Genesis 1:1 notes, Rashi 1 | Full Hebrew and English Rashi reachable | Index links, namespaces, note store |
| Ibn Ezra on Ruth 3:1 | One title and two separate Hebrew comment blocks | Grouped-note rendering |
| Return from a note | Back to the invoking verse and position | Navigation stack |
| Filter to Rashi only | Chooser shows only Rashi; the rest stays stored | Source metadata and filtering |
| Same note from different verses | Both work; Back returns to the right verse | Relationship model, de-duplication |
| Change panel source filters | Main pages stay stable | Needless layout invalidation |
| Change inline translation or font size | Main pages update; stay near the same verse | Layout cache key, saved position |
| Open Genesis 1 and Deuteronomy 32 | Device stays responsive; notes not all laid out | Eager parsing or rendering |
| Open title, contents, credits | Generic EPUB rendering still works | Over-broad Tanach parsing |
| Network off | Everything still works | Hidden network dependency |

The EPUBs pass EPUBCheck and internal anchor checks, and a browser check followed
verse → index → bilingual Rashi → back to the verse. Those do not establish
compatibility or speed on the device; the table above is the device acceptance test.

## 11. Handoff note for a reader developer

Inspect the existing EPUB import, XHTML parsing and sanitizing, link handling, bidi,
pagination, cache keys, and position code, and compare them with this guide and the
sample EPUBs. Keep working general-EPUB behavior. Add the smallest layer that indexes
footnote asides and verse relationships, takes extracted notes out of the main
pagination flow, and shows source-filtered full notes separately. Support the index
indirection, optional language blocks, real relative link targets, and
invocation-specific Back. Don't assume all commentary is English, all books share a
translation, ids are globally unique, or all chapters are small.
