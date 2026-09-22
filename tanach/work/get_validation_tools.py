import hashlib,json,zipfile
from sync import CACHE,ROOT,batch
tools=ROOT/'work/tools'
release=json.loads((CACHE/'epubcheck-release.json').read_text())
java=json.loads((CACHE/'java-release.json').read_text())[0]['binary']['package']
items=[(release['assets'][0]['browser_download_url'],tools/'epubcheck.zip'),(java['link'],tools/'java.zip')]
assert not batch(items)
assert hashlib.sha256((tools/'java.zip').read_bytes()).hexdigest()==java['checksum']
for name in ('epubcheck','java'):
    dest=tools/name
    dest.mkdir(exist_ok=True)
    with zipfile.ZipFile(tools/(name+'.zip')) as z:
        for n in z.namelist():
            assert (dest/n).resolve().is_relative_to(dest.resolve())
        z.extractall(dest)
print('Validation tools unpacked locally; no installation.')
