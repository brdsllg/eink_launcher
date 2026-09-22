import json
from sync import ROOT,CACHE,key
out=ROOT/'outputs'
options=json.loads((out/'commentary-whitelist-options.json').read_text(encoding='utf-8'))
ids={f'C{i:03d}' for i in (1,2,3,4,5,6,7,8,9,11,13,15,16,17,19,30,35,61,76,83,98,14,116)}
chosen=[g for g in options['options'] if g['choice_id'] in ids]
assert len(chosen)==len(ids)
titles={t for g in chosen for t in g['titles']}
c=json.loads((out/'source-selection.json').read_text(encoding='utf-8'))
for s in c['sources']:
    s['status']='include' if s['title'] in titles else 'exclude'
    s['reason']='User commentary whitelist' if s['title'] in titles else 'Outside user commentary whitelist'
c['preferences']['commentary_whitelist']=[dict(choice_id=g['choice_id'],name=g['name']) for g in chosen]
c['preferences']['attachment_policy']='direct_only'
c['preferences']['commentary_extent']='full direct comments; no broad cross-citations or essay expansion'
(out/'source-selection.json').write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8')
options['status']='user_whitelist_applied'
for g in options['options']:g['selected']=g['choice_id'] in ids
(out/'commentary-whitelist-options.json').write_text(json.dumps(options,ensure_ascii=False,indent=2),encoding='utf-8')
(out/'selected-commentaries.md').write_text('# Selected commentaries\n\nDirect commentary only. Full text in Hebrew and available selected English editions.\n\n'+'\n'.join('- '+g['name']+' ('+g['choice_id']+')' for g in chosen)+'\n\nOr HaChaim and Siftei Chakhamim were added from the explicitly named list. Jonathan Sacks remains whitelisted, but essays linked only by general citations do not qualify under the direct-only rule. Direct supercommentary on Rashi can be attached through the parent Rashi comment.\n',encoding='utf-8')
for title in ('Siftei Chakhamim','Mizrachi','Bartenura on Torah'):
    d=json.loads((CACHE/'schemas'/f'{key(title)}.json').read_text(encoding='utf-8'))
    print(title,d.get('base_text_titles'),d.get('base_text_mapping'))
    print(str(d['schema'])[:550])
print('Selected groups',len(chosen),'individual titles',len(titles))
