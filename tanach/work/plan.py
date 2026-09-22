import json, re, collections
from sync import ROOT,CACHE,key
c=json.loads((ROOT/'outputs/source-selection.json').read_text(encoding='utf-8'))
catalog=json.loads((CACHE/'books.json').read_text(encoding='utf-8'))['books']
target=set(c['preferences']['book_order'])
def parent_books(title,seen=frozenset()):
    if title in c['preferences']['book_order']:return {title}
    if title in seen:return set()
    p=CACHE/'schemas'/f'{key(title)}.json'
    if not p.exists():return set()
    d=json.loads(p.read_text(encoding='utf-8'))
    result=set()
    for b in d.get('base_text_titles',[]):
        result.update(parent_books(b['en'] if isinstance(b,dict) else b,seen|{title}))
    return result
chosen=[]
unavailable=[]
for s in c['sources']:
    if s['status']!='include':continue
    p=CACHE/'schemas'/f"{key(s['title'])}.json"
    if not p.exists():
        unavailable.append(s['title']);continue
    d=json.loads(p.read_text(encoding='utf-8'))
    bases=[b['en'] if isinstance(b,dict) else b for b in d.get('base_text_titles',[])]
    if s['category']=='Modern Commentary on Tanakh' or not bases or parent_books(s['title'])&target:
        chosen.append(s)
plan=[]
for b in catalog:
    if b['title'] in target and b['versionTitle']=='Tanach with Nikkud':
        plan.append(dict(b,role='hebrew'))
for t in c['translations']:
    if t['status']=='include':
        plan.extend(dict(b,role='translation') for b in t['editions'] if b['title'] in target)
excluded=[]
for s in chosen:
    for b in s['available_versions']:
        title=b['versionTitle']
        override=s.get('edition_decisions',{}).get(b['json_url'],{}).get('status')
        if override=='exclude' or override=='pending':continue
        if override=='include':
            plan.append(dict(b,role='commentary',source_category=s['category'],sort_order=s['sort_order']));continue
        if title=='merged':continue
        if b['language'] not in ('English','Hebrew'):continue
        if re.search(r'\[(?:[a-z]{2,3})\]',title,re.I) or any(x in title.lower() for x in ('portuguese','spanish','french','german','judeo','yiddish')):
            excluded.append(dict(b,reason='non-target language'));continue
        if b['language']=='English' and (title in ('Sefaria Community Translation','Wikisource','Wikisource Mikraot Gedolot','Corrected Rashi (English) ') or 'JPS' in title):
            excluded.append(dict(b,reason='unreviewed commentary translation provenance'));continue
        if b['language']=='English' and not any(x.lower() in title.lower() for x in (
            'Metsudah','Mike Feuer','Eliyahu Munk','Judaica Press','YU Torah','Rosenbaum',
            'Strickman','Chavel','Torah miTzion','Etzion VBM','VBM Torah','Maggid',
            'Orthodox Union','OU Press','Jachter','Redeeming Relevance','Isaac Levy')):
            excluded.append(dict(b,reason='pending user review of commentary translator'));continue
        plan.append(dict(b,role='commentary',source_category=s['category'],sort_order=s['sort_order']))
(CACHE/'download-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
(CACHE/'excluded-editions.json').write_text(json.dumps(excluded,ensure_ascii=False,indent=2),encoding='utf-8')
print('Full-build source candidates:',len(chosen),'download editions:',len(plan),'missing schemas:',unavailable)
print('English commentary editions:')
for title, count in collections.Counter(b['versionTitle'] for b in plan if b['role']=='commentary' and b['language']=='English').most_common():
    print(count,title)
