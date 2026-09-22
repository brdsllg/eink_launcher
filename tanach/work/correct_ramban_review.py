import json
from sync import ROOT,CACHE,key
p=ROOT/'outputs/source-selection.json'
c=json.loads(p.read_text(encoding='utf-8'))
s=next(s for s in c['sources'] if s['title']=='Ramban on Deuteronomy')
b=next(b for b in s['available_versions'] if b['versionTitle']=='Ramban Commentary')
d=json.loads((CACHE/'texts'/f"{key(b['json_url'])}.json").read_text(encoding='utf-8'))
s['edition_decisions'][b['json_url']]=dict(status='include',reviewed=True,version_title=d['versionTitle'],language=d['language'],license=d.get('license','unknown'),source_url=d['versionSource'],availability='empty_export',reason='Approved Ramban work; edition metadata points to Judaica Press. Export has no nonempty text. No user religious decision required.')
p.write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8')
print('Corrected Ramban edition review; no EPUB text changes needed because the export is empty.')
