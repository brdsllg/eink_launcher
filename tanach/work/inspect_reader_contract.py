import json,sqlite3,zipfile
from xml.etree import ElementTree as E
from sync import ROOT,CACHE,fetch,key
NS={'h':'http://www.w3.org/1999/xhtml'}
c=json.loads((ROOT/'outputs/source-selection.json').read_text(encoding='utf-8'))
s=next(s for s in c['sources'] if s['title']=='Ramban on Deuteronomy')
b=next(b for b in s['available_versions'] if b['versionTitle']=='Ramban Commentary')
p=CACHE/'texts'/f"{key(b['json_url'])}.json"
if not p.exists():fetch(b['json_url'],p)
d=json.loads(p.read_text(encoding='utf-8'))
print('RAMBAN METADATA',json.dumps({k:v for k,v in d.items() if k not in ('text','schema')},ensure_ascii=False))
def nonempty(a,path=()):
    if isinstance(a,str):
        if a.strip():yield path,a
    elif isinstance(a,list):
        for i,v in enumerate(a,1):yield from nonempty(v,path+(i,))
found=list(nonempty(d['text']))
print('RAMBAN CONTENT',len(found),[(p,t[:350]) for p,t in found[:2]])
rows=[]
for p in sorted((ROOT/'outputs/samples').glob('*.epub')):
    with zipfile.ZipFile(p) as z:
        name=next(n for n in z.namelist() if '/chapter-' in n)
        t=E.fromstring(z.read(name))
        asides=t.findall('.//h:aside',NS)
        rows.append(dict(file=p.name,chapter_path=name,chapter_bytes=z.getinfo(name).file_size,asides=len(asides),commentary=sum(x.get('data-category') in ('rishon','acharon','modern') for x in asides)))
        if p.name.startswith('01-'):
            verse=t.find('.//h:section[@id="v-genesis-1-1"]',NS)
            index=t.find('.//h:aside[@id="index-genesis-1-1"]',NS)
            anchor=index.find('.//h:a[@data-source="Rashi on Genesis"]',NS)
            note=t.find('.//h:aside[@id="'+anchor.get('href')[1:]+'"]',NS)
            print('ACTUAL EXAMPLE',verse.attrib,anchor.attrib,note.attrib)
            print('RASHI BLOCKS',[(n.tag,n.attrib) for n in note if n.tag.endswith('div')])
db=sqlite3.connect(ROOT/'work/tanach.sqlite')
print('RAMBAN INCLUDED',list(db.execute("select source,count(*),sum(en<>'') from notes where source like 'Ramban%' group by source")))
(ROOT/'outputs/reader-contract-facts.json').write_text(json.dumps(rows,indent=2))
print('CHAPTER SIZES',rows)
