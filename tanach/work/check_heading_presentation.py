import re
import zipfile
import xml.etree.ElementTree as E
import sqlite3
from build import OUT, ROOT, hebrew_number, PARSHIYOT, TEHILLIM_DAILY, DAY_NAMES_EN, DAY_NAMES_HE, slug
assert [hebrew_number(n) for n in (1,10,11,15,16,30,115,176)] == ['א׳','י׳','י״א','ט״ו','ט״ז','ל׳','קט״ו','קע״ו']
ns={'h':'http://www.w3.org/1999/xhtml'}
ops='{http://www.idpf.org/2007/ops}type'
TORAH=set(PARSHIYOT)
count=0
parsha_headings=0
aliyah_headings=0
daily_headings=0
torah_seen=set()
psalms_seen=False
for path in sorted((OUT/'books').glob('*.epub')):
    with zipfile.ZipFile(path) as z:
        package=z.read('EPUB/package.opf').decode('utf-8')
        book=re.search(r'<dc:title>([^<]+)</dc:title>',package).group(1)
        nav=E.fromstring(z.read('EPUB/nav.xhtml'))
        toc_links=nav.findall('.//h:nav[@id="toc"]//h:a',ns)
        assert toc_links and all(link.get('href','').startswith('chapter-') and '#' not in link.get('href') for link in toc_links)
        # EPUB 3.3 allows exactly one nav carrying the toc semantic; the
        # Parshah/Aliyah list therefore ships as a second nav typed "other".
        toc_navs=[n for n in nav.findall('.//h:nav',ns) if 'toc' in (n.get(ops) or '').split()]
        assert len(toc_navs)==1,(path.name,len(toc_navs))
        parsha_navs=nav.findall('.//h:nav[@id="parsha-toc"]',ns)
        assert len(parsha_navs)==(1 if book in TORAH else 0),(path.name,book,len(parsha_navs))
        if book in TORAH:
            torah_seen.add(book)
            assert (parsha_navs[0].get(ops) or '').split()==['other'],(path.name,parsha_navs[0].get(ops))
            links=[a.get('href','') for a in parsha_navs[0].findall('.//h:a',ns)]
            heads=[h for h in links if '#parsha-' in h]
            assert len(heads)==len(PARSHIYOT[book]),(path.name,len(heads))
            assert len(links)==len(PARSHIYOT[book])*8,(path.name,len(links))
            assert len(set(links))==len(links),(path.name,'duplicate parshah link')
            assert all(re.fullmatch(r'chapter-\d+\.xhtml#(?:parsha|aliyah)-\S+',h) for h in links),links[:3]
            for parsha in PARSHIYOT[book]:
                ps=slug(parsha['name_en'])
                source=z.read(f'EPUB/chapter-{parsha["start"][0]}.xhtml').decode('utf-8')
                match=re.search(r'<h1 class="parsha-heading" id="parsha-%s"[^>]*>.*?</h1>'%re.escape(ps),source)
                assert match,(path.name,ps)
                spans=re.findall(r'<span lang="(\w+)"[^>]*dir="(\w+)"',match.group(0))
                assert spans==[('en','ltr'),('he','rtl')],(path.name,ps,spans)
                for n,(a_ch,a_v) in enumerate(parsha['aliyot'],1):
                    source=z.read(f'EPUB/chapter-{a_ch}.xhtml').decode('utf-8')
                    match=re.search(r'<h2 class="aliyah-heading" id="aliyah-%s-%d"[^>]*>.*?</h2>'%(re.escape(ps),n),source)
                    assert match,(path.name,ps,n)
                    assert 'font-size:1.15em' in match.group(0),(path.name,ps,n)
        tehillim_navs=nav.findall('.//h:nav[@id="tehillim-toc"]',ns)
        assert len(tehillim_navs)==(1 if book == 'Psalms' else 0),(path.name,book,len(tehillim_navs))
        if book == 'Psalms':
            psalms_seen=True
            assert (tehillim_navs[0].get(ops) or '').split()==['other'],(path.name,tehillim_navs[0].get(ops))
            links=[a.get('href','') for a in tehillim_navs[0].findall('.//h:a',ns)]
            day_links=[h for h in links if '#tehillim-day-' in h]
            assert len(day_links)==30,(path.name,len(day_links))
            assert len(set(links))==len(links),(path.name,'duplicate tehillim link')
            assert all(re.fullmatch(r'chapter-\d+\.xhtml(?:#(?:tehillim-day-\d+|v-psalms-\d+-\d+))?',h) for h in links),links[:3]
            for n in range(1, 31):
                day=TEHILLIM_DAILY[n-1]
                ch, v=day['start']
                source=z.read(f'EPUB/chapter-{ch}.xhtml').decode('utf-8')
                match=re.search(r'<h1 class="tehillim-day-heading" id="tehillim-day-%d"[^>]*>.*?</h1>'%n,source)
                assert match,(path.name,n)
                assert DAY_NAMES_EN[n-1] in match.group(0),(path.name,n)
                assert DAY_NAMES_HE[n-1] in match.group(0),(path.name,n)
                spans=re.findall(r'<span lang="(\w+)"[^>]*dir="(\w+)"',match.group(0))
                assert spans==[('en','ltr'),('he','rtl')],(path.name,n,spans)
            # Psalm 119 carries two day headings (Days 25/26 share the file).
            source119=z.read('EPUB/chapter-119.xhtml').decode('utf-8')
            assert source119.count('tehillim-day-25')>=1 and source119.count('tehillim-day-26')>=1,(path.name,'psalm 119 split')
        for name in z.namelist():
            if '/chapter-' not in name: continue
            source=z.read(name)
            if book in TORAH:
                parsha_headings+=source.count(b'class="parsha-heading"')
                aliyah_headings+=source.count(b'class="aliyah-heading"')
                assert b'tehillim-day-heading' not in source,(path.name,name)
            elif book == 'Psalms':
                daily_headings+=source.count(b'class="tehillim-day-heading"')
                assert b'parsha-heading' not in source and b'aliyah-heading' not in source,(path.name,name)
            else:
                assert b'parsha-heading' not in source and b'aliyah-heading' not in source,(path.name,name)
                assert b'tehillim-day-heading' not in source,(path.name,name)
            tree=E.fromstring(source)
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
# The five books of the Torah carry both heading families, Psalms carries
# the daily headings, no others do.
assert torah_seen==TORAH,(torah_seen,TORAH)
assert parsha_headings==54,(parsha_headings,)
assert aliyah_headings==378,(aliyah_headings,)
assert psalms_seen,(psalms_seen,)
assert daily_headings==30,(daily_headings,)
print(f'PASS: {count} bilingual verse headings; 54 parshah headings and 378 aliyah headings in the five Torah books only; 30 daily Tehillim headings in Psalms; one toc nav per book.')

