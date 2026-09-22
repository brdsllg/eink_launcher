import zipfile
import xml.etree.ElementTree as E
import sqlite3
from build import OUT, ROOT, hebrew_number
assert [hebrew_number(n) for n in (1,10,11,15,16,30,115,176)] == ['א׳','י׳','י״א','ט״ו','ט״ז','ל׳','קט״ו','קע״ו']
ns={'h':'http://www.w3.org/1999/xhtml'}
count=0
for path in (OUT/'books').glob('*.epub'):
    with zipfile.ZipFile(path) as z:
        nav=E.fromstring(z.read('EPUB/nav.xhtml'))
        toc_links=nav.findall('.//h:nav[@id="toc"]//h:a',ns)
        assert toc_links and all(link.get('href','').startswith('chapter-') for link in toc_links)
        for name in z.namelist():
            if '/chapter-' not in name: continue
            tree=E.fromstring(z.read(name))
            for verse in tree.findall('.//h:section[@class="verse"]',ns):
                n=int(verse.get('data-ref').rsplit(':',1)[1])
                heading=verse.find('h:h2',ns)
                assert [''.join(x.itertext()) for x in heading] == [f'Verse {n}',f'פסוק {hebrew_number(n)}']
                assert [x.get('dir') for x in heading]==['ltr','rtl']
                assert 'font-size:1.15em' in heading.get('style','')
                assert heading[0].tail==' '
                translation=verse.find('h:div[@class="translation"]',ns)
                if translation is not None:
                    assert 'data-source' not in translation.attrib
                    assert translation.get('data-translation-label')
                assert 'Koren Jerusalem Bible' not in ''.join(verse.itertext())
                assert verse.find('.//h:span[@class="verse-number"]',ns) is None
                count+=1
expected=sqlite3.connect(ROOT/'work/tanach.sqlite').execute('select count(*) from verses').fetchone()[0]
assert count==expected==23206
print(f'PASS: {count} bilingual verse headings; no inline numbers or visible Koren credits; Hebrew numeral edge cases.')
