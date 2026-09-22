import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'outputs/source-selection.json'
c=json.loads(p.read_text(encoding='utf-8'))
c['preferences']['presentation'].update(style_revision=3,verse_emphasis='same_size_as_commentary',commentary_style='flush_with_small_title',verse_heading='bilingual_english_left_hebrew_right')
p.write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8')
p=root/'work/package_samples.py'
s=p.read_text(encoding='utf-8').replace('Verses are larger; commentary has small headings, smaller text and an inset rule.','Verses have bold bilingual headings: English left, Hebrew right. Verse and commentary text use equal sizes, without indentation.')
p.write_text(s,encoding='utf-8')
p=root/'outputs/reader-compatibility.md'
s=p.read_text(encoding='utf-8').split('## Presentation revision 2')[0]
s+='''## Presentation revision 3 — 15 September 2026

Pages progress left-to-right; Hebrew blocks retain `dir="rtl"`. Each verse starts with `.verse-heading`: bold “Verse 1” on the left and “פסוק א׳” on the right, with no inline verse number. Both languages of verse and commentary body text use 1em, with no paragraph indentation or commentary inset. Commentary titles remain small `.note-title` paragraphs.

Primary `.translation` blocks carry only an opaque `data-edition` identifier, not `data-source`. Resolve that identifier against the matching section in credits.xhtml if source information is needed. Do not append edition names or attribution labels to verse text. Source names remain available in the notes/alternate-translation chooser; full publication credits belong on the final credits page. These rules supersede older illustrative markup above. If the reader replaces EPUB styling, preserve the bilingual heading, equal body sizes and flush alignment explicitly.
'''
p.write_text(s,encoding='utf-8')
