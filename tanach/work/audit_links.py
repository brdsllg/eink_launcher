import json,csv,collections
from sync import ROOT,CACHE,key
c=json.loads((ROOT/'outputs/source-selection.json').read_text(encoding='utf-8'))
modern={s['title'] for s in c['sources'] if s['category']=='Modern Commentary on Tanakh' and s['status']=='include'}
counts=collections.Counter();examples=[]
for p in (CACHE/'links').glob('links*.csv'):
    with p.open(encoding='utf-8-sig',newline='') as f:
        for row in csv.DictReader(f):
            if any('Covenant' in row[x] for x in ('Text 1','Text 2')) and any(row[x] in c['preferences']['samples'] for x in ('Text 1','Text 2')):
                counts[(row['Text 1'],row['Text 2'])]+=1
                if len(examples)<6:examples.append(row)
print('Covenant links',counts.most_common(12));print(examples)
for title in ('Steinsaltz on Genesis','Malbim on I Samuel','Covenant and Conversation; Genesis; The Book of the Beginnings'):
    source=next(s for s in c['sources'] if s['title']==title)
    for b in source['available_versions']:
        p=CACHE/'texts'/f"{key(b['json_url'])}.json"
        if p.exists():
            d=json.loads(p.read_text(encoding='utf-8'));print(title,d['language'],d.get('actualLanguage'),d['versionTitle'],str(d['text'])[:150])
report=json.loads((ROOT/'outputs/build-report.json').read_text(encoding='utf-8'))
print([x for x in report['unresolved_links'] if x['source']=='Malbim on I Samuel'][:6])
