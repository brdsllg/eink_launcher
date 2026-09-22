import collections,json,re,sqlite3
from sync import ROOT,CACHE
out=ROOT/'outputs'
config=json.loads((out/'source-selection.json').read_text(encoding='utf-8'))
books=config['preferences']['book_order']+['Torah','Tanakh','Bereishit','Shemot','Vayikra','Bamidbar','Devarim']
db=sqlite3.connect(ROOT/'work/tanach.sqlite')
counts=dict(db.execute('select source,count(*) from notes group by source'))
groups={}
for s in config['sources']:
    if s['status']!='include':continue
    title=s['title'];versions=s['available_versions']
    cats=versions[0]['categories'] if versions else []
    name=title
    for book in sorted(books,key=len,reverse=True):
        if name.endswith(' on '+book):name=name[:-len(' on '+book)];break
    if 'Jonathan Sacks' in cats:name='Jonathan Sacks — listed collections'
    elif 'Avraham Remer' in cats:name='Avraham Remer — Joshua, Judges and Samuel'
    elif title.startswith('Redeeming Relevance;'):name='Redeeming Relevance'
    elif title.startswith('Steinsaltz on '):name='Steinsaltz commentary'
    elif title=='Ralbag Ruth':name='Ralbag'
    elif title.startswith('Gur Aryeh on '):name='Gur Aryeh'
    g=groups.setdefault(name,dict(name=name,categories=[],titles=[],sample_notes=0,in_samples=False))
    g['titles'].append(title);g['sample_notes']+=counts.get(title,0)
    g['in_samples']=g['in_samples'] or title in counts
    if s['category'] not in g['categories']:g['categories'].append(s['category'])
common=['Rashi','Ramban','Ibn Ezra','Sforno','Rashbam','Radak','Metzudat David','Metzudat Zion','Malbim','Malbim Beur Hamilot','Ralbag','Ralbag Beur HaMilot','Abarbanel','Or HaChaim',"Ba'al HaTurim","Kitzur Ba'al HaTurim",'Kli Yakar','Haamek Davar','Chizkuni',"Da'at Zekenim"]
ordered=[groups[n] for n in common if n in groups]+[g for n,g in sorted(groups.items()) if n not in common]
for i,g in enumerate(ordered,1):g['choice_id']=f'C{i:03d}';g['selected']=False
(out/'commentary-whitelist-options.json').write_text(json.dumps(dict(status='awaiting_user_whitelist',options=ordered),ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# Choose your Tanach commentary whitelist','',
    'Reply with names or choice IDs, or tick the boxes below. Nothing here is selected yet. Previous exclusions remain excluded. These are commentary works/collections, not competing English translation editions. Selecting Rashi, for example, selects its book-specific entries together; it does not require selecting every English translation of Rashi.','',
    '“In samples” means at least one note is present across the nine current sample chapters. A blank sample presence does not establish that the commentary has no text elsewhere. The number is distinct stored notes across the samples, not word count, importance, completeness, or predicted final size.','',
    '## Familiar verse-commentary choices','']
for g in ordered[:len([n for n in common if n in groups])]:
    lines.append(f"- [ ] **{g['choice_id']} — {g['name']}** — {g['sample_notes']:,} notes in samples" if g['in_samples'] else f"- [ ] **{g['choice_id']} — {g['name']}** — not in current samples")
lines+=['','## Other previously eligible works and collections','']
for g in ordered[len([n for n in common if n in groups]):]:
    presence=f"{g['sample_notes']:,} notes in samples" if g['in_samples'] else 'not in current samples; export availability must be checked'
    lines.append(f"- [ ] **{g['choice_id']} — {g['name']}** — {presence}")
lines+=['','## One separate choice that affects size','',
    '- [ ] **Direct commentary only:** attach the selected works’ verse-addressed commentary and explicit commentary links; omit broad cross-citation/essay links. This is the suggested starting point for a smaller study edition.',
    '- [ ] **Also include linked discussions:** include relevant linked essays and broader discussions from the selected works. Some can be long even when only one verse is cited.','',
    'Choose one of those two attachment policies. Either can retain the full text of every included comment; neither requires summarizing the commentary. A commentator whitelist and an attachment policy are separate controls.','',
    '## Group contents','',
    'The following shows the exact Sefaria titles behind grouped choices. You can narrow a group if you want only some of its works.','']
for g in ordered:
    if len(g['titles'])>1:
        lines.append(f"- **{g['choice_id']} — {g['name']}:** "+'; '.join(g['titles']))
lines+=['','## Reader guide','',
    'reader-compatibility.md explains the existing EPUB format, note parsing, source switches, pagination, caching, and device tests. Selecting fewer sources changes the content, not the required reader interface.']
(out/'commentary-whitelist.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Groups:',len(ordered),'present in samples:',sum(g['in_samples'] for g in ordered))
print([(g['choice_id'],g['name']) for g in ordered[:20]])
