"""Download public Sefaria data with content hashes; downstream build is offline."""
import concurrent.futures as cf
import datetime, hashlib, json, sys, time, urllib.request, urllib.parse
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT/'work/cache'
BASE = 'https://storage.googleapis.com/sefaria-export/'

def fetch(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.with_suffix(path.suffix+'.meta.json').exists():
        return json.loads(path.with_suffix(path.suffix+'.meta.json').read_text())
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent':'Personal-Tanach-EPUB/0.1'})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
                meta = dict(url=url, sha256=hashlib.sha256(data).hexdigest(), bytes=len(data),
                    fetched_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), etag=r.headers.get('ETag'), last_modified=r.headers.get('Last-Modified'))
            temp = path.with_suffix(path.suffix+'.part')
            temp.write_bytes(data)
            temp.replace(path)
            path.with_suffix(path.suffix+'.meta.json').write_text(json.dumps(meta, indent=2))
            return meta
        except Exception:
            if attempt == 2: raise
            time.sleep(attempt+1)

def key(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24]

def batch(items):
    failures=[]
    with cf.ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(fetch,u,p):(u,p) for u,p in items}
        for i,f in enumerate(cf.as_completed(futures),1):
            u,p=futures[f]
            try: f.result()
            except Exception as e: failures.append(dict(url=u,path=str(p),error=str(e)))
            if i%50==0: print(f'{i}/{len(items)} downloaded or cached', flush=True)
    print(f'Finished {len(items)} requests; failures: {len(failures)}',flush=True)
    return failures

if __name__=='__main__':
    mode=sys.argv[1]
    if mode=='catalog':
        failures=batch([('https://raw.githubusercontent.com/Sefaria/Sefaria-Export/master/books.json',CACHE/'books.json'),(BASE+'table_of_contents.json',CACHE/'table_of_contents.json')])
        if failures:raise RuntimeError(failures)
        raise SystemExit(0)
    config=json.loads((ROOT/'outputs/source-selection.json').read_text(encoding='utf-8'))
    if mode=='inspect':
        items=[(BASE+'schemas/'+urllib.parse.quote(t.replace(' ','_'),safe='')+'.json',CACHE/'schemas'/f'{key(t)}.json') for t in ['Rashi on Genesis','Birkat Asher on Torah','Genesis','Ruth','Covenant and Conversation; Genesis; The Book of the Beginnings']]
        catalog=json.loads((CACHE/'books.json').read_text())['books']
        for b in catalog:
            if (b['title']=='Ruth' and b['versionTitle'] in ('Tanach with Nikkud',"Tanach with Ta'amei Hamikra",'The Koren Jerusalem Bible')) or (b['title']=='Rashi on Genesis' and b['versionTitle']!='merged' and b['language']=='English'):
                items.append((b['json_url'], CACHE/'texts'/f"{key(b['json_url'])}.json"))
        items.append(('https://storage.googleapis.com/storage/v1/b/sefaria-export/o?prefix=links%2F&fields=items(name,size,generation),nextPageToken', CACHE/'link-list.json'))
    elif mode=='schemas':
        titles=config['preferences']['book_order']+[s['title'] for s in config['sources'] if s['status']=='include']
        items=[(BASE+'schemas/'+urllib.parse.quote(t.replace(' ','_'),safe='')+'.json', CACHE/'schemas'/f'{key(t)}.json') for t in titles]
    elif mode=='texts':
        plan=json.loads((CACHE/'download-plan.json').read_text(encoding='utf-8'))
        items=[(b['json_url'],CACHE/'texts'/f"{key(b['json_url'])}.json") for b in plan]
    elif mode=='links':
        listing=json.loads((CACHE/'link-list.json').read_text())
        assert not listing.get('nextPageToken'), 'Paginate bucket listing before downloading'
        import re
        items=[(BASE+x['name']+'?generation='+x['generation'],CACHE/x['name']) for x in listing['items'] if re.fullmatch(r'links/links\d+\.csv',x['name'])]
    else: raise ValueError(mode)
    failures=batch(items)
    (CACHE/f'{mode}-failures.json').write_text(json.dumps(failures,indent=2))
