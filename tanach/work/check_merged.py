import json
from sync import ROOT,CACHE,fetch,key
c=json.loads((ROOT/'outputs/source-selection.json').read_text(encoding='utf-8'))
s=next(s for s in c['sources'] if s['title']=='Steinsaltz on Genesis')
for b in s['available_versions']:
    p=CACHE/'texts'/f"{key(b['json_url'])}.json"
    fetch(b['json_url'],p)
    d=json.loads(p.read_text(encoding='utf-8'))
    print({k:v for k,v in d.items() if k!='text'})
    print('TEXT START',str(d['text'])[:300])
