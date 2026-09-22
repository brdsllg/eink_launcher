import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
p=ROOT/'outputs/source-selection.json'
c=json.loads(p.read_text(encoding='utf-8'))
c['preferences']['presentation']={'page_progression':'ltr','credits':'end_only','style_revision':2,'verse_emphasis':'larger','commentary_style':'smaller_inset_with_small_title'}
p.write_text(json.dumps(c,ensure_ascii=False,indent=2),encoding='utf-8')
p=ROOT/'work/build.py';s=p.read_text(encoding='utf-8')
start=s.index("CSS='''");end=s.index("'''",start+7)+3
css='''body {font-family:serif; margin:5%; color:#111; background:#fff; line-height:1.5;}
h1 {font-size:1.25em; line-height:1.35; margin:1em 0;}
h2 {font-size:1.1em; line-height:1.4;}
.verse {margin:1.2em 0 1.7em; padding-bottom:1em; border-bottom:1px solid #ccc;}
.hebrew {font-family:"Noto Serif Hebrew","David","Times New Roman",serif; font-size:1.65em; text-align:right; line-height:1.85; margin:.4em 0;}
.translation {font-size:1.13em; text-align:left; line-height:1.65; margin:.55em 0;}
.verse-number {font-size:.6em; margin-left:.5em;}
a {color:inherit; text-decoration:underline;}
.note-links {font-family:sans-serif; font-size:.78em; line-height:1.8; text-align:left; margin:.65em 0 0;}
.note-links a {display:inline-block; margin-right:.65em;}
aside {margin:1.5em 0; border-top:1px solid #bbb; padding-top:.7em;}
.commentary-note {margin:1.5em .6em; padding:.6em .85em; border-top:0; border-right:2px solid #999;}
.note-title {font-family:sans-serif; font-size:.8em; font-weight:bold; line-height:1.45; margin:0 0 .7em; text-align:left;}
.note-he {font-family:"Noto Serif Hebrew","David","Times New Roman",serif; text-align:right; font-size:1.08em; line-height:1.8;}
.note-en {text-align:left; font-size:.95em; line-height:1.65;}
.note-paragraph {margin:.65em 0;}
.ketiv {font-size:.85em;}
.embedded-footnote {font-size:.85em;}
.colophon {overflow-wrap:anywhere; font-size:.9em;}
.backlinks {font-family:sans-serif; font-size:.75em; margin:1em 0 0;}
'''
s=s[:start]+"CSS='''"+css+"'''"+s[end:]
s=s.replace('page-progression-direction="rtl"','page-progression-direction="ltr"')
s=s.replace('2026-09-14T00:00:00Z','2026-09-15T00:00:00Z')
s=s.replace('</div><p class="label">{e(info["version_title"])}</p>','</div>')
s=s.replace("                    contents.append('<p class=\"label\">'+'; '.join(e(editions[x]['version_title']) for x in ids)+'</p>')\n",'')
s=s.replace('<h3>','<p class="note-title">').replace('</h3>','</p>')
s=s.replace('id="{nid}" data-source="{e(n["source"])}"','id="{nid}" class="commentary-note" data-source="{e(n["source"])}"')
s=s.replace('{e(info["version_title"])}</a>','{e(translation_label(info["version_title"]))}</a>')
s=s.replace('· {e(info["version_title"])}</p>','· {e(translation_label(info["version_title"]))}</p>')
s=s.replace('Translations &amp; commentary ({len(nids)} notes)','Notes &amp; translations')
intro_start=s.index("        intro=f'");intro_end=s.index('\n',intro_start)
s=s[:intro_start]+'''        intro=f'<h1>{e(book)}</h1><p>Sample · Chapters {", ".join(map(str,chapters))}</p><p><a href="nav.xhtml">Contents</a></p>' '''.rstrip()+s[intro_end:]
helper='''def translation_label(name):
    if 'Metsudah' in name:return 'Metsudah'
    if name=='The Koren Jerusalem Bible':return 'Koren'
    if 'Silverstein' in name:return 'R. Shraga Silverstein'
    if 'Mike Feuer' in name:return 'R. Mike Feuer'
    if 'Torah Yesharah' in name:return 'Torah Yesharah'
    return name

'''
s=s.replace('def generate(conn,editions):',helper+'def generate(conn,editions):')
p.write_text(s,encoding='utf-8')
print('Updated display styles, credits placement and LTR page progression.')
