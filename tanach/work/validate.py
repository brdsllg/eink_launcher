import collections,json,posixpath,re,sqlite3,subprocess,urllib.parse,zipfile
from concurrent.futures import ThreadPoolExecutor
from xml.etree import ElementTree as ET
from sync import ROOT
out=ROOT/'outputs';books=out/'books'
java=next((ROOT/'work/tools/java').rglob('java.exe'))
jar=next((ROOT/'work/tools/epubcheck').rglob('epubcheck.jar'))
reports=ROOT/'work/validation';reports.mkdir(exist_ok=True)
results=[]
NS='{http://www.w3.org/1999/xhtml}'
def check(p):
    report=reports/(p.stem+'.json')
    run=subprocess.run([str(java),'-jar',str(jar),str(p),'-j',str(report)],capture_output=True,text=True,encoding='utf-8',errors='replace')
    (reports/(p.stem+'.txt')).write_text(run.stdout+'\n'+run.stderr,encoding='utf-8')
    print(p.name,'EPUBCheck exit',run.returncode,flush=True)
    return p.name,run.returncode
with ThreadPoolExecutor(max_workers=3) as pool:
    codes=dict(pool.map(check,sorted(books.glob('*.epub'))))
for p in sorted(books.glob('*.epub')):
    structural=[]
    with zipfile.ZipFile(p) as z:
        assert z.namelist()[0]=='mimetype' and z.getinfo('mimetype').compress_type==0
        assert z.read('mimetype')==b'application/epub+zip'
        ids={};trees={}
        for name in z.namelist():
            if name.endswith(('.xhtml','.opf','.ncx','.xml')):
                root=ET.fromstring(z.read(name));trees[name]=root
                vals=[n.attrib['id'] for n in root.iter() if 'id' in n.attrib]
                assert len(vals)==len(set(vals)),('Duplicate ID',name)
                ids[name]=set(vals)
        for name,tree in trees.items():
            for a in tree.iter():
                if 'href' not in a.attrib:continue
                href=a.attrib['href'];u=urllib.parse.urlsplit(href)
                if u.scheme:continue
                dest=posixpath.normpath(posixpath.join(posixpath.dirname(name),u.path)) if u.path else name
                assert dest in z.namelist(),('Broken file link',name,href)
                if u.fragment:assert u.fragment in ids[dest],('Broken anchor',name,href)
                if a.attrib.get('{http://www.idpf.org/2007/ops}type')=='noteref':
                    target=next(n for n in trees[dest].iter() if n.attrib.get('id')==u.fragment)
                    assert target.tag==NS+'aside'
                    assert target.attrib.get('{http://www.idpf.org/2007/ops}type')=='footnote'
                    assert len(''.join(target.itertext()).strip())>0
        for name,tree in trees.items():
            for node in tree.iter(NS+'p'):
                if node.attrib.get('class')=='hebrew':
                    assert not re.search('[\u0591-\u05af]',''.join(node.itertext()))
    results.append(dict(file=p.name,epubcheck_exit=codes[p.name],structure='pass'))
(out/'full-validation-results.json').write_text(json.dumps(results,indent=2))
assert len(results)==39,('Expected 39 EPUBs',len(results))
if any(r['epubcheck_exit'] for r in results):raise SystemExit(1)
