import json
from sync import CACHE,key
plan=json.loads((CACHE/'download-plan.json').read_text(encoding='utf-8'))
for b in plan:
    if b['title'] not in ('Birkat Asher on Torah','Malbim on Psalms','Covenant and Conversation; Genesis; The Book of the Beginnings','Rashi on Genesis'):continue
    p=CACHE/'texts'/f"{key(b['json_url'])}.json"
    if not p.exists():continue
    d=json.loads(p.read_text(encoding='utf-8'))
    print(d['title'],d['versionTitle'],d.get('license'), list(d.keys()))
    t=d['text']
    print('TEXT:',str(t)[:1200])
