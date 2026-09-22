"""Offline, range-aware full Tanach EPUB builder (Python standard library)."""
import collections, csv, hashlib, html, json, re, sqlite3, sys, zipfile
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree as ET
from sync import ROOT,CACHE,key
OUT=ROOT/'outputs'
CONFIG=json.loads((OUT/'source-selection.json').read_text(encoding='utf-8'))
BOOK_ORDER=CONFIG['preferences']['book_order']
TARGET_BOOKS=set(BOOK_ORDER)
DIRECT_ONLY=CONFIG['preferences'].get('attachment_policy')=='direct_only'
PLAN=json.loads((CACHE/'download-plan.json').read_text(encoding='utf-8'))
WARN=[]

def slug(s):return re.sub('[^a-z0-9]+','-',s.lower()).strip('-')
def natural(s):return tuple(int(x) if x.isdigit() else x for x in re.split(r'(\d+)',s))
def e(s):return html.escape(str(s),quote=True)
def strip_trop(s):return re.sub('[\u0591-\u05af]','',s)

class SafeHTML(HTMLParser):
    """Keep readable formatting, never active content or remote media."""
    allowed={'b','strong','i','em','small','sup','sub','span','p','div','br','ul','ol','li','blockquote'}
    def __init__(self):super().__init__(convert_charrefs=True);self.out=[];self.stack=[];self.skip=0
    def handle_starttag(self,t,a):
        if t in ('script','style'):self.skip+=1;return
        if self.skip or t not in self.allowed:return
        attrs=dict(a); extra=''
        if attrs.get('class')=='footnote':extra=' class="embedded-footnote"'
        self.out.append('<'+t+extra+(' />' if t=='br' else '>'))
        if t!='br':self.stack.append(t)
    def handle_endtag(self,t):
        if t in ('script','style'):self.skip=max(0,self.skip-1);return
        if self.skip or t not in self.stack:return
        while self.stack:
            end=self.stack.pop();self.out.append('</'+end+'>')
            if end==t:break
    def handle_data(self,d):
        if not self.skip:self.out.append(e(d))
    def finish(self,s):
        self.feed(s)
        while self.stack:self.out.append('</'+self.stack.pop()+'>')
        return ''.join(self.out)

def clean(s):return SafeHTML().finish(s)
def plaintext(s):return html.unescape(re.sub('<[^>]+>','',s)).strip()

def hebrew(s,ref):
    s=strip_trop(s)
    # The export has unpointed ketiv before one or more [pointed qere] groups.
    # A maqaf can join either side, and multiword qere is sometimes split over
    # adjacent bracket groups (for example, אשדת [אֵשׁ] [דָּת]).
    pattern=(
        r'(?<![\u05b0-\u05bd\u05bf\u05c1\u05c2\u05c7\u05d0-\u05ea])'
        r'([\u05d0-\u05ea]+(?:[ \u05be][\u05d0-\u05ea]+)*\u05be?)\s*'
        r'((?:\[[^\[\]]+\]\s*)+)'
    )
    pairs=[];gaps=[]
    def swap(m):
        k,groups=m.groups()
        # Rendering order is pointed qere first, bracketed ketiv after, and
        # the source whitespace that followed the brackets is re-emitted so
        # the ketiv span is never glued to the next word.
        gap=re.search(r'\s*\Z',groups).group()
        q=' '.join(x.strip() for x in re.findall(r'\[([^\[\]]+)\]',groups))
        q=re.sub(r'\u05be\s+', '\u05be', q)
        pairs.append((k,q));gaps.append(gap);return f'§Q{len(pairs)-1}§'
    s=re.sub(pattern,swap,s)
    # A remaining bracket contains qere without a separately encoded ketiv.
    if '[' in s:
        WARN.append(dict(kind='qere_without_ketiv',ref=ref,text=s))
        s=re.sub(r'\[([^\[\]]+)\]',lambda m:m.group(1),s)
    if ref=='Ruth 3:12':
        assert ' אם ' in s
        s=s.replace(' אם ',' [אם] ')
    rendered=e(s)
    for i,((k,q),gap) in enumerate(zip(pairs,gaps)):
        rendered=rendered.replace(f'§Q{i}§',f'<span class="qere">{e(q)}</span> <span class="ketiv">[{e(k)}]</span>'+gap)
    return rendered,pairs


def leaves(node,path=()):
    if 'nodes' not in node:
        yield path,node
    else:
        for child in node['nodes']:
            name='' if child.get('default') else child.get('title',child.get('key',''))
            yield from leaves(child,path+((name,) if name else ()))

def arrays(value,path=()):
    if isinstance(value,dict):
        for k,v in value.items():yield from arrays(v,path+((k,) if k else ()))
    else:yield path,value

def segments(a,loc=()):
    if isinstance(a,str):
        if plaintext(a):yield loc,a
    elif isinstance(a,list):
        for i,v in enumerate(a,1):yield from segments(v,loc+(i,))

def rank(d):
    v=d['versionTitle']
    return (1000 if 'Metsudah' in v else 0)+float(d.get('priority') or 0)+(10 if d.get('status')=='locked' else 0)

def parse_address(ref):
    m=re.fullmatch(r'(.*?) (\d+(?::\d+)*)(?:-(\d+(?::\d+)*))?',ref)
    if not m:return ref,(),()
    prefix,start,end=m.groups();start=tuple(map(int,start.split(':')))
    if end:
        end=tuple(map(int,end.split(':')));end=start[:len(start)-len(end)]+end
    else:end=start
    return prefix,start,end

def in_range(loc,start,end):
    if not start:return True
    n=len(start)
    return start<=loc[:n]<=end

def main():
    dbpath=ROOT/'work/tanach.sqlite'
    conn=sqlite3.connect(dbpath)
    conn.executescript('''
    DROP TABLE IF EXISTS verses; DROP TABLE IF EXISTS translations; DROP TABLE IF EXISTS notes;
    DROP TABLE IF EXISTS note_refs; DROP TABLE IF EXISTS editions;
    CREATE TABLE verses(book TEXT,chapter INT,verse INT,original TEXT,hebrew TEXT,hebrew_edition TEXT,PRIMARY KEY(book,chapter,verse));
    CREATE TABLE translations(book TEXT,chapter INT,verse INT,edition TEXT,text TEXT,is_primary INT,PRIMARY KEY(book,chapter,verse,edition));
    CREATE TABLE notes(id TEXT PRIMARY KEY,source TEXT,ref TEXT,category TEXT,sort_order INT,he TEXT,en TEXT,he_edition TEXT,en_edition TEXT);
    CREATE TABLE note_refs(note_id TEXT,book TEXT,chapter INT,verse INT,connection_type TEXT,original_base_ref TEXT,original_note_ref TEXT,UNIQUE(note_id,book,chapter,verse,connection_type,original_base_ref,original_note_ref));
    CREATE TABLE editions(id TEXT PRIMARY KEY,title TEXT,version_title TEXT,language TEXT,license TEXT,source_url TEXT,export_url TEXT,sha256 TEXT);
    ''')
    docs=[];edition_info={};schema_cache={};chapters_by_book={}
    source_policy={s['title']:s for s in CONFIG['sources']}
    translation_policy={t['version_title']:t for t in CONFIG['translations']}
    for b in PLAN:
        if b['role']=='commentary':
            policy=source_policy[b['title']]
            if policy['status']!='include' or policy.get('edition_decisions',{}).get(b['json_url'],{}).get('status') in ('exclude','pending'):continue
        if b['role']=='translation' and translation_policy[b['versionTitle']]['status']!='include':continue
        path=CACHE/'texts'/f"{key(b['json_url'])}.json"
        assert path.exists(),f'Missing cached edition: {b}'
        d=json.loads(path.read_text(encoding='utf-8'))
        if d.get('actualLanguage',d['language']) not in ('en','he'):
            WARN.append(dict(kind='language_mismatch',title=b['title'],edition=d['versionTitle']));continue
        if re.search(r'(^test\b|\btest$|abbreviated|summary)',d['versionTitle'],re.I):
            WARN.append(dict(kind='test_or_abridged_edition',title=b['title'],edition=d['versionTitle']));continue
        eid='ed-'+key(b['json_url'])
        meta=json.loads(path.with_suffix('.json.meta.json').read_text())
        info=(eid,d['title'],d['versionTitle'],d['language'],d.get('license','unknown'),d.get('versionSource',''),b['json_url'],meta['sha256'])
        conn.execute('INSERT INTO editions VALUES(?,?,?,?,?,?,?,?)',info)
        edition_info[eid]=dict(zip(('id','title','version_title','language','license','source_url','export_url','sha256'),info))
        docs.append((b,d,eid))
        if b['role']=='hebrew':
            assert b['title'] in TARGET_BOOKS
            assert isinstance(d.get('text'),list) and d['text'],('Missing Hebrew chapters',b['title'])
            chapters_by_book[b['title']]=list(range(1,len(d['text'])+1))
            for ch,chapter in enumerate(d['text'],1):
                for v,t in enumerate(chapter,1):
                    rendered,pairs=hebrew(t,f"{b['title']} {ch}:{v}")
                    conn.execute('INSERT INTO verses VALUES(?,?,?,?,?,?)',(b['title'],ch,v,t,rendered,eid))
    assert set(chapters_by_book)==TARGET_BOOKS,('Missing Hebrew books',sorted(TARGET_BOOKS-set(chapters_by_book)))
    verse_keys={(b,c,v) for b,c,v in conn.execute('SELECT book,chapter,verse FROM verses')}
    for b,d,eid in docs:
        if b['role']=='translation':
            for ch in chapters_by_book[b['title']]:
                a=d['text']
                if not isinstance(a,list) or len(a)<ch:continue
                for v,t in enumerate(a[ch-1],1):
                    if (b['title'],ch,v) in verse_keys and isinstance(t,str) and plaintext(t):
                        conn.execute('INSERT INTO translations VALUES(?,?,?,?,?,0)',(b['title'],ch,v,eid,t))
    for b,c,v in verse_keys:
        choices=list(conn.execute('SELECT edition FROM translations WHERE book=? AND chapter=? AND verse=?',(b,c,v)))
        preferred=[]
        for preference in CONFIG['preferences']['primary_translation']:
            preferred=[x[0] for x in choices if (preference=='Metsudah' and 'Metsudah' in edition_info[x[0]]['version_title']) or edition_info[x[0]]['version_title']==preference]
            if preferred:break
        if not preferred:
            WARN.append(dict(kind='missing_approved_translation',book=b,chapter=c,verse=v))
            continue
        conn.execute('UPDATE translations SET is_primary=1 WHERE book=? AND chapter=? AND verse=? AND edition=?',(b,c,v,sorted(preferred)[0]))

    # Merge commentary editions at segment level, retaining exact provenance; do not mix base translations.
    raw={}; leaf_nodes={}; prefix_sources={}; leaf_bases={}; article_groups={}
    for b,d,eid in sorted(docs,key=lambda x:rank(x[1]),reverse=True):
        if b['role']!='commentary':continue
        source=b['title']
        if source not in schema_cache:
            schema_cache[source]=json.loads((CACHE/'schemas'/f'{key(source)}.json').read_text(encoding='utf-8'))
        schema=schema_cache[source]
        nodes={p:n for p,n in leaves(schema['schema'])}
        bases=[x['en'] if isinstance(x,dict) else x for x in schema.get('base_text_titles',[])]
        for path,arr in arrays(d['text']):
            prefix=', '.join((source,)+path)
            node=nodes.get(path)
            if node is None:
                # Some exports flatten nested schema paths into one dictionary key.
                node=next((n for p,n in nodes.items() if ', '.join(p)==', '.join(path)),None)
            if node is None:
                WARN.append(dict(kind='unmapped_schema_leaf',source=source,path=path));continue
            leaf_nodes[prefix]=node;prefix_sources[prefix]=source
            leaf_bases[prefix]=bases
            for loc,text in segments(arr):
                identity=(prefix,loc)
                entry=raw.setdefault(identity,dict(source=source,prefix=prefix,loc=loc,category=b['source_category'],sort_order=b['sort_order'],langs={}))
                entry['langs'].setdefault(d['language'],(text,eid))
    # One note per commentary segment; complete essay leaf per note for paragraph-based works.
    notes={}; resolver=collections.defaultdict(dict)
    for (prefix,loc),entry in raw.items():
        names=leaf_nodes[prefix].get('sectionNames',[])
        is_essay=names==['Paragraph'] and not DIRECT_ONLY
        note_loc=() if is_essay else loc
        ident=(prefix,note_loc)
        nid='n-'+key(prefix+' '+':'.join(map(str,note_loc)))
        note=notes.setdefault(nid,dict(id=nid,source=entry['source'],ref=prefix+(' '+':'.join(map(str,note_loc)) if note_loc else ''),category=entry['category'],sort_order=entry['sort_order'],parts={'he':[],'en':[]},editions={'he':[],'en':[]}))
        for lang,(text,eid) in entry['langs'].items():
            note['parts'][lang].append((loc,text));note['editions'][lang].append(eid)
        resolver[prefix][loc]=nid
    attachments=set();resolved_direct=0
    def root_books(title,seen=frozenset()):
        if title in CONFIG['preferences']['book_order']:return {title}
        if title in seen:return set()
        if title not in schema_cache:
            path=CACHE/'schemas'/f'{key(title)}.json'
            if not path.exists():return set()
            schema_cache[title]=json.loads(path.read_text(encoding='utf-8'))
        result=set()
        for b in schema_cache[title].get('base_text_titles',[]):
            result.update(root_books(b['en'] if isinstance(b,dict) else b,seen|{title}))
        return result
    for (prefix,loc),entry in raw.items():
        names=leaf_nodes[prefix].get('sectionNames',[])
        if len(names)>=2 and names[:2]==['Chapter','Verse'] and len(loc)>=2:
            bases=leaf_bases[prefix]
            path=prefix[len(entry['source']):].strip(', ')
            roots=root_books(entry['source'])
            # Named book nodes explicitly use chapter/verse addressing, including supercommentaries.
            named=next((b for b in CONFIG['preferences']['book_order'] if path==b or path.startswith(b+', ')),None)
            base=named if named and (not bases or named in roots) else next(iter(roots)) if len(roots)==1 else None
            if base and (base,loc[0],loc[1]) in verse_keys:
                nid=resolver[prefix][loc]
                attachments.add((nid,base,loc[0],loc[1],'schema',f'{base} {loc[0]}:{loc[1]}',prefix+' '+':'.join(map(str,loc))))
                resolved_direct+=1
    print(f'Normalized {len(raw)} commentary segments; direct attachments {resolved_direct}',flush=True)

    verses_by_book=collections.defaultdict(list)
    for b,c,v in sorted(verse_keys):verses_by_book[b].append((c,v))
    source_set={s['title'] for s in CONFIG['sources'] if s['status']=='include'}
    def source_root(text):
        parts=text.split(', ')
        for n in range(len(parts),0,-1):
            candidate=', '.join(parts[:n])
            if candidate in source_set:return candidate
        return None
    link_counts=collections.Counter();unresolved=[]
    for file in sorted((CACHE/'links').glob('links*.csv')):
        if not re.fullmatch(r'links\d+\.csv',file.name):continue
        with file.open(encoding='utf-8-sig',newline='') as f:
            for row in csv.DictReader(f):
                if DIRECT_ONLY and row['Conection Type'].strip().lower()!='commentary':continue
                side=1 if row['Text 1'] in TARGET_BOOKS else 2 if row['Text 2'] in TARGET_BOOKS else 0
                if not side:continue
                other=3-side;source=source_root(row[f'Text {other}'])
                if source is None:continue
                bp,start,end=parse_address(row[f'Citation {side}'])
                if bp not in TARGET_BOOKS:continue
                targets=[(bp,c,v) for c,v in verses_by_book[bp] if in_range((c,v),start,end)]
                if not targets:continue
                nr=row[f'Citation {other}'];np,ns,ne=parse_address(nr)
                typ=row['Conection Type']
                # Ignore cross-citations from verse-commentaries outside the selected books.
                sp=CACHE/'schemas'/f'{key(source)}.json'
                if source not in schema_cache and sp.exists():
                    schema_cache[source]=json.loads(sp.read_text(encoding='utf-8'))
                sch=schema_cache.get(source,{})
                candidate_node=next((node for path,node in leaves(sch.get('schema',{})) if ', '.join((source,)+path)==np),{})
                if candidate_node.get('sectionNames',[])[:2]==['Chapter','Verse'] and typ not in ('commentary','Commentary'):continue
                if np not in resolver:
                    unresolved.append(dict(base=row[f'Citation {side}'],ref=nr,source=source,type=typ,reason='No selected export leaf'))
                    continue
                names=leaf_nodes[np].get('sectionNames',[])
                # For verse-addressed works, reference links are cross-citations, not extra commentary attachments.
                if names[:2]==['Chapter','Verse'] and typ not in ('commentary','Commentary'):continue
                nids={nid for loc,nid in resolver[np].items() if in_range(loc,ns,ne)}
                if not nids:
                    unresolved.append(dict(base=row[f'Citation {side}'],ref=nr,source=source,type=typ,reason='No selected text at reference'))
                for nid in nids:
                    for book,ch,v in targets:
                        attachments.add((nid,book,ch,v,typ,row[f'Citation {side}'],nr));link_counts[typ]+=1
        print('Read',file.name,flush=True)
    attached={a[0] for a in attachments}
    for nid in attached:
        n=notes[nid]
        values=[]
        for lang in ('he','en'):
            parts=sorted(n['parts'][lang])
            values.append('\n'.join('<div class="note-paragraph">'+clean(t)+'</div>' for _,t in parts))
        conn.execute('INSERT INTO notes VALUES(?,?,?,?,?,?,?,?,?)',(nid,n['source'],n['ref'],n['category'],n['sort_order'],*values,json.dumps(sorted(set(n['editions']['he']))),json.dumps(sorted(set(n['editions']['en'])))))
    conn.executemany('INSERT OR IGNORE INTO note_refs VALUES(?,?,?,?,?,?,?)',sorted(attachments))
    conn.commit()
    report=dict(attachment_policy=CONFIG['preferences'].get('attachment_policy','all_approved_links'),verses=len(verse_keys),notes=len(attached),attachments=len(attachments),link_types=dict(link_counts),warnings=WARN,unresolved_links=unresolved)
    (OUT/'build-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('warnings','unresolved_links')}))
    generate(conn,edition_info,chapters_by_book)

CSS='''body {font-family:serif; margin:5%; color:#111; background:#fff; line-height:1.5;}
h1 {font-size:1.25em; line-height:1.35; margin:1em 0;}
h2 {font-size:1.1em; line-height:1.4;}
.verse {margin:1.2em 0 1.7em; padding-bottom:1em; border-bottom:1px solid #ccc;}
.hebrew {font-family:"Noto Serif Hebrew","David","Times New Roman",serif; font-size:1em; text-align:right; line-height:1.8; margin:.4em 0;}
.translation {font-size:1em; text-align:left; line-height:1.65; margin:.55em 0;}
.verse-heading {display:flex; justify-content:space-between; align-items:baseline; margin:.65em 0 .35em; font-size:1.15em; font-weight:bold; line-height:1.4;}
.comment-segment {margin:.7em 0;}
p, .translation, .note-he, .note-en {text-indent:0;}
a {color:inherit; text-decoration:underline;}
.note-links {font-family:sans-serif; font-size:.78em; line-height:1.8; text-align:left; margin:.65em 0 0;}
.note-links a {display:inline-block; margin-right:.65em;}
aside {margin:1.5em 0; border-top:1px solid #bbb; padding-top:.7em;}
.commentary-note {margin:1.5em 0; padding:.6em 0; border-top:1px solid #bbb;}
.note-title {font-family:sans-serif; font-size:.8em; font-weight:bold; line-height:1.45; margin:0 0 .7em; text-align:left;}
.note-he {font-family:"Noto Serif Hebrew","David","Times New Roman",serif; text-align:right; font-size:1em; line-height:1.8;}
.note-en {text-align:left; font-size:1em; line-height:1.65;}
.note-paragraph {margin:.65em 0;}
.ketiv {font-size:.85em;}
.embedded-footnote {font-size:.85em;}
.colophon {overflow-wrap:anywhere; font-size:.9em;}
.backlinks {font-family:sans-serif; font-size:.75em; margin:1em 0 0;}
'''

def xhtml(title,body):
    return '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en"><head><title>'+e(title)+'</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>'+body+'</body></html>'

def hebrew_number(number):
    if not 1 <= number <= 999:
        raise ValueError('Verse number must be between 1 and 999')
    letters=''
    for value, letter in ((400,'ת'),(300,'ש'),(200,'ר'),(100,'ק')):
        while number >= value:
            letters+=letter
            number-=value
    if number in (15,16):
        letters+={15:'טו',16:'טז'}[number]
    else:
        for value,letter in ((90,'צ'),(80,'פ'),(70,'ע'),(60,'ס'),(50,'נ'),(40,'מ'),(30,'ל'),(20,'כ'),(10,'י'),(9,'ט'),(8,'ח'),(7,'ז'),(6,'ו'),(5,'ה'),(4,'ד'),(3,'ג'),(2,'ב'),(1,'א')):
            if number >= value:
                letters+=letter
                number-=value
    return letters+'׳' if len(letters)==1 else letters[:-1]+'״'+letters[-1]

def translation_label(name):
    if 'Metsudah' in name:return 'Metsudah'
    if name=='The Koren Jerusalem Bible':return 'Koren'
    if 'Silverstein' in name:return 'R. Shraga Silverstein'
    if 'Mike Feuer' in name:return 'R. Mike Feuer'
    if 'Torah Yesharah' in name:return 'Torah Yesharah'
    return name

def generate(conn,editions,chapters_by_book=None):
    conn.row_factory=sqlite3.Row
    if chapters_by_book is None:
        chapters_by_book={book:[r[0] for r in conn.execute('SELECT DISTINCT chapter FROM verses WHERE book=? ORDER BY chapter',(book,))] for book in BOOK_ORDER}
    book_dir=OUT/'books';book_dir.mkdir(exist_ok=True)
    preview=ROOT/'work/preview';preview.mkdir(exist_ok=True)
    summary=[]
    for book in BOOK_ORDER:
        chapters=chapters_by_book[book]
        bs=slug(book);files={'style.css':re.sub(r'direction:(?:rtl|ltr); ?','',CSS)};used=set();total_notes=set();total_trans=collections.Counter();book_notes=collections.Counter()
        title=book
        intro=f'<h1>{e(book)}</h1><p>Complete book · {len(chapters)} chapters</p><p><a href="nav.xhtml">Contents</a></p>'
        files['title.xhtml']=xhtml(title,intro)
        for ch in chapters:
            body=[f'<h1>{e(book)} {ch}</h1>'];aside=[]
            chapter_notes={r['id']:r for r in conn.execute('SELECT DISTINCT n.* FROM notes n JOIN note_refs r ON r.note_id=n.id WHERE r.book=? AND r.chapter=? ORDER BY n.sort_order,n.ref',(book,ch))}
            translations_by_verse=collections.defaultdict(list)
            for translation in conn.execute('SELECT * FROM translations WHERE book=? AND chapter=? ORDER BY verse,is_primary DESC,edition',(book,ch)):
                translations_by_verse[translation['verse']].append(translation)
            note_ids_by_verse=collections.defaultdict(list)
            for note_ref in conn.execute('SELECT DISTINCT r.verse,n.id,n.sort_order,n.ref FROM note_refs r JOIN notes n ON n.id=r.note_id WHERE r.book=? AND r.chapter=? ORDER BY r.verse,n.sort_order,n.ref',(book,ch)):
                note_ids_by_verse[note_ref['verse']].append(note_ref['id'])
            backlinks=collections.defaultdict(list)
            for row in conn.execute('SELECT * FROM verses WHERE book=? AND chapter=? ORDER BY verse',(book,ch)):
                v=row['verse'];vid=f'v-{bs}-{ch}-{v}';used.add(row['hebrew_edition'])
                body.append(f'<section class="verse" id="{vid}" data-ref="{e(book)} {ch}:{v}"><h2 class="verse-heading" dir="ltr" style="display:flex; justify-content:space-between; font-size:1.15em;"><span lang="en" xml:lang="en" dir="ltr">Verse {v}</span> <span lang="he" xml:lang="he" dir="rtl">פסוק {hebrew_number(v)}</span></h2><p class="hebrew" lang="he" xml:lang="he" dir="rtl">{row["hebrew"]}</p>')
                translations=translations_by_verse[v]
                primary=next((t for t in translations if t['is_primary']),None)
                if primary is not None:
                    info=editions[primary['edition']];used.add(primary['edition']);total_trans[info['version_title']]+=1
                    body.append(f'<div class="translation" lang="en" xml:lang="en" dir="ltr" data-edition="{primary["edition"]}" data-translation-label="{e(translation_label(info["version_title"]))}" data-primary="true">{clean(primary["text"])}</div>')
                links=[]
                for t in translations:
                    if t['is_primary'] or primary is None:continue
                    info=editions[t['edition']];used.add(t['edition']);nid=f't-{ch}-{v}-{t["edition"]}'
                    links.append(f'<a id="r-{nid}" epub:type="noteref" href="#{nid}" data-category="translation" data-source="{e(translation_label(info["version_title"]))}">{e(translation_label(info["version_title"]))}</a>')
                    aside.append(f'<aside epub:type="footnote" id="{nid}" data-category="translation" data-source="{e(translation_label(info["version_title"]))}" data-edition="{t["edition"]}"><div lang="en" xml:lang="en" dir="ltr">{clean(t["text"])}</div><p class="backlinks"><a href="#{vid}">Back to verse {v}</a></p></aside>')
                nids=note_ids_by_verse[v]
                nids.sort(key=lambda nid:(chapter_notes[nid]['sort_order'],natural(chapter_notes[nid]['ref'])))
                # Every marker points directly to a full note, including in popup readers.
                grouped=collections.defaultdict(list)
                for nid in nids:grouped[chapter_notes[nid]['source']].append(nid);backlinks[nid].append(vid)
                for source,ids in grouped.items():
                    gid='g-'+key(f'{book}:{ch}:{v}:{source}')
                    cat=category_slug(chapter_notes[ids[0]]['category'])
                    heading=source if source.endswith(' on '+book) else source+' on '+book
                    heading+=f' {ch}:{v}'
                    links.append(f'<a epub:type="noteref" href="#{gid}" data-source="{e(source)}" data-category="{cat}">{e(source)}</a>')
                    contents=[f'<aside epub:type="footnote" id="{gid}" class="commentary-note" data-source="{e(source)}" data-category="{cat}" data-ref="{e(heading)}"><p class="note-title">{e(heading)}</p>']
                    for lang in ('he','en'):
                        segments=[];edition_ids=set()
                        for nid in ids:
                            n=chapter_notes[nid]
                            if not n[lang]:continue
                            eids=json.loads(n[lang+'_edition']);used.update(eids);edition_ids.update(eids)
                            segments.append(f'<div class="comment-segment" data-note-id="{nid}" data-ref="{e(n["ref"])}" data-editions="{" ".join(eids)}">{n[lang]}</div>')
                        if segments:
                            contents.append(f'<div class="note-{lang}" lang="{lang}" xml:lang="{lang}" dir="{"rtl" if lang=="he" else "ltr"}" data-editions="{" ".join(sorted(edition_ids))}">'+''.join(segments)+'</div>')
                    for nid in ids:
                        if nid not in total_notes:book_notes[source]+=1
                        total_notes.add(nid)
                    contents.append(f'<p class="backlinks"><a href="#{vid}">Back to verse {v}</a> / <a href="#index-{bs}-{ch}-{v}">Other notes</a></p></aside>')
                    aside.append(''.join(contents))
                if links:
                    index_id=f'index-{bs}-{ch}-{v}'
                    body.append(f'<p class="note-links"><a epub:type="noteref" href="#{index_id}" data-category="index" data-ref="{e(book)} {ch}:{v}">Notes &amp; translations</a></p>')
                    aside.append(f'<aside epub:type="footnote" id="{index_id}" data-category="index" data-ref="{e(book)} {ch}:{v}"><p class="note-title">{e(book)} {ch}:{v} · Translations and commentary</p><div class="note-links">'+''.join('<p>'+link+'</p>' for link in links)+f'</div><p class="backlinks"><a href="#{vid}">Back to verse {v}</a></p></aside>')
                body.append('</section>')
            files[f'chapter-{ch}.xhtml']=xhtml(f'{book} {ch}',''.join(body)+'<section epub:type="endnotes"><h2>Translations and commentary</h2>'+''.join(aside)+'</section>')
        credits=['<div class="colophon"><h1>Sources and credits</h1><p>Text supplied by Sefaria’s public export. Edition titles, licenses, and sources below are reproduced from its metadata. Prepared for personal use.</p><p>Changes: removed cantillation from the base text if present; rearranged qere/ketiv for display; sanitized source markup; selected commentary editions by segment, preferring Metsudah where available. Original text and provenance are retained in the build database.</p>']
        for eid in sorted(used,key=lambda x:(editions[x]['title'],editions[x]['language'],editions[x]['version_title'])):
            d=editions[eid]
            credits.append(f'<section id="{eid}"><h2>{e(d["title"])}</h2><p>{e(d["version_title"])} · {d["language"]}</p><p>License: {e(d["license"])}</p><p>Source: {e(d["source_url"])}</p><p>Export: <a href="{e(d["export_url"])}">Sefaria edition JSON</a></p></section>')
        credits.append('</div>');files['credits.xhtml']=xhtml('Sources and credits',''.join(credits))
        toc=''.join(f'<li><a href="chapter-{ch}.xhtml">{e(book)} {ch}</a></li>' for ch in chapters)
        files['nav.xhtml']=xhtml('Contents',f'<nav epub:type="toc" id="toc"><h1>Contents</h1><ol>{toc}</ol></nav>')
        uid='urn:tanach:book:'+bs+':'+hashlib.sha256(json.dumps(CONFIG['preferences'],sort_keys=True).encode()).hexdigest()[:12]
        navpoints=''.join(f'<navPoint id="ch-{ch}" playOrder="{i+1}"><navLabel><text>{e(book)} {ch}</text></navLabel><content src="chapter-{ch}.xhtml"/></navPoint>' for i,ch in enumerate(chapters))
        files['toc.ncx']=f'<?xml version="1.0" encoding="UTF-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="{uid}"/></head><docTitle><text>{e(title)}</text></docTitle><navMap>{navpoints}</navMap></ncx>'
        manifest=[]
        for name in files:
            mt='text/css' if name.endswith('.css') else 'application/x-dtbncx+xml' if name.endswith('.ncx') else 'application/xhtml+xml'
            prop=' properties="nav"' if name=='nav.xhtml' else ''
            manifest.append(f'<item id="{name.replace(".","-")}" href="{name}" media-type="{mt}"{prop}/>')
        spine=''.join(f'<itemref idref="{name.replace(".","-")}"/>' for name in ['title.xhtml','nav.xhtml']+[f'chapter-{ch}.xhtml' for ch in chapters]+['credits.xhtml'])
        idx=CONFIG['preferences']['book_order'].index(book)+1
        files['package.opf']=f'<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="pub-id">{uid}</dc:identifier><dc:title>{e(title)}</dc:title><dc:language>he</dc:language><dc:language>en</dc:language><dc:creator>Tanach; commentaries from Sefaria</dc:creator><meta property="dcterms:modified">2026-09-17T00:00:00Z</meta><meta name="calibre:series" content="Tanach"/><meta name="calibre:series_index" content="{idx}"/><meta property="belongs-to-collection" id="series">Tanach</meta><meta refines="#series" property="collection-type">series</meta><meta refines="#series" property="group-position">{idx}</meta></metadata><manifest>{"".join(manifest)}</manifest><spine toc="toc-ncx" page-progression-direction="ltr">{spine}</spine></package>'
        target=book_dir/f'{idx:02d}-{bs}.epub'
        with zipfile.ZipFile(target,'w') as z:
            z.writestr('mimetype','application/epub+zip',compress_type=zipfile.ZIP_STORED)
            z.writestr('META-INF/container.xml','<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',compress_type=zipfile.ZIP_DEFLATED)
            for name,value in files.items():z.writestr('EPUB/'+name,value.encode('utf-8'),compress_type=zipfile.ZIP_DEFLATED)
        pdir=preview/bs;pdir.mkdir(exist_ok=True)
        for name,value in files.items():
            if name.endswith(('.xhtml','.css')):(pdir/name).write_text(value,encoding='utf-8')
        summary.append(dict(book=book,chapters=chapters,verses=conn.execute('SELECT count(*) FROM verses WHERE book=?',(book,)).fetchone()[0],notes=len(total_notes),sources=dict(book_notes),primary_translations=dict(total_trans),bytes=target.stat().st_size,file=target.name))
    (OUT/'full-coverage.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Generated',len(summary),'complete book EPUBs',flush=True)

def category_slug(c):return {'Rishonim on Tanakh':'rishon','Acharonim on Tanakh':'acharon','Modern Commentary on Tanakh':'modern'}.get(c,'other')

if __name__=='__main__':main()
