import unittest,re,sqlite3,json
from xml.etree import ElementTree as ET
from build import hebrew,clean,parse_address,in_range,natural,ROOT,CONFIG

class PipelineTests(unittest.TestCase):
    def test_qere_and_maqaf(self):
        got,pairs=hebrew('עַל־במותי [בָּמֳתֵי] אָרֶץ','Deuteronomy 32:13')
        self.assertEqual(pairs,[('במותי','בָּמֳתֵי')])
        self.assertIn('עַל־<span class="qere">בָּמֳתֵי</span>',got)
        self.assertIn('[במותי]',got)
    def test_qere_only_does_not_consume_preceding_word(self):
        got,_=hebrew('תֹּאמְרִי [אֵלַי] אֶעֱשֶׂה','Ruth 3:5')
        self.assertEqual(got,'תֹּאמְרִי אֵלַי אֶעֱשֶׂה')
    def test_multiword_qere_stays_grouped(self):
        got,pairs=hebrew('מִימִינוֹ אשדת [אֵשׁ] [דָּת] לָמוֹ','Deuteronomy 33:2')
        self.assertEqual(pairs,[('אשדת','אֵשׁ דָּת')])
        self.assertIn('<span class="qere">אֵשׁ דָּת</span> <span class="ketiv">[אשדת]</span>',got)
    def test_maqaf_ketiv_is_recognized(self):
        got,pairs=hebrew('וְלַשְׁבִּית ענוי־[עֲנִיֵּי־] אָרֶץ','Amos 8:4')
        self.assertEqual(pairs,[('ענוי־','עֲנִיֵּי־')])
        self.assertIn('<span class="qere">עֲנִיֵּי־</span> <span class="ketiv">[ענוי־]</span>',got)
    def test_ketiv_only(self):
        got,_=hebrew('כִּי אם גֹאֵל','Ruth 3:12')
        self.assertEqual(got,'כִּי [אם] גֹאֵל')
    def test_qere_source_evidence(self):
        xml=ET.parse(ROOT/'work/cache/ruth-source.xml')
        self.assertIn('אם',[n.text for n in xml.findall('.//k')])
        self.assertIn('שמלתך',[n.text for n in xml.findall('.//k')])
    def test_qere_only_bracket_is_retained_without_brackets(self):
        got,pairs=hebrew('כִּי [שָׁם]','Genesis 1:1')
        self.assertEqual(pairs,[])
        self.assertEqual(got,'כִּי שָׁם')
    def test_ranges(self):
        self.assertEqual(parse_address('Rashi on Genesis 1:1:2-4'),('Rashi on Genesis',(1,1,2),(1,1,4)))
        self.assertTrue(in_range((2,1),(1,31),(2,3)))
        self.assertFalse(in_range((2,4),(1,31),(2,3)))
        self.assertTrue(in_range((1,5),(1,),(1,)))
    def test_html(self):
        s=clean('<b>Text<i>nested</b><script>bad()</script>& more<br><img src=x onerror=x>')
        self.assertNotIn('bad',s);self.assertNotIn('onerror',s)
        self.assertEqual(''.join(ET.fromstring('<div>'+s+'</div>').itertext()),'Textnested& more')
    def test_numeric_order(self):
        self.assertEqual(sorted(['Rashi 1:1:10','Rashi 1:1:2'],key=natural),['Rashi 1:1:2','Rashi 1:1:10'])
    def test_database_invariants(self):
        c=sqlite3.connect(ROOT/'work/tanach.sqlite')
        count=c.execute('select count(*) from verses').fetchone()[0]
        self.assertEqual(count,23206)
        self.assertEqual(c.execute('select count(distinct book) from verses').fetchone()[0],39)
        missing=c.execute('select count(*) from verses v where not exists (select 1 from translations t where t.book=v.book and t.chapter=v.chapter and t.verse=v.verse and t.is_primary=1)').fetchone()[0]
        self.assertEqual(missing,2)
        self.assertEqual(c.execute('select count(*) from translations where is_primary=1').fetchone()[0],count-missing)
        self.assertFalse(c.execute('select book,chapter,verse from translations group by book,chapter,verse having sum(is_primary)<>1').fetchall())
        self.assertFalse(c.execute('select r.note_id from note_refs r left join notes n on n.id=r.note_id where n.id is null').fetchall())
        for book,ch,v,eid in c.execute('select book,chapter,verse,edition from translations where is_primary=1'):
            name=c.execute('select version_title from editions where id=?',(eid,)).fetchone()[0]
            self.assertTrue('Metsudah' in name or name=='The Koren Jerusalem Bible')
        allowed={s['title'] for s in CONFIG['sources'] if s['status']=='include'}
        self.assertTrue({r[0] for r in c.execute('select distinct source from notes')}<=allowed)
        if CONFIG['preferences'].get('attachment_policy')=='direct_only':
            self.assertTrue({r[0] for r in c.execute('select distinct connection_type from note_refs')}<={'schema','commentary','Commentary'})
            self.assertGreater(c.execute("select count(*) from notes where source='Siftei Chakhamim'").fetchone()[0],0)
        else:
            self.assertTrue(c.execute("select count(*) from notes where source like 'Covenant and Conversation%' ").fetchone()[0]>0)

if __name__=='__main__':unittest.main()
