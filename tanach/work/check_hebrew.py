import json,re
from sync import CACHE,key,ROOT
c=json.loads((ROOT/'outputs/source-selection.json').read_text(encoding='utf-8'))
for b in json.loads((CACHE/'download-plan.json').read_text(encoding='utf-8')):
    if b['role']!='hebrew':continue
    d=json.loads((CACHE/'texts'/f"{key(b['json_url'])}.json").read_text(encoding='utf-8'))
    for ch in c['preferences']['samples'][b['title']]:
        for v,t in enumerate(d['text'][ch-1],1):
            if '[' in t or re.search(r'(?<![\u0590-\u05ff])[\u05d0-\u05ea]{2,}(?![\u0590-\u05ff])',t):
                print(b['title'],ch,v,t)
