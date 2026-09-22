from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'outputs/reader-compatibility.md'
s=p.read_text(encoding='utf-8')
s=s.replace('├── Rashi link 1 → full Rashi note, Hebrew + English\n                ├── Rashi link 2 → another full Rashi note','├── Rashi link → all Rashi comments for this verse, Hebrew + English')
s=s.replace('This abridged example uses actual IDs from the Genesis sample; bracketed descriptions replace the text content only:', 'This abridged example illustrates the current structure; bracketed IDs and text stand for generated values:')
s=s.replace('data-edition="[edition identifier]">','data-edition="[edition identifier]" data-primary="true" data-translation-label="Metsudah">')
s=s.replace('n-9b0aa6b4eb3783d9cbae00e2','g-[generated-group-id]')
s=s.replace('title="Rashi on Genesis 1:1:1"><sup>1</sup></a>','>Rashi on Genesis</a>')
s=s.replace('data-ref="Rashi on Genesis 1:1:1">\n  <h3>Rashi on Genesis 1:1:1</h3>', 'data-ref="Rashi on Genesis 1:1">\n  <p class="note-title">Rashi on Genesis 1:1</p>')
s=s.replace('[Full Hebrew commentary]', '<div class="comment-segment" data-note-id="[original-note-id]" data-ref="Rashi on Genesis 1:1:1">[First Hebrew comment]</div>\n    <div class="comment-segment" data-note-id="[next-note-id]" data-ref="Rashi on Genesis 1:1:2">[Second Hebrew comment]</div>')
s=s.replace('[Full English commentary]','[Separate comment-segment blocks for available English comments]')
s=s.replace('[Edition labels and backlinks]','[Backlinks]')
s=s.replace('Canonical commentary reference, such as `Rashi on Genesis 1:1:1`.','The aside carries a verse-level heading, such as `Rashi on Genesis 1:1`; each `.comment-segment` retains its original reference and `data-note-id`.')
s=s.replace('`data-source` identifies the edition.', '`data-source` supplies a short selector label; `data-edition` identifies the exact edition.')
s=s.split('## Presentation revision 4')[0]
s+='''## Presentation revision 5 — 16 September 2026

The verse heading is a single h2 with two spans: English left and Hebrew right, laid out with flex space-between and explicit per-span direction. The heading is 1.15em; verse and commentary bodies remain 1em. A literal space separates the spans even if styling is discarded. A native renderer must build one horizontal row with two independently directed labels, not concatenate strings or put each label in a separate row. Respect left-to-right page progression and no paragraph indentation.

Each commentary aside now groups one source for one base verse. Render its note-title once, without an extra segment number. Under each language, preserve every comment-segment block as a separate paragraph block, in document order. Do not synthesize headings from each segment's data-ref. Group anchors now begin g-; rebuild import and pagination caches for this revision. Original note IDs survive as data-note-id; a note spanning multiple verses may appear in multiple groups. Do not discard an entire group's segments merely because another group contains the same original note.

### Translation selector and replacement text

The EPUB cannot control native dropdown wording. The reader should seed the selector with the inline .translation block as a real option, using data-edition as its identity and data-translation-label as its display name; select it initially. Do not create a separate “Book default” option. The builder already chooses Metsudah where present, otherwise Koren. Ruth 3:1 is explicitly marked Metsudah. For older imports without the label, resolve data-edition to the matching section in credits.xhtml.

Then add alternate translation asides reached from that verse's index, using their data-edition and short data-source label. Switching should replace only the translation body with the aside's direct English div, not the entire aside or its backlinks. Show source names only in the selector, never before or after the displayed verse. Alternate asides now contain no note-title. Full edition attribution stays in credits.xhtml. Switching back to Metsudah must restore the original inline text. Default selection is per verse because availability can vary; remember explicit user choices by edition when available and otherwise use that verse's primary option.

Device acceptance checks: Ruth 3:1 initially shows Metsudah selected; Koren selects different text without any prefix/suffix label; switching back restores Metsudah; Ibn Ezra on Ruth 3:1 has one title and two separate Hebrew comment blocks; the bilingual verse heading occupies one row. Reader source code is needed to implement or verify these native UI behaviors.
'''
p.write_text(s,encoding='utf-8')
p=root/'work/package_samples.py'
s=p.read_text(encoding='utf-8').replace('Verses have larger bold headings on separate lines: English left, Hebrew right.','Verses have a compact bold heading on one row: English left, Hebrew right. Commentary is grouped by source and verse, retaining separate comment paragraphs.')
p.write_text(s,encoding='utf-8')
