import collections,json,sqlite3
from sync import ROOT
r=json.loads((ROOT/'outputs/build-report.json').read_text(encoding='utf-8'))
print('WARNINGS:',collections.Counter(x['kind'] for x in r['warnings']))
for x in r['warnings'][:12]:print(x)
print('UNRESOLVED:',len(r['unresolved_links']),collections.Counter(x['reason'] for x in r['unresolved_links']))
for x in r['unresolved_links'][:18]:print(x)
c=sqlite3.connect(ROOT/'work/tanach.sqlite')
print('Unknown licenses used',list(c.execute("select title,version_title from editions where license='unknown'"))[:20])
for row in json.loads((ROOT/'outputs/sample-coverage.json').read_text(encoding='utf-8')):
    print(row['book'],row['notes'],len(row['sources']),row['primary_translations'],row['bytes'])
