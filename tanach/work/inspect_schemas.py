import json
from sync import CACHE,key
for title in ('Rashi on Genesis','Birkat Asher on Torah','Covenant and Conversation; Genesis; The Book of the Beginnings','Malbim on Psalms'):
    p=CACHE/'schemas'/f'{key(title)}.json'
    if p.exists():
        d=json.loads(p.read_text(encoding='utf-8'))
        print(json.dumps({k:d.get(k) for k in ('title','base_text_titles','schema')},ensure_ascii=False)[:5000])
print((CACHE/'schemas-failures.json').read_text())
links=list((CACHE/'links').glob('links*.csv'))
if links:
    with links[0].open(encoding='utf-8') as f:
        for _ in range(5):print(f.readline())
