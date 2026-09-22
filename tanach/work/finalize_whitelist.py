import json,re,zipfile,sqlite3,shutil
from xml.etree import ElementTree as E
from sync import ROOT
out=ROOT/'outputs'
options=json.loads((out/'commentary-whitelist-options.json').read_text(encoding='utf-8'))
p=out/'commentary-whitelist.md';text=p.read_text(encoding='utf-8')
text=text.replace('Nothing here is selected yet.','Your selections are checked below.').replace('Reply with names or choice IDs, or tick the boxes below.','This records the choices from your whitelist.')
for g in options['options']:
    if g['selected']:text=text.replace(f"- [ ] **{g['choice_id']}",f"- [x] **{g['choice_id']}")
text=text.replace('- [ ] **Direct commentary only:**','- [x] **Direct commentary only:**')
text=text.replace('Choose one of those two attachment policies.','Direct commentary only is selected.')
text=text.replace('across the nine current sample chapters','across the nine original broad sample chapters')
p.write_text(text,encoding='utf-8')
facts=[]
for p in sorted((out/'samples').glob('*.epub')):
    with zipfile.ZipFile(p) as z:
        ch=next(n for n in z.namelist() if '/chapter-' in n)
        tree=E.fromstring(z.read(ch));ns={'h':'http://www.w3.org/1999/xhtml'}
        asides=tree.findall('.//h:aside',ns)
        facts.append(dict(file=p.name,chapter_path=ch,chapter_bytes=z.getinfo(ch).file_size,asides=len(asides),commentary=sum(a.get('data-category') in ('rishon','acharon','modern') for a in asides)))
(out/'reader-contract-facts.json').write_text(json.dumps(facts,indent=2))
g=next(r for r in facts if r['file'].startswith('01-'));d=next(r for r in facts if r['file'].startswith('05-'))
p=out/'reader-compatibility.md';text=p.read_text(encoding='utf-8')
text=re.sub(r'The actual Genesis 1 XHTML is \*\*[\d,]+ bytes uncompressed\*\*, including [\d,]+ commentary asides plus indexes and alternate translations\. Deuteronomy 32 is \*\*[\d,]+ bytes\*\*\.',f"The actual Genesis 1 XHTML is **{g['chapter_bytes']:,} bytes uncompressed**, including {g['commentary']:,} commentary asides plus indexes and alternate translations. Deuteronomy 32 is **{d['chapter_bytes']:,} bytes**.",text)
text=text.replace('This guide describes the nine EPUB samples generated for the Bigme B751C.','This guide describes the nine direct-commentary whitelist EPUB samples generated for the Bigme B751C.')
p.write_text(text,encoding='utf-8')
old=json.loads((ROOT/'work/previous-build-report.json').read_text(encoding='utf-8'))
new=json.loads((out/'build-report.json').read_text(encoding='utf-8'))
db=sqlite3.connect(ROOT/'work/tanach.sqlite')
print('Notes',old['notes'],'->',new['notes'])
print('Siftei Chakhamim',db.execute("select count(*) from notes where source='Siftei Chakhamim'").fetchone()[0])
print('Connection types',db.execute('select distinct connection_type from note_refs').fetchall())
print('Jonathan Sacks',db.execute("select count(*) from notes where source like 'Covenant%' or source like 'Lessons in%' ").fetchone()[0])
print('Chapter size',g['chapter_bytes'],d['chapter_bytes'])
