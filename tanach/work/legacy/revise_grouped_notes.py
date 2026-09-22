import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'work/build.py'
s=p.read_text(encoding='utf-8')
s=s.replace('.verse-heading {display:block; margin:.65em 0 .35em; font-size:1.35em; font-weight:bold; line-height:1.4;}', '.verse-heading {display:flex; justify-content:space-between; align-items:baseline; margin:.65em 0 .35em; font-size:1.15em; font-weight:bold; line-height:1.4;}\n.comment-segment {margin:.7em 0;}')
start=s.index('                body.append(f\'<section class="verse"')
end=s.index('\n                translations=',start)
s=s[:start]+'''                body.append(f'<section class="verse" id="{vid}" data-ref="{e(book)} {ch}:{v}"><h2 class="verse-heading" dir="ltr" style="display:flex; justify-content:space-between; font-size:1.15em;"><span lang="en" xml:lang="en" dir="ltr">Verse {v}</span> <span lang="he" xml:lang="he" dir="rtl">פסוק {hebrew_number(v)}</span></h2><p class="hebrew" lang="he" xml:lang="he" dir="rtl">{row["hebrew"]}</p>')'''+s[end:]
s=s.replace('data-edition="{primary["edition"]}">','data-edition="{primary["edition"]}" data-translation-label="{e(translation_label(info["version_title"]))}" data-primary="true">')
s=s.replace('data-source="{e(info["version_title"])}"','data-source="{e(translation_label(info["version_title"]))}"')
s=s.replace('<p class="note-title">{e(book)} {ch}:{v} · {e(translation_label(info["version_title"]))}</p>','')
start=s.index('                for source,ids in grouped.items():')
end=s.index('                if links:',start)
s=s[:start]+'''                for source,ids in grouped.items():
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
'''+s[end:]
start=s.index('            for nid,n in sorted(chapter_notes.items()')
end=s.index('            files[f\'chapter-',start)
s=s[:start]+s[end:]
p.write_text(s,encoding='utf-8')
p=root/'outputs/source-selection.json'
c=json.loads(p.read_text(encoding='utf-8'))
c['preferences']['presentation'].update(style_revision=5,verse_heading='single_row_1.15em',commentary_grouping='source_per_verse',translation_labels='selector_only')
p.write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8')
