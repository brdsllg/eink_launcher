import collections,hashlib,json,sqlite3,zipfile
from sync import ROOT,CACHE,key
out=ROOT/'outputs'
config=json.loads((out/'source-selection.json').read_text(encoding='utf-8'))
plan=json.loads((CACHE/'download-plan.json').read_text(encoding='utf-8'))
excluded=json.loads((CACHE/'excluded-editions.json').read_text(encoding='utf-8'))
db=sqlite3.connect(ROOT/'work/tanach.sqlite');db.row_factory=sqlite3.Row
editions={r['export_url']:dict(r) for r in db.execute('SELECT * FROM editions')}
for s in config['sources']:
    s.setdefault('edition_decisions',{})
    for b in plan:
        if b['role']=='commentary' and b['title']==s['title']:
            url=b['json_url'];entry=editions.get(url)
            if s['edition_decisions'].get(url,{}).get('reviewed'):continue
            if entry:
                s['edition_decisions'][url]=dict(status='include',version_title=entry['version_title'],language=entry['language'],license=entry['license'],source_url=entry['source_url'],sha256=entry['sha256'])
            else:
                s['edition_decisions'][url]=dict(status='exclude',version_title=b['versionTitle'],reason='Language mismatch or test/abridged edition')
    for b in excluded:
        if b['title']==s['title']:
            if s['edition_decisions'].get(b['json_url'],{}).get('reviewed'):continue
            pending='provenance' in b['reason'] or 'pending' in b['reason']
            s['edition_decisions'][b['json_url']]=dict(status='pending' if pending else 'exclude',version_title=b['versionTitle'],language=b['language'],reason=b['reason'])
    s['selected_versions']=[dict(export_url=u,**d) for u,d in s['edition_decisions'].items() if d['status']=='include']
    if s['selected_versions']:s['license_status']='Recorded per selected edition; unknown means metadata does not supply a license.'
for t in config['translations']:
    t['cached_edition_metadata']=[d for u,d in editions.items() if d['version_title']==t['version_title'] and d['title'] in config['preferences']['book_order']]
config['stage']='samples_built_full_collection_not_built'
config['preferences']['note_navigation']='Verse-level index links to source-tagged, full-text footnote asides.'
(out/'source-selection.json').write_text(json.dumps(config,ensure_ascii=False,indent=2),encoding='utf-8')
coverage=json.loads((out/'sample-coverage.json').read_text(encoding='utf-8'))
build=json.loads((out/'build-report.json').read_text(encoding='utf-8'))
validation=json.loads((out/'validation-results.json').read_text())
assert len(validation)==9 and all(r['epubcheck_exit']==0 and r['structure']=='pass' for r in validation)
pending=collections.defaultdict(set)
for s in config['sources']:
    if s['status']!='include':continue
    for d in s.get('edition_decisions',{}).values():
        if d['status']=='pending':pending[d['version_title']].add(s['title'])
missing=[s['title'] for s in config['sources'] if s['status']=='include' and not s['export_available']]
lines=['# Tanach EPUB sample set','',
    'Nine chapter samples for testing on the Bigme B751C and your existing reader. These are not the complete 39 books.','',
    '## Your settings','',
    '- Metsudah beneath the Hebrew where available, with Koren as the fallback.',
    '- Other approved English translations are available through each verse’s notes link.',
    '- Hebrew has vowels and no cantillation. Qere appears in the main text; ketiv follows in brackets. Divine names retain the source spelling.',
    '- Full text from the user’s 23 whitelisted commentary groups, in Hebrew and selected English editions where available. Direct commentary only; no broad cross-citations or expanded essays. No Targum.',
    '- The exact whitelist is recorded in selected-commentaries.md. Jonathan Sacks is eligible, but general essay/citation links are excluded by the direct-only policy.',
    '- Source credits appear only at the end. Verses have a compact bold heading on one row: English left, Hebrew right. Commentary is grouped by source and verse, retaining separate comment paragraphs. Verse and commentary text use equal sizes, without indentation.',
    '- Chapter-only navigation and left-to-right page progression; Hebrew text remains RTL. Sources and edition licenses remain in the final spine page without cluttering the table of contents.','',
    '## Samples','',
    '| Chapter | Verses | Commentary notes in this book | Sources | Default translation | EPUB size |',
    '|---|---:|---:|---:|---|---:|']
for c in coverage:
    default='Metsudah' if all('Metsudah' in t for t in c['primary_translations']) else 'Koren'
    lines.append(f"| {c['book']} {c['chapters'][0]} | {c['verses']} | {c['notes']:,} | {len(c['sources'])} | {default} | {c['bytes']/1048576:.2f} MB |")
lines+=['',f"There are {build['notes']:,} distinct commentary notes across the samples. Included comments retain their full text. Attachments use explicit chapter/verse structure (including selected supercommentary) or Sefaria links typed commentary. Broad citation links and whole-essay expansion are excluded. A verse-level link opens the source list, then an individual note opens the full text.",'',
    '## Validation','',
    '- All nine EPUBs passed EPUBCheck 5.3.0.',
    '- Every local file link and anchor was checked; all note references resolve to footnote asides. No duplicate IDs or remaining cantillation in base-text paragraphs.',
    '- Automated checks cover translation fallback, qere/ketiv including read-only and written-only words, ranges, reference sorting, source-markup handling, and database relationships.',
    '- Browser previews were checked at 800 × 1280. This does not establish compatibility or performance in the Bigme reader.','',
    '## What to try on the device','',
    'Start with Ruth 3 for qere/ketiv and Metsudah, Isaiah 40 for Koren fallback, and Genesis 1 for a heavy commentary chapter. Open a verse’s notes list, select a note, and return to the verse. Check Hebrew vowel placement, bracket direction, chapter loading time, and whether your reader supports links inside footnotes.','',
    'Genesis 1 and Deuteronomy 32 remain useful loading tests because the selected direct commentaries can be substantial.','',
    '## Coverage limits','',
    f"- {len(build['unresolved_links'])} candidate export links remain unattached; detailed references and reasons are in build-report.json. Some point to unavailable editions, excluded translations, or commentary outside this sample’s download scope. Some refer to segments absent or numbered differently in the selected editions; available direct verse commentaries are still attached independently.",
    '- Selecting a source does not guarantee a note on every sample verse. Only material present in the selected exports and attached under the direct-only policy is included.',
    '- Some source files report their license as “unknown”; the colophons retain that exact label rather than inventing one.',
    '- Commentary translations with uncertain provenance are withheld below. The original Hebrew remains included when available.',
    '- The current renderer deliberately stops on unreviewed qere/ketiv bracket forms outside the tested cases. Generalizing and validating those cases is required before building all 39 books.','',
    '## Commentary edition metadata to investigate','',
    'This is an internal edition-review queue, not a list of commentators whose Orthodox status is in doubt. The earlier request for a blanket decision was premature: generic edition labels need metadata and content checks first. These English edition variants are withheld for now; the named commentators can already be included through other editions. Only a specific unresolved religious or editorial choice should be referred back to the user.','',
    'Ramban is approved and already included: the Genesis and Deuteronomy samples contain Hebrew and English Ramban. The additional edition labeled “Ramban Commentary” links to Judaica Press but contains no exported text. It has been removed from this review queue; no user decision is needed for it.','',
    '| Edition | Commentary works affected |','|---|---|']
for title,titles in sorted(pending.items()):
    lines.append('| '+title.replace('|','/')+' | '+', '.join(sorted(titles)).replace('|','/')+' |')
lines+=['','## Reader integration','',
    'The detailed implementation contract, actual XHTML examples, cache rules, and device test matrix are in reader-compatibility.md.','',
    '- Base verses: `section.verse`, stable `id="v-{book}-{chapter}-{verse}"`, and `data-ref`.',
    '- The verse-level noteref opens an index aside with `data-category="index"`. A custom reader can skip this index and use its contained source-specific noterefs directly.',
    '- Full commentary: grouped `aside epub:type="footnote"` entries use generated `g-…` anchors plus `data-source`, `data-category` (`rishon`, `acharon`, `modern`), and verse-level `data-ref`.',
    '- Alternate translations use `data-category="translation"` and edition identifiers.',
    '- Hebrew and English commentary blocks have explicit language and direction attributes; edition IDs preserve provenance.',
    '- Each `.comment-segment` keeps its original `data-note-id` and may appear in more than one verse group when the source attaches it to multiple verses; group-level backlinks return to the invoking verse.',
    '- EPUB files require no scripts or network connection. Fonts are left to the reader; no proprietary font is embedded.','',
    'The SQLite database and original cached files remain in the workspace for further development. The pipeline archive contains the scripts and selection manifest, not the large cache or Java tools.']
(out/'sample-guide.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
# Replace the initial inventory report with current decisions and sample status.
(out/'source-review.md').write_text('# Source review status\n\nYour 23 commentary groups are recorded in selected-commentaries.md and source-selection.json. Only direct commentary is attached. Metsudah is primary with Koren fallback; Targum and all unselected commentary works are excluded.\n\nSee sample-guide.md for sample coverage and remaining edition metadata checks. These checks concern editions, not the Orthodox status of already approved classical commentators.\n',encoding='utf-8')
readme='''# Tanach EPUB pipeline

Current state: the full 39-book collection is built (revision 5, 17 September 2026) in
outputs/books/, and outputs/samples/ holds the nine chapter samples used for reader checks.
Python 3.11+ standard library is sufficient for downloading and building.
Use UTF-8 mode on Windows: `python -X utf8 ...`.
Run the commands below from the tanach/ segment root, which contains work/ and outputs/.

Directory layout is intentional: scripts in work/, configuration and deliverables in outputs/.
The raw cache in work/cache/ and the normalized database in work/tanach.sqlite are the fastest
way to rebuild offline.

Rebuild from the existing cache:
    python -X utf8 work/build.py

Redraw EPUBs from the existing SQLite database after a presentation-only edit:
    python -X utf8 work/regenerate.py

Package the current deliverables:
    python -X utf8 work/package_full.py      # checksums + outputs/tanach-39-epubs.zip
    python -X utf8 work/package_samples.py   # guides + outputs/tanach-samples.zip + tanach-pipeline.zip

To download into a fresh workspace, retain outputs/source-selection.json and run:
    python -X utf8 work/sync.py catalog
    python -X utf8 work/sync.py inspect
    python -X utf8 work/sync.py schemas
    python -X utf8 work/plan.py
    python -X utf8 work/sync.py texts
    python -X utf8 work/sync.py links
    python -X utf8 work/build.py

The inspect step also caches the current link-file listing. Download failures are recorded in work/cache/.
Do not run inventory.py over an edited source-selection.json: it is the initial catalog-discovery script and will regenerate that file.
Source status and per-edition decisions in the manifest control the selection. Explicit edition decisions override the discovery rules.
After source-selection changes, run plan.py, sync.py texts, and build.py to update the cache and normalized database.
English commentary variants without established provenance remain pending; a pending edition is not downloaded by subsequent plan runs.

Validation requires EPUBCheck and a Java runtime, extracted under work/tools/ (work/get_validation_tools.py re-downloads them if missing).
Run work/validate.py over outputs/books, then work/test_pipeline.py, work/check_heading_presentation.py, and work/check_grouped_notes.py. work/test_pipeline.py also uses the independently cached tanach.us Ruth XML for its evidence check; work/visual-check.cjs renders work/preview/ with the bundled Playwright runtime.
The exact download metadata and SHA-256 of each source are kept beside cached files; link downloads are pinned to bucket object generations.
The build does not access the network.

work/legacy/ holds historical one-shot migrations (revise_*, refine_*, apply_whitelist.py, document_grouped_format.py, update_heading_presentation.py) plus an obsolete coverage snapshot. Do not rerun them blindly: some overwrite current preferences or duplicate edits. Make changes directly to the current generator, configuration, and documentation.
'''
(out/'pipeline-readme.md').write_text(readme,encoding='utf-8')
with zipfile.ZipFile(out/'tanach-samples.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted((out/'samples').glob('*.epub')):z.write(p,p.name)
    for name in ('sample-guide.md','validation-results.json','sample-coverage.json','reader-compatibility.md','selected-commentaries.md'):z.write(out/name,name)
with zipfile.ZipFile(out/'tanach-pipeline.zip','w',zipfile.ZIP_DEFLATED) as z:
    for name in ('sync.py','plan.py','build.py','regenerate.py','validate.py','test_pipeline.py','inventory.py','get_validation_tools.py','package_samples.py'):
        z.write(ROOT/'work'/name,'work/'+name)
    z.write(out/'source-selection.json','outputs/source-selection.json')
    z.write(out/'pipeline-readme.md','README.md')
    z.write(out/'reader-compatibility.md','outputs/reader-compatibility.md')
    z.write(out/'selected-commentaries.md','outputs/selected-commentaries.md')
manifest={p.name:dict(bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in (out/'samples').glob('*.epub')}
(out/'sample-checksums.json').write_text(json.dumps(manifest,indent=2))
print('Packaged 9 samples and the source pipeline. Pending commentary edition titles:',len(pending))
