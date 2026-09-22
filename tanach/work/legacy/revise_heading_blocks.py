import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'outputs/source-selection.json'
c=json.loads(p.read_text(encoding='utf-8'))
c['preferences']['presentation'].update(style_revision=4,verse_heading='separate_h2_blocks_english_left_hebrew_right_1.35em')
p.write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8')
p=root/'outputs/reader-compatibility.md'
s=p.read_text(encoding='utf-8')
s=s.replace('Presentation revision 3','Presentation revision 4').replace('15 September 2026','16 September 2026')
s=s.replace('Each verse starts with `.verse-heading`: bold “Verse 1” on the left and “פסוק א׳” on the right, with no inline verse number.','Each verse starts with two separate h2 blocks, both `.verse-heading`: “Verse 1” on its own left-aligned line, then “פסוק א׳” on its own right-aligned line. Each heading has explicit language, direction, and inline alignment and font-size (1.35em). Preserve these blocks as separate headings; do not concatenate their text. They are deliberately larger than the 1em verse/commentary body. Keep the navigation TOC chapter-only; these headings are not nav entries.')
p.write_text(s,encoding='utf-8')
p=root/'work/package_samples.py'
s=p.read_text(encoding='utf-8').replace('Verses have bold bilingual headings: English left, Hebrew right.','Verses have larger bold headings on separate lines: English left, Hebrew right.')
p.write_text(s,encoding='utf-8')
