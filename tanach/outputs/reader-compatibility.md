# Tanach EPUB reader compatibility and implementation guide

This guide describes the nine direct-commentary whitelist EPUB samples generated for the Bigme B751C. It is based on inspection of the actual ZIP contents, XHTML, metadata, and links. The reader’s source code has not been inspected, so the changes below are a contract to compare against its existing implementation, not a claim that each feature is missing.

## 1. What the reader needs to do

The files are reflowable EPUB 3 publications. A basic reader can display their chapters and follow ordinary links to chapter-end notes. The custom study experience should parse those notes into a separate store, paginate the main text, and open selected commentary in a panel or page when requested.

The EPUB carries the text, verse-to-note relationships, source names, categories, language directions, and edition identifiers. The reader supplies the interface: source switches, translation selection, note panels, and pagination. There is no executable reader code, Sefaria API dependency, or SQLite database inside the EPUB.

Recommended first implementation: keep the Hebrew and primary English translation in the reading flow; show commentary in a separate scrollable view. Add inline commentary later if wanted. Changing a commentary filter in a separate view does not require repaginating the main text.

## 2. Package layout

An example sample contains:

```text
mimetype
META-INF/container.xml
EPUB/package.opf
EPUB/nav.xhtml
EPUB/toc.ncx
EPUB/style.css
EPUB/title.xhtml
EPUB/chapter-1.xhtml
EPUB/credits.xhtml
```

Resolve the package location through `container.xml`; do not hard-code `EPUB/`. Read the package manifest for resources and the spine for reading order. `nav.xhtml` supplies navigation; `toc.ncx` is an additional legacy navigation aid, not a promise that every EPUB 2 reader will support these EPUB 3 files. The spine specifies `page-progression-direction="ltr"`. This determines page progression; individual text blocks still have their own directions. Follow the same distinction when assigning gestures.

Each current sample has one selected chapter. A future complete book can have multiple chapter documents, so keep document paths in every resolved anchor and reading position. The current samples use the “Tanach Samples” series metadata.

These packaging and structural semantics use the [EPUB specification](https://www.w3.org/TR/epub-33/). General reading-system behavior is specified separately in [EPUB Reading Systems](https://www.w3.org/TR/epub-rs-33/); a custom study panel is an application feature.

## 3. The actual verse → index → note relationship

```text
Genesis 1:1 verse
    └── “Translations & commentary” link
          └── index-genesis-1-1
                ├── alternate translation link → translation aside
                ├── Rashi link → all Rashi comments for this verse, Hebrew + English
                └── other sources and their notes
```

The verse index was added because displaying hundreds of individual links beneath a verse overwhelmed the page. The custom reader can bypass that index screen: read its links to populate a native source chooser and open the selected note directly.

All of these are real `<a>` links. Do not look only for tappable `<span>` elements or assume the verse’s first link leads directly to commentary text.

This abridged example illustrates the current structure; bracketed IDs and text stand for generated values:

```xml
<section class="verse" id="v-genesis-1-1" data-ref="Genesis 1:1">
  <p class="hebrew" lang="he" xml:lang="he" dir="rtl">
    [Hebrew verse]
  </p>
  <div class="translation" lang="en" xml:lang="en" dir="ltr"
       data-edition="[edition identifier]" data-primary="true" data-translation-label="Metsudah">
    [Primary English translation]
  </div>
  <p class="note-links">
    <a epub:type="noteref" href="#index-genesis-1-1"
       data-category="index" data-ref="Genesis 1:1">
      Translations &amp; commentary
    </a>
  </p>
</section>

<aside epub:type="footnote" id="index-genesis-1-1"
       data-category="index" data-ref="Genesis 1:1">
  [Other index content]
  <a epub:type="noteref" href="#g-[generated-group-id]"
     data-source="Rashi on Genesis" data-category="rishon"
     >Rashi on Genesis</a>
</aside>

<aside epub:type="footnote" id="g-[generated-group-id]"
       data-source="Rashi on Genesis" data-category="rishon"
       data-ref="Rashi on Genesis 1:1">
  <p class="note-title">Rashi on Genesis 1:1</p>
  <div class="note-he" lang="he" xml:lang="he" dir="rtl"
       data-editions="ed-f8f86fd0a8121ddc55e11521">
    <div class="comment-segment" data-note-id="[original-note-id]" data-ref="Rashi on Genesis 1:1:1">[First Hebrew comment]</div>
    <div class="comment-segment" data-note-id="[next-note-id]" data-ref="Rashi on Genesis 1:1:2">[Second Hebrew comment]</div>
  </div>
  <div class="note-en" lang="en" xml:lang="en" dir="ltr"
       data-editions="ed-ed203dc1b5dd8415b0480afa">
    [Separate comment-segment blocks for available English comments]
  </div>
  [Backlinks]
</aside>
```

The XHTML declares the namespaces `http://www.w3.org/1999/xhtml` and `http://www.idpf.org/2007/ops`. In an XML parser, recognize the latter namespace’s `type` attribute, not merely the literal prefix `epub`, which could change. Test its whitespace-separated tokens for `noteref` or `footnote`. If the existing HTML parser retains attributes by literal names, support its `epub:type` representation as well.

## 4. Fields the parser must retain

| Element or field | Meaning and handling |
|---|---|
| `section.verse` | One base verse. Retain its anchor and `data-ref`. |
| `.hebrew` | Already prepared source text. Preserve its inline markup and Unicode. |
| `.translation` | The default English text for this verse, with an opaque `data-edition` linking to end credits. Do not add a visible source label. |
| `a` with `epub:type="noteref"` | Resolve `href`; then inspect the target’s category. |
| Footnote aside, `data-category="index"` | Navigation to this verse’s notes and alternates, not a commentator. |
| Footnote aside, `data-category="translation"` | Alternate English translation; `data-source` supplies a short selector label; `data-edition` identifies the exact edition. |
| Footnote aside, category `rishon`, `acharon`, or `modern` | Full commentary. Group/filter using its source and category. |
| `data-ref` on commentary | The aside carries a verse-level heading, such as `Rashi on Genesis 1:1`; each `.comment-segment` retains its original reference and `data-note-id`. |
| `.note-he` and `.note-en` | Available language blocks. Either can be absent. |
| `data-editions` | Space-separated provenance identifiers. One block can cite multiple editions because the build fills missing segments from other selected editions. |
| `data-edition` | A single edition identifier on a translation. |
| Credits | Visible edition attribution is in credits.xhtml only. Retain the source and edition data attributes without adding labels to every verse or note. |
| `.backlinks` | Return links. The app can replace their presentation with native navigation. |

Preserve these fields before sanitization or document-to-widget conversion. If the existing reader strips `aside`, IDs, `data-*`, or namespaced attributes before interpretation, it will discard the information needed for source controls.

Treat IDs as opaque strings. A note ID is not a verse number, and the superscript number is local display order, not a permanent identifier. Use `(publication content fingerprint, document path, element ID)` for storage and lookup. The same canonical note ID may occur in different EPUBs.

## 5. Suggested import and display sequence

1. Open the EPUB with the existing package loader, and retain its resource resolver, navigation, spine, and metadata.
2. Load the requested chapter and build an ID lookup. Parse the XHTML before flattening it into styled text.
3. Collect the footnote asides into a note store. Retain their content, category, source, reference, language blocks, edition IDs, and links.
4. For each `section.verse`, resolve its index link and read that index’s individual note links. Build the verse-to-note relationship from these links, not from note headings, note order, or guessed reference parsing.
5. Deduplicate the same target within that verse. Preserve the exported order. Keep relationships from other verses to the same note.
6. Build a display tree for the base verses. Remove the extracted endnote section from this tree so its thousands of notes and its “Translations and commentary” heading do not enter the main pagination stream. Keep the original parsed data separately.
7. Paginate the display tree. Replace the exported index link with your preferred verse action if desired.
8. On a note request, fetch the selected aside from the note store and render its complete content in the note view. Maintain a return position and a separate note-navigation history.

Do not hide arbitrary asides throughout unrelated EPUBs. Apply this extraction to recognized footnote structures, and provide ordinary anchor navigation when a target is unrecognized or cannot be extracted. Do not hide a broken target and leave its text inaccessible.

A parser model could be:

```text
Verse
  documentPath, elementId, reference
  hebrewFragment
  primaryTranslation {editionId, sourceName, fragment}
  alternateTranslationTargets[]
  commentaryTargets[]

Note
  documentPath, elementId, kind
  sourceName?, sourceCategory?, reference?
  fullFragment
  hebrewFragment?, englishFragment?
  editionIds[]
```

Resolve links relative to the containing document. Although sample note links are usually `#id`, the resource resolver should also handle `chapter-2.xhtml#id`. Retain a backlink’s source verse even when the same note is accessible from several verses. The appropriate native Back action returns to where the user opened the note, not automatically to the first backlink in its HTML.

## 6. Hebrew and mixed-language rendering

Honor each block’s `dir` and language. Do not reverse Hebrew strings or reverse the entire chapter: Hebrew, English, digits, brackets, and citations coexist. Let the text layout engine perform bidirectional layout and Hebrew shaping.

Use a font that supports Hebrew vowel marks, adequate line height, and mixed Hebrew/English text. Test for clipped marks above and below the line. No font is embedded in these samples. Preserve combining characters and grapheme boundaries when measuring, selecting, highlighting, or breaking text across pages.

The base text already has vowels without cantillation, qere rendered first in the main text, and ketiv in brackets after it. The reader must not perform another bracket swap, remove vowel marks, or substitute Divine names. A qere-only word can appear without a bracketed partner; Ruth 3:12 has a written-only word with no pointed qere. Bracket contents are not reader commands.

Commentary can contain source footnotes, `<b>`, `<i>`, `<small>`, `<sup>`, paragraph blocks, and `<br>`. Preserve their readable content. A superscript inside the text is not necessarily an EPUB note link; identify note links by their actual attributes.

## 7. Translation selection and source switches

The current primary translation has already been chosen verse by verse: Metsudah when present, otherwise Koren. The reader can display it without implementing any fallback logic.

For user-selectable translations, combine the inline primary text and the alternate translation asides into a per-verse list. If the user’s selected edition is missing for a verse, retain the exported default and retain its real source metadata. Do not label Koren text as Metsudah or assume every edition covers every verse. When replacing the inline translation, update the text and provenance together; show its short name in the translation chooser if needed.

Group commentary by exact `data-source`. Let users select sources and Hebrew/English/both; an unavailable English block must not cause an available Hebrew note to disappear unexpectedly. A “both” setting should show what exists, with an optional missing-translation indicator.

There is a format limitation: `Rashi on Genesis` and `Rashi on Ruth` are separate source names. The samples do not contain a canonical cross-book “Rashi” family identifier. For a library-wide Rashi switch, use an explicit mapping, or add a `data-commentator-id` field in a later EPUB revision. Do not rely on splitting arbitrary names at the word “on.” Category labels are broad groupings, not edition identities or independent religious assessments.

The samples contain the selected build editions only. A reader switch cannot recover an edition or commentary absent from the EPUB. The files also do not offer every alternate translation of each commentary; commentary blocks are selected at build time with provenance preserved.

## 8. Pagination, caching, and reading position

| Change | Main text needs repagination? |
|---|---|
| Change sources shown only in the note panel | No, unless this also changes main-text layout. |
| Change note panel font or panel language | Only the note panel. |
| Replace the inline English translation | Yes. |
| Change main font, size, line spacing, margins, viewport, or text scaling | Yes. |
| Show/hide English in the main flow | Yes. |
| Insert selected commentary inline | Yes; include source and language choices in the layout key. |

Cache chapter parsing separately from pagination. A parsed-note cache should depend on publication/chapter content and the parser version, not on font settings. A page-layout cache should also depend on effective viewport, font metrics, sizes, spacing, display mode, selected translation, and renderer version. Include sorted source/language selections only when they affect the paginated content.

Do not use the package identifier alone as a content cache key. The current builder can retain that identifier after source content changes. Use a file/chapter content hash or another verified revision fingerprint.

Store reading position using a document, verse anchor, and a text position/context within that verse, with page number as a convenience. A page number or whole-chapter text offset alone is unstable after filters, translation changes, or font changes. Annotation anchoring also needs its language/edition or selected-text context if the displayed translation can change.

## 9. Performance on the Bigme

The actual Genesis 1 XHTML is **3,006,495 bytes uncompressed**, including 345 commentary asides plus indexes and alternate translations. Deuteronomy 32 is **2,342,092 bytes**. These are measured chapter sizes, not ZIP download sizes or measured RAM requirements; parsed trees and layout objects can take substantially more memory.

Avoid creating widgets and laying out every note at chapter open. Import or parse the document, extract the note store, then lay out the base verses and instantiate the requested notes on demand. In a Flutter reader, expensive parsing and indexing should not monopolize the UI thread. The particular integration depends on whether the reader uses a WebView or a native text/widget renderer.

For a WebView-based reader, a preprocessing layer can extract footnotes before the chapter is loaded for pagination. For a native renderer, perform extraction before converting nodes into the paginated spans or widgets. In both cases retain a source document/fragment store so hidden notes remain accessible.

Lazy note rendering does not eliminate the cost of decompressing and parsing a large chapter. Measure chapter opening, initial page availability, peak memory, and note-opening latency on the device. If parsing remains slow, the EPUB builder can later move notes into separate, source-specific XHTML resources with cross-document links. That would be a format revision; the current files keep notes in the chapter document.

## 10. Concrete checks for the existing reader

| Test | Expected result | Likely area to change if it fails |
|---|---|---|
| Open Ruth 3 | Hebrew and Metsudah appear in alternating blocks. | XHTML structure conversion, font, or bidi layout. |
| Inspect Ruth 3:3–5 and 3:12 | Correct qere/ketiv order, no vowel clipping, read-only and written-only cases retained. | Font/shaping or destructive text normalization. |
| Open Isaiah 40 | Koren is used; its provenance remains in metadata and end credits. | Translation-block handling. |
| Open Genesis 1:1 notes, select Rashi 1 | Full Hebrew and English Rashi are accessible. | Index-link parsing, namespaces, note store, or nested note navigation. |
| Return from that Rashi note | Return to the invoking verse and reading position. | Navigation stack / anchor restoration. |
| Enable only Rashi in the app’s source filter | The note chooser shows matching Rashi notes without deleting the rest from storage. | Source metadata retention and filtering. |
| Open a note from different linked verses | Both accesses work; Back returns to the respective invoking verse. | Relationship model and deduplication. |
| Change source filters in panel-only mode | Main pages remain stable. | Unnecessary layout invalidation. |
| Change the inline translation or font size | Main pages update; the reader stays near the same verse. | Layout cache key and persistent position. |
| Open Genesis 1 and Deuteronomy 32 | Device remains responsive; note bodies are not all laid out with the verses. | Parsing schedule and eager rendering. |
| Open a title, contents, or credits page | The existing generic EPUB renderer still handles it. | Overly broad Tanach-specific parsing. |
| Disable network access | Chapters, translations, and commentary continue to work. | Accidental dependency on external source links. |

The EPUBs have passed EPUBCheck and internal anchor checks. Browser testing also verified the path from a verse to its index, to bilingual Rashi, and back to the verse. Those checks do not establish Bigme reader compatibility; the table above is the device acceptance test.

## 11. Handoff to the reader’s developer or coding AI

Inspect the existing EPUB import, XHTML parsing/sanitization, link handling, bidi rendering, pagination, cache keys, and reading-position code. Compare them against this document and the supplied sample EPUBs. Preserve working general EPUB behavior. Implement the smallest missing layer that indexes footnote asides and verse relationships, removes extracted notes from the main pagination flow, and presents source-filtered full notes in a separate view. Support the verse index indirection, optional language blocks, actual relative link targets, and invocation-specific Back navigation. Do not assume all commentary is English, all books share a translation, IDs are globally unique, or all chapters are small. Validate with the test table before adding optional inline-commentary pagination.

Exact patches require the reader repository or the relevant parser, renderer, link, pagination, and cache files. None of those app files were changed as part of this guide.

## Presentation revision 5 — 16 September 2026

The verse heading is a single h2 with two spans: English left and Hebrew right, laid out with flex space-between and explicit per-span direction. The heading is 1.15em; verse and commentary bodies remain 1em. A literal space separates the spans even if styling is discarded. A native renderer must build one horizontal row with two independently directed labels, not concatenate strings or put each label in a separate row. Respect left-to-right page progression and no paragraph indentation.

Each commentary aside now groups one source for one base verse. Render its note-title once, without an extra segment number. Under each language, preserve every comment-segment block as a separate paragraph block, in document order. Do not synthesize headings from each segment's data-ref. Group anchors now begin g-; rebuild import and pagination caches for this revision. Original note IDs survive as data-note-id; a note spanning multiple verses may appear in multiple groups. Do not discard an entire group's segments merely because another group contains the same original note.

### Translation selector and replacement text

The EPUB cannot control native dropdown wording. The reader should seed the selector with the inline .translation block as a real option, using data-edition as its identity and data-translation-label as its display name; select it initially. Do not create a separate “Book default” option. The builder already chooses Metsudah where present, otherwise Koren. Ruth 3:1 is explicitly marked Metsudah. For older imports without the label, resolve data-edition to the matching section in credits.xhtml.

Then add alternate translation asides reached from that verse's index, using their data-edition and short data-source label. Switching should replace only the translation body with the aside's direct English div, not the entire aside or its backlinks. Show source names only in the selector, never before or after the displayed verse. Alternate asides now contain no note-title. Full edition attribution stays in credits.xhtml. Switching back to Metsudah must restore the original inline text. Default selection is per verse because availability can vary; remember explicit user choices by edition when available and otherwise use that verse's primary option.

Device acceptance checks: Ruth 3:1 initially shows Metsudah selected; Koren selects different text without any prefix/suffix label; switching back restores Metsudah; Ibn Ezra on Ruth 3:1 has one title and two separate Hebrew comment blocks; the bilingual verse heading occupies one row. Reader source code is needed to implement or verify these native UI behaviors.
