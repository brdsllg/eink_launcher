import sqlite3,zipfile
import xml.etree.ElementTree as E
from build import ROOT,OUT,clean
c=sqlite3.connect(ROOT/'work/tanach.sqlite');c.row_factory=sqlite3.Row
ns={'h':'http://www.w3.org/1999/xhtml'}
seen=set();groups=0
for p in (OUT/'books').glob('*.epub'):
    with zipfile.ZipFile(p) as z:
        for name in z.namelist():
            if '/chapter-' not in name:continue
            tree=E.fromstring(z.read(name))
            for a in tree.findall('.//h:aside[@class="commentary-note"]',ns):
                groups+=1
                assert len(a.findall('h:p[@class="note-title"]',ns))==1
                for segment in a.findall('.//h:div[@class="comment-segment"]',ns):
                    nid=segment.get('data-note-id');seen.add(nid)
                    note=c.execute('select * from notes where id=?',(nid,)).fetchone()
                    assert note['source']==a.get('data-source')
                    parent=next(x for x in a if segment in list(x))
                    lang=parent.get('lang')
                    original=E.fromstring('<div>'+note[lang]+'</div>')
                    assert ''.join(original.itertext())==''.join(segment.itertext())
            for a in tree.findall('.//h:aside[@data-category="translation"]',ns):
                assert a.find('h:p[@class="note-title"]',ns) is None
                assert 'The Koren Jerusalem Bible' not in a.get('data-source','')
            if 'ruth' in p.name and name.endswith('/chapter-3.xhtml'):
                verse=tree.find('.//h:section[@id="v-ruth-3-1"]',ns)
                assert verse.find('h:div[@class="translation"]',ns).get('data-translation-label')=='Metsudah'
                ibn=tree.find('.//h:aside[@data-ref="Ibn Ezra on Ruth 3:1"]',ns)
                assert ibn is not None
                assert len(ibn.findall('h:div[@class="note-he"]/h:div',ns))==2
assert seen=={r[0] for r in c.execute('select distinct note_id from note_refs')}
print(f'PASS: {len(seen)} original notes preserved in {groups} verse/source groups; Ruth default Metsudah and two Ibn Ezra comments verified.')
