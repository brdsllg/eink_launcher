"""Fetch EPUBCheck and a Java runtime for validate.py (unpacked, not installed).

Idempotent: release metadata is fetched once into work/cache/ (with sidecars),
downloaded archives are reused when their SHA-256 matches the release digest,
and unpacked tools are skipped when a working binary is already present.
Works on Windows, macOS and Linux: the Temurin JDK archive matching this
OS/architecture is picked from the release assets and verified before unpack.

Usage:
    python -X utf8 work/get_validation_tools.py [--tools-dir DIR]
Default tools dir is this segment's work/tools; talmud/work/sync.py invokes
this script with its own tools dir so each segment stays self-sufficient.
"""
import argparse,hashlib,json,platform,subprocess,sys,tarfile,zipfile
from pathlib import Path
from sync import CACHE,ROOT,fetch
JAVA_API='https://api.github.com/repos/adoptium/temurin21-binaries/releases/latest'
EPUBCHECK_API='https://api.github.com/repos/w3c/epubcheck/releases/latest'
def release(name,url):
    path=CACHE/f'{name}-release.json'
    if not path.exists():fetch(url,path)
    return json.loads(path.read_text(encoding='utf-8'))
def digest(asset):
    d=asset.get('digest') or ''
    return d.split(':',1)[1] if d.startswith('sha256:') else None
def java_pick(rel):
    if isinstance(rel,list):  # Adoptium API v3 shape (older caches)
        pkg=rel[0]['binary']['package']
        return pkg['link'],pkg.get('checksum')
    os_={'win32':'windows','darwin':'mac','linux':'linux'}.get(sys.platform)
    arch={'x86_64':'x64','amd64':'x64','aarch64':'aarch64','arm64':'aarch64'}.get(platform.machine().lower())
    if not os_ or not arch:raise SystemExit(f'Unsupported platform: {sys.platform}/{platform.machine()}')
    ext='.zip' if os_=='windows' else '.tar.gz'
    token=f'OpenJDK21U-jdk_{arch}_{os_}_hotspot_'
    for a in rel['assets']:
        if a['name'].startswith(token) and a['name'].endswith(ext):
            return a['browser_download_url'],digest(a)
    raise SystemExit(f'No Temurin JDK asset for {arch}/{os_} in release {rel.get("tag_name")}')
def epubcheck_pick(rel):
    for a in rel.get('assets',[]):
        if a['name'].startswith('epubcheck') and a['name'].endswith('.zip'):
            return a['browser_download_url'],digest(a)
    raise SystemExit('No EPUBCheck zip asset in release metadata')
def find(binary,dest):
    pats=('java.exe','java') if binary=='java' and sys.platform=='win32' else ((binary,) if binary!='java' else ('java','java.exe'))
    for pat in pats:
        for p in sorted(dest.rglob(pat)):
            if p.is_file():return p
    return None
def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for chunk in iter(lambda:f.read(1<<20),b''):h.update(chunk)
    return h.hexdigest()
def verify(path,want):
    if not want:
        print(f'WARNING: no SHA-256 digest for {path.name}; skipping verification',flush=True);return
    got=sha(path)
    assert got==want,(f'SHA-256 mismatch for {path.name}',got,want)
def need(path,want):
    if not path.exists():return True
    if want and sha(path)!=want:
        print(f'Stale {path.name}; re-downloading',flush=True)
        path.unlink();return True
    return False
def unpack(archive,dest):
    dest.mkdir(parents=True,exist_ok=True)
    if archive.name.endswith('.tar.gz'):
        with tarfile.open(archive) as t:
            for m in t.getmembers():
                assert not m.name.startswith('/') and '..' not in Path(m.name).parts,m.name
            try:t.extractall(dest,filter='data')
            except TypeError:t.extractall(dest)  # Python < 3.12 has no filters
    else:
        with zipfile.ZipFile(archive) as z:
            for n in z.namelist():
                assert (dest/n).resolve().is_relative_to(dest.resolve()),n
            z.extractall(dest)
if __name__=='__main__':
    ap=argparse.ArgumentParser(description='Fetch and unpack EPUBCheck + Java for validate.py.')
    ap.add_argument('--tools-dir',default=str(ROOT/'work'/'tools'))
    tools=Path(ap.parse_args().tools_dir).resolve()
    java=find('java',tools/'java');jar=find('epubcheck.jar',tools/'epubcheck')
    if java and jar:
        print(f'Validation tools already present: {java} + {jar}');raise SystemExit(0)
    wanted=[]
    if not java:
        url,want=java_pick(release('java',JAVA_API))
        path=tools/('java.zip' if url.endswith('.zip') else 'java.tar.gz')
        if need(path,want):fetch(url,path)
        wanted.append((path,want,tools/'java'))
    if not jar:
        url,want=epubcheck_pick(release('epubcheck',EPUBCHECK_API))
        path=tools/'epubcheck.zip'
        if need(path,want):fetch(url,path)
        wanted.append((path,want,tools/'epubcheck'))
    for path,want,dest in wanted:
        verify(path,want);unpack(path,dest)
    java=find('java',tools/'java');jar=find('epubcheck.jar',tools/'epubcheck')
    assert java and jar,f'Tools unpacked but binaries not found under {tools}'
    run=subprocess.run([str(java),'-version'],capture_output=True,text=True)
    assert run.returncode==0,run.stderr
    print((run.stderr or run.stdout).strip().splitlines()[0])
    run=subprocess.run([str(java),'-jar',str(jar),'--version'],capture_output=True,text=True)
    assert run.returncode==0,run.stderr
    print((run.stdout or run.stderr).strip().splitlines()[0])
    print(f'Validation tools ready: {java} + {jar}; nothing installed.')
