import json,zipfile,re
from xml.etree import ElementTree as E
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
ns={'h':'http://www.w3.org/1999/xhtml','o':'http://www.idpf.org/2007/opf'}
for path in (ROOT/'outputs/samples').glob('*.epub'):
    with zipfile.ZipFile(path) as z:
        opf=E.fromstring(z.read('EPUB/package.opf'))
        assert opf.find('o:spine',ns).get('page-progression-direction')=='ltr'
        for name in z.namelist():
            if '/chapter-' not in name:continue
            tree=E.fromstring(z.read(name))
            assert not tree.findall('.//h:p[@class="label"]',ns)
            assert not tree.findall('.//h:h3',ns)
            for he in tree.findall('.//h:p[@class="hebrew"]',ns):assert he.get('dir')=='rtl'
            notes=tree.findall('.//h:aside[@class="commentary-note"]',ns)
            assert notes
            for note in notes:assert note.find('h:p[@class="note-title"]',ns) is not None
        assert b'License:' in z.read('EPUB/credits.xhtml')
print('All nine: LTR page progression, RTL Hebrew, no inline credit labels, small commentary titles, credits retained.')

p=ROOT/'work/package_samples.py';s=p.read_text(encoding='utf-8')
s=s.replace('Chapter navigation and RTL page progression.','Chapter navigation and left-to-right page progression; Hebrew text remains RTL.')
s=s.replace("    '- Chapter navigation", "    '- Source credits appear only at the end. Verses are larger; commentary has small headings, smaller text and an inset rule.',\n    '- Chapter navigation")
p.write_text(s,encoding='utf-8')
p=ROOT/'outputs/reader-compatibility.md';s=p.read_text(encoding='utf-8')
s=s.replace('`page-progression-direction="rtl"`','`page-progression-direction="ltr"`')
s=s.replace('| `.label` | Visible source/edition attribution, not part of the verse text. Keep it associated with the right content. |','| Credits | Visible edition attribution is in credits.xhtml only. Retain the source and edition data attributes without adding labels to every verse or note. |')
s=s.replace('display its real source label','retain its real source metadata')
s=s.replace('update the text, provenance, and visible label together','update the text and provenance together; show its short name in the translation chooser if needed')
s=s.replace('Koren appears with its own label.','Koren is used; its provenance remains in metadata and end credits.')
s=s.replace('Small font', 'Small font')
s+='\n## Presentation revision 2 — 15 September 2026\n\nPages progress left-to-right. Hebrew blocks retain `dir="rtl"`. Source and edition credits are shown only at the end, with attribution retained in data attributes. The translation chooser uses short edition names. Commentary asides have `class="commentary-note"`; their headings are plain paragraphs with `class="note-title"`, not h3 headings. Main Hebrew verses are 1.65em and English translations 1.13em; commentary Hebrew is 1.08em and English .95em, with .8em headings and an inset border. These relative sizes describe the EPUB stylesheet. A custom renderer should preserve that hierarchy if it replaces publisher CSS.\n'
p.write_text(s,encoding='utf-8')
